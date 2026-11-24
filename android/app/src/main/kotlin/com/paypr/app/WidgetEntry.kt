package com.paypr.app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.view.View
import android.widget.RemoteViews
import android.widget.Toast
import es.antonborri.home_widget.HomeWidgetPlugin
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import java.math.BigDecimal
import java.util.UUID
import org.json.JSONArray
import org.json.JSONObject

private const val CHANNEL = "paypr/widget_entry"

internal object WidgetEntry {
    private const val ENABLED = "widget_keypad_enabled"
    private const val ENTRY_CONTEXT = "widget_entry_context"
    private const val CHOICES_PER_PAGE = 2
    private const val RECENT_CATEGORY_LIMIT = 5
    private val detailsPages = setOf("details", "wallet", "destination")
    private val saving = mutableSetOf<String>()

    private data class Choice(val id: String, val name: String)

    private class EntryContext(private val data: JSONObject) {
        val user = data.getString("user")
        val company = data.getString("company")
        val name = data.optString("name")
        val defaultWallet = data.optString("default_wallet")
        val scope = "$user/$company"

        fun choices(key: String): List<Choice> {
            val items = data.getJSONArray(key)
            return List(items.length()) { index ->
                val item = items.getJSONObject(index)
                Choice(item.getString("id"), item.getString("name"))
            }
        }
    }

    private fun entryContext(data: SharedPreferences): EntryContext? {
        if (!data.getBoolean(ENABLED, false)) return null
        val raw = data.getString(ENTRY_CONTEXT, null) ?: return null
        return EntryContext(JSONObject(raw)).takeIf {
            it.company == data.getString("company_id", null) &&
                it.company == data.getString("widget_active_workspace", it.company)
        }
    }

    private fun destinations(entry: EntryContext, state: JSONObject): List<Choice> {
        val type = state.optString("type", "expense")
        return if (type == "transfer") {
            entry.choices("wallets").filterNot { it.id == state.optString("wallet") }
        } else {
            val recent = recentCategories(state.optJSONObject("defaults"), type)
            entry.choices(type).sortedBy { choice ->
                recent.indexOf(choice.id).takeIf { it >= 0 } ?: recent.size
            }
        }
    }

    private fun recentCategories(defaults: JSONObject?, type: String): List<String> {
        val items = defaults?.optJSONObject(type)?.optJSONArray("categories") ?: return emptyList()
        return List(items.length()) { items.getString(it) }
    }

    private fun defaults(context: Context) =
        context.getSharedPreferences("widget_entry_defaults", Context.MODE_PRIVATE)

    private fun remember(context: Context, entry: EntryContext, type: String, wallet: String, destination: String) {
        val preferences = defaults(context)
        val saved = JSONObject(preferences.getString(entry.scope, "{}").orEmpty())
        val byType = JSONObject().put("wallet", wallet)
        if (type != "transfer") {
            val categories = (listOf(destination) + recentCategories(saved, type))
                .distinct().take(RECENT_CATEGORY_LIMIT)
            byType.put("categories", JSONArray(categories))
        }
        saved.put("type", type).put(type, byType)
        preferences.edit().putString(entry.scope, saved.toString()).apply()
    }

    private fun applyDefaults(entry: EntryContext, state: JSONObject, type: String) {
        val saved = state.optJSONObject("defaults")
        val rememberedWallet = saved?.optJSONObject(type)?.optString("wallet")
        val wallets = entry.choices("wallets")
        val walletIndex = listOf(rememberedWallet, entry.defaultWallet, wallets.firstOrNull()?.id)
            .firstNotNullOfOrNull { id -> wallets.indexOfFirst { it.id == id }.takeIf { it >= 0 } }
        state.remove("wallet")
        state.remove("walletPage")
        state.remove("destination")
        state.remove("destinationPage")
        state.put("type", type)
        if (walletIndex != null) {
            state.put("wallet", wallets[walletIndex].id).put("walletPage", walletIndex / CHOICES_PER_PAGE)
        }
        if (type != "transfer") {
            val available = entry.choices(type)
            val category = recentCategories(saved, type).firstOrNull { id -> available.any { it.id == id } }
            if (category != null) state.put("destination", category)
        }
    }

    private fun choiceOffset(state: JSONObject, field: String, choices: List<Choice>): Int {
        val lastPage = (choices.size - 1).coerceAtLeast(0) / CHOICES_PER_PAGE
        return (state.optInt("${field}Page").coerceIn(0, lastPage)) * CHOICES_PER_PAGE
    }

    private fun drafts(context: Context) =
        context.getSharedPreferences("widget_entry_drafts", Context.MODE_PRIVATE)

    private fun draft(context: Context, id: Int, scope: String): JSONObject? {
        val preferences = drafts(context)
        val key = "$id:$scope"
        preferences.getString(key, null)?.let { return JSONObject(it) }
        val legacy = preferences.getString(id.toString(), null)?.let(::JSONObject) ?: return null
        if (legacy.optString("scope") != scope) return null
        preferences.edit().putString(key, legacy.toString()).remove(id.toString()).apply()
        return legacy
    }

    private fun store(context: Context, id: Int, scope: String, draft: JSONObject?) {
        drafts(context).edit().putString("$id:$scope", draft?.toString()).apply()
    }

    fun delete(context: Context, id: Int) {
        val preferences = drafts(context)
        val editor = preferences.edit().remove(id.toString())
        preferences.all.keys.filter { it.startsWith("$id:") }.forEach { editor.remove(it) }
        editor.apply()
    }

    fun openIntent(context: Context, id: Int, data: SharedPreferences): PendingIntent? {
        val entry = entryContext(data) ?: return null
        return actionIntent(context, id, entry.scope, "open")
    }

    private fun actionIntent(
        context: Context, id: Int, token: String, action: String
    ): PendingIntent {
        val intent = Intent(context, WidgetEntryReceiver::class.java).apply {
            data = Uri.Builder().scheme("paypr-widget").authority("entry")
                .appendPath(id.toString()).appendPath(token).appendPath(action).build()
        }
        return PendingIntent.getBroadcast(context, 0, intent, PendingIntent.FLAG_IMMUTABLE)
    }

    fun render(context: Context, id: Int, data: SharedPreferences): RemoteViews? {
        val entry = entryContext(data) ?: return null
        val state = draft(context, id, entry.scope) ?: return null
        if (state.optString("page") == "receipt") {
            store(context, id, entry.scope, null)
            return null
        }
        val views = RemoteViews(context.packageName, R.layout.widget_entry)
        views.removeAllViews(R.id.widget_entry_rows)
        views.setViewVisibility(R.id.widget_entry_close, View.VISIBLE)
        views.setViewVisibility(R.id.widget_entry_workspace, View.VISIBLE)
        val token = state.getString("id")
        fun intent(action: String) = actionIntent(context, id, token, action)
        fun row(vararg keys: Pair<String, String>, accent: Boolean = false) {
            val row = RemoteViews(context.packageName, R.layout.widget_entry_row)
            keys.forEach { (label, action) ->
                val key = RemoteViews(context.packageName, R.layout.widget_entry_key)
                key.setTextViewText(R.id.widget_entry_key, label)
                key.setContentDescription(
                    R.id.widget_entry_key,
                    when (action) {
                        "backspace" -> "Delete digit"
                        "." -> "Decimal point"
                        "review" -> "Review entry"
                        "more:wallet" -> "More wallets"
                        "more:destination" ->
                            if (state.optString("type") == "transfer") "More destination wallets" else "More categories"
                        else -> label
                    }
                )
                val style = when {
                    action == "save" || action == "review" ->
                        R.drawable.widget_add_pill to R.color.widget_on_add
                    action == "type" || (accent && label.isNotEmpty()) ->
                        R.drawable.widget_entry_type_pill to R.color.widget_on_entry_type
                    else -> null
                }
                when {
                    style != null -> {
                        key.setInt(R.id.widget_entry_key, "setBackgroundResource", style.first)
                        key.setTextColor(
                            R.id.widget_entry_key,
                            androidx.core.content.ContextCompat.getColor(context, style.second)
                        )
                    }
                    action.isEmpty() ->
                        key.setInt(R.id.widget_entry_key, "setBackgroundResource", 0)
                }
                if (action.isNotEmpty()) key.setOnClickPendingIntent(R.id.widget_entry_key, intent(action))
                row.addView(R.id.widget_entry_row, key)
            }
            views.addView(R.id.widget_entry_rows, row)
        }
        val type = state.optString("type", "expense")
        val amount = state.optString("amount").ifEmpty { "0" }
        val currency = data.getString("currency_symbol", "").orEmpty()
        val error = state.optString("error")
        val workspace = entry.name.ifBlank { data.getString("company_name", "Workspace").orEmpty() }
        views.setTextViewText(R.id.widget_entry_workspace, workspace)
        views.setTextViewText(R.id.widget_entry_title, error.ifEmpty { "$currency $amount".trim() })
        views.setOnClickPendingIntent(R.id.widget_entry_close, intent("cancel"))

        val wallets = entry.choices("wallets")
        val destinations = destinations(entry, state)
        when {
            token in saving -> row("Saving…" to "")
            state.optBoolean("retry") -> row("Retry save" to "save")
            state.optString("page") in detailsPages -> {
                fun heading(label: String, field: String, choices: List<Choice>) =
                    if (choices.size > CHOICES_PER_PAGE) "$label ›" to "more:$field" else label to ""

                fun choiceKey(field: String, choices: List<Choice>, index: Int): Pair<String, String> {
                    if (choices.isEmpty() && index == 0) return "Set up in the app" to ""
                    val choice = choices.getOrNull(choiceOffset(state, field, choices) + index)
                        ?: return "" to ""
                    val selected = choice.id == state.optString(field)
                    return (if (selected) "✓ ${choice.name}" else choice.name) to "select:$field:${choice.id}"
                }

                val transfer = type == "transfer"
                row(
                    heading(if (transfer) "From wallet" else "Wallet", "wallet", wallets),
                    heading(if (transfer) "To wallet" else "Category", "destination", destinations),
                    accent = true,
                )
                repeat(CHOICES_PER_PAGE) { index ->
                    row(
                        choiceKey("wallet", wallets, index),
                        choiceKey("destination", destinations, index),
                    )
                }
                row(
                    "Back" to "amount",
                    "${type.replaceFirstChar { it.uppercaseChar() }} ↻" to "type",
                    "Save" to "save",
                )
            }
            else -> {
                row("1" to "1", "2" to "2", "3" to "3")
                row("4" to "4", "5" to "5", "6" to "6")
                row("7" to "7", "8" to "8", "9" to "9")
                row("." to ".", "0" to "0", "⌫" to "backspace", "→" to "review")
            }
        }
        return views
    }

    fun handle(context: Context, intent: Intent, async: () -> BroadcastReceiver.PendingResult) {
        val parts = intent.data?.pathSegments ?: return
        if (parts.size != 3) return
        val id = parts[0].toIntOrNull() ?: return
        val manager = AppWidgetManager.getInstance(context)
        if (manager.getAppWidgetInfo(id)?.provider?.className != PayprWidgetProvider::class.java.name) return
        val data = HomeWidgetPlugin.getData(context)
        val action = parts[2]
        fun update() {
            PayprWidgetProvider().onUpdate(context, manager, intArrayOf(id), data)
        }
        val entry = entryContext(data)
        if (action == "open") {
            if (entry == null) {
                if (data.getBoolean(ENABLED, false)) {
                    Toast.makeText(
                        context,
                        context.getString(R.string.widget_keypad_unavailable),
                        Toast.LENGTH_SHORT,
                    ).show()
                }
                update()
                return
            }
            if (parts[1] != entry.scope) {
                update()
                return
            }
            if (draft(context, id, entry.scope) != null) {
                update()
                return
            }
            val state = JSONObject().put("scope", entry.scope)
                .put("id", "tx_widget_${UUID.randomUUID().toString().replace("-", "")}")
            val saved = JSONObject(defaults(context).getString(entry.scope, "{}").orEmpty())
            state.put("defaults", saved)
            applyDefaults(entry, state, saved.optString("type", "expense"))
            store(context, id, entry.scope, state)
            update()
            return
        }

        if (entry == null) return
        val state = draft(context, id, entry.scope) ?: return
        val token = state.optString("id")
        if (parts[1] != token || token in saving || entry.scope != state.optString("scope")) return
        if (action == "cancel") {
            store(context, id, entry.scope, null)
            update()
            return
        }
        if (state.optString("page") == "receipt" || (state.optBoolean("retry") && action != "save")) return
        state.remove("error")
        val type = state.optString("type", "expense")
        val amount = state.optString("amount")
        when (action) {
            "amount" -> state.remove("page")
            "review" -> state.put("page", "details")
            "type" -> {
                applyDefaults(entry, state, when (type) {
                    "expense" -> "income"
                    "income" -> "transfer"
                    else -> "expense"
                })
            }
            "more:wallet", "more:destination" -> {
                if (state.optString("page") !in detailsPages) return
                val field = action.substringAfter(':')
                val choices = if (field == "wallet") entry.choices("wallets") else destinations(entry, state)
                val pageCount = (choices.size + CHOICES_PER_PAGE - 1) / CHOICES_PER_PAGE
                if (pageCount <= 1) return
                val nextPage = (choiceOffset(state, field, choices) / CHOICES_PER_PAGE + 1) % pageCount
                state.put("${field}Page", nextPage)
            }
            "backspace" -> state.put("amount", amount.dropLast(1))
            "." -> if ('.' !in amount) state.put("amount", amount.ifEmpty { "0" } + ".")
            "save" -> {
                val cents = amount.toBigDecimalOrNull()?.multiply(BigDecimal(100))?.toLong() ?: 0L
                val wallet = state.optString("wallet")
                val destination = state.optString("destination")
                val error = when {
                    cents <= 0 -> "Enter an amount"
                    entry.choices("wallets").none { it.id == wallet } -> "Choose a wallet"
                    destinations(entry, state).none { it.id == destination } ->
                        if (type == "transfer") "Choose a destination wallet" else "Choose a category"
                    else -> null
                }
                if (error == null) {
                    saving.add(token)
                    state.put("retry", true)
                    store(context, id, entry.scope, state)
                    update()
                    val pending = async()
                    WidgetEntryEngine.save(context, mapOf(
                        "user" to entry.user,
                        "company" to entry.company,
                        "type" to type,
                        "id" to state.getString("id"),
                        "cents" to cents.toString(),
                        "wallet" to wallet,
                        "destination" to destination,
                    )) { message, uncertain ->
                        saving.remove(token)
                        if (message == null) remember(context, entry, type, wallet, destination)
                        if (draft(context, id, entry.scope)?.optString("id") == state.optString("id")) {
                            if (message == null) {
                                store(context, id, entry.scope, null)
                            } else {
                                store(context, id, entry.scope, state.put("retry", uncertain).put("error", message))
                            }
                        }
                        try {
                            update()
                        } finally {
                            pending.finish()
                        }
                    }
                    return
                }
                state.put("error", error)
            }
            else -> {
                if (action.startsWith("select:")) {
                    if (state.optString("page") !in detailsPages) return
                    val key = action.substringAfter(':').substringBefore(':')
                    if (key != "wallet" && key != "destination") return
                    val prefix = "select:$key:"
                    if (!action.startsWith(prefix)) return
                    val choiceId = action.removePrefix(prefix)
                    val choices = if (key == "wallet") entry.choices("wallets") else destinations(entry, state)
                    val choice = choices
                        .firstOrNull { it.id == choiceId } ?: return
                    state.put(key, choice.id)
                    if (key == "wallet" && type == "transfer") {
                        if (state.optString("destination") == choice.id) state.remove("destination")
                        state.remove("destinationPage")
                    }
                } else if (action.length == 1 && action[0] in '0'..'9') {
                    val hasSpace = if ('.' in amount) amount.substringAfter('.').length < 2 else amount.length < 9
                    if (hasSpace) state.put("amount", (if (amount == "0") "" else amount) + action)
                } else return
            }
        }
        store(context, id, entry.scope, state)
        update()
    }
}

class WidgetEntryReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        WidgetEntry.handle(context.applicationContext, intent) { goAsync() }
    }
}

private object WidgetEntryEngine {
    fun save(context: Context, request: Map<String, String>, complete: (String?, Boolean) -> Unit) {
        val handler = Handler(Looper.getMainLooper())
        var engine: FlutterEngine? = null
        var finished = false
        lateinit var timeout: Runnable
        fun finish(message: String?, uncertain: Boolean) {
            if (finished) return
            finished = true
            handler.removeCallbacks(timeout)
            // Leave the current platform-channel callback before destroying its engine.
            handler.post {
                try {
                    engine?.destroy()
                } finally {
                    complete(message, uncertain)
                }
            }
        }
        timeout = Runnable { finish("Save timed out", true) }
        handler.postDelayed(timeout, 8_000)
        try {
            val loader = FlutterInjector.instance().flutterLoader()
            loader.startInitialization(context)
            loader.ensureInitializationCompleteAsync(context, null, handler) {
                if (finished) return@ensureInitializationCompleteAsync
                try {
                    val flutter = FlutterEngine(context)
                    engine = flutter
                    val channel = MethodChannel(flutter.dartExecutor.binaryMessenger, CHANNEL)
                    channel.setMethodCallHandler { call, result ->
                        if (call.method != "ready") {
                            result.notImplemented()
                            return@setMethodCallHandler
                        }
                        result.success(null)
                        channel.invokeMethod("save", request, object : MethodChannel.Result {
                            override fun success(result: Any?) = finish(result as? String, false)
                            override fun error(code: String, message: String?, details: Any?) =
                                finish("Could not confirm save", true)
                            override fun notImplemented() = finish("Save is unavailable", true)
                        })
                    }
                    flutter.dartExecutor.executeDartEntrypoint(
                        DartExecutor.DartEntrypoint(loader.findAppBundlePath(), "widgetEntryMain")
                    )
                } catch (error: Exception) {
                    android.util.Log.e("WidgetEntry", "Widget engine failed", error)
                    finish("Could not start save", true)
                }
            }
        } catch (error: Exception) {
            android.util.Log.e("WidgetEntry", "Flutter initialization failed", error)
            finish("Could not start save", true)
        }
    }
}
