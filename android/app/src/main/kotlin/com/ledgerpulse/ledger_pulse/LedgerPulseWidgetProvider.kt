package com.ledgerpulse.ledger_pulse

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.net.Uri
import android.os.Bundle
import android.widget.RemoteViews
import androidx.core.content.ContextCompat
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider

class LedgerPulseWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: android.content.SharedPreferences
    ) {
        for (appWidgetId in appWidgetIds) {
            val options = appWidgetManager.getAppWidgetOptions(appWidgetId)
            updateAppWidget(context, appWidgetManager, appWidgetId, widgetData, options)
        }
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle?
    ) {
        val widgetData = HomeWidgetPlugin.getData(context)
        updateAppWidget(context, appWidgetManager, appWidgetId, widgetData, newOptions)
    }

    private fun updateAppWidget(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        widgetData: android.content.SharedPreferences,
        options: Bundle?
    ) {
        try {
            val mode = widgetData.getString("mode", "ledger") ?: "ledger"
            val isExpense = mode.equals("expense", ignoreCase = true) ||
                            mode.equals("expenseTracker", ignoreCase = true) ||
                            mode.equals("expense_tracker", ignoreCase = true)

            val minWidth = options?.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH) ?: 140
            val isMedium = minWidth >= 220

            val views = if (isExpense) {
                buildExpenseWidget(context, widgetData, isMedium)
            } else {
                buildLedgerWidget(context, widgetData, isMedium)
            }

            appWidgetManager.updateAppWidget(appWidgetId, views)
        } catch (e: Exception) {
            android.util.Log.e("LedgerPulseWidget", "Error updating widget: ${e.message}", e)
        }
    }

    private fun getSafeFloat(prefs: android.content.SharedPreferences, key: String, defaultVal: Float): Float {
        return try {
            val isDouble = prefs.getBoolean("home_widget.double.$key", false)
            val value = prefs.all[key] ?: return defaultVal
            when {
                isDouble && value is Long -> java.lang.Double.longBitsToDouble(value).toFloat()
                value is Float -> value
                value is Double -> value.toFloat()
                value is Number -> value.toFloat()
                value is String -> value.toFloatOrNull() ?: defaultVal
                else -> defaultVal
            }
        } catch (_: Exception) {
            defaultVal
        }
    }

    private fun getSafeInt(prefs: android.content.SharedPreferences, key: String, defaultVal: Int): Int {
        return try {
            val all = prefs.all
            val value = all[key] ?: return defaultVal
            when (value) {
                is Int -> value
                is Long -> value.toInt()
                is Number -> value.toInt()
                is String -> value.toIntOrNull() ?: defaultVal
                else -> defaultVal
            }
        } catch (_: Exception) {
            defaultVal
        }
    }

    private fun buildExpenseWidget(
        context: Context,
        widgetData: android.content.SharedPreferences,
        isMedium: Boolean
    ): RemoteViews {
        val companyName = widgetData.getString("company_name", "Profile Name") ?: "Profile Name"
        val companyId = widgetData.getString("company_id", "default") ?: "default"
        val currencySymbol = widgetData.getString("currency_symbol", "₹") ?: "₹"

        // Today spend formatted (e.g. "₹2,000" or fallback to "₹2,000")
        var todaySpend = widgetData.getString("today_spend_amount", null)
        if (todaySpend.isNullOrEmpty()) {
            val rawValue = widgetData.getString("today_spend_value", null)
                ?: widgetData.getString("cash_out_value", "2,000")
                ?: "2,000"
            todaySpend = "$currencySymbol$rawValue"
        }

        val spendProgress = widgetData.getString("spend_progress_text", "Spend - 2000/3700") ?: "Spend - 2000/3700"
        val spendPercent = widgetData.getString("spend_percent_text", "58%") ?: "58%"
        val progressInt = getSafeInt(widgetData, "spend_progress_percent", 58)

        val layoutId = if (isMedium) {
            R.layout.widget_expense_tracker_medium
        } else {
            R.layout.widget_expense_tracker_small
        }

        val spendLabel = widgetData.getString("spend_label", null)
            ?: widgetData.getString("today_label", "Today")
            ?: "Today"

        return RemoteViews(context.packageName, layoutId).apply {
            setTextViewText(R.id.widget_company_name, companyName)
            setTextViewText(R.id.widget_today_label, spendLabel)
            setTextViewText(R.id.widget_today_amount, todaySpend)
            setTextViewText(R.id.widget_expense_spend_progress, spendProgress)
            setTextViewText(R.id.widget_expense_spend_percent, spendPercent)
            setProgressBar(R.id.widget_expense_progress_bar, 100, progressInt.coerceIn(0, 100), false)

            if (isMedium) {
                val cat1 = widgetData.getString("category_1_name", "Food & Dining") ?: "Food & Dining"
                val cat2 = widgetData.getString("category_2_name", "Groceries") ?: "Groceries"
                val cat3 = widgetData.getString("category_3_name", "Travel") ?: "Travel"

                val p1 = getSafeFloat(widgetData, "category_1_percent", 45f)
                val p2 = getSafeFloat(widgetData, "category_2_percent", 30f)
                val p3 = getSafeFloat(widgetData, "category_3_percent", 25f)

                setTextViewText(R.id.widget_expense_category_1, if (cat1.startsWith("•")) cat1 else "• $cat1")
                setTextViewText(R.id.widget_expense_category_2, if (cat2.startsWith("•")) cat2 else "• $cat2")
                setTextViewText(R.id.widget_expense_category_3, if (cat3.startsWith("•")) cat3 else "• $cat3")

                val donutBitmap = createDonutChartBitmap(context, 72, listOf(p1, p2, p3))
                setImageViewBitmap(R.id.widget_expense_donut_chart, donutBitmap)
            }

            // Plus button PendingIntent: opens quick add transaction in app (on both Small and Medium widgets)
            val quickAddUri = Uri.parse("ledgerpulse://dashboard?company_id=$companyId&action=quick_add")
            val quickAddIntent = HomeWidgetLaunchIntent.getActivity(
                context,
                MainActivity::class.java,
                quickAddUri
            )
            setOnClickPendingIntent(R.id.widget_expense_add_button, quickAddIntent)

            // Root click PendingIntent: opens dashboard for active company
            val deepLinkUri = Uri.parse("ledgerpulse://dashboard?company_id=$companyId")
            val pendingIntent = HomeWidgetLaunchIntent.getActivity(
                context,
                MainActivity::class.java,
                deepLinkUri
            )
            setOnClickPendingIntent(R.id.widget_root, pendingIntent)
        }
    }

    private fun buildLedgerWidget(
        context: Context,
        widgetData: android.content.SharedPreferences,
        isMedium: Boolean
    ): RemoteViews {
        val companyName = widgetData.getString("company_name", "Ledger Enterprise") ?: "Ledger Enterprise"
        val companyId = widgetData.getString("company_id", "default") ?: "default"
        val currencySymbol = widgetData.getString("currency_symbol", "₹") ?: "₹"

        var cashInValue = widgetData.getString("cash_in_value", null)
        if (cashInValue.isNullOrEmpty()) {
            val fullAmount = widgetData.getString("cash_in_amount", "2000") ?: "2000"
            cashInValue = fullAmount.replace("₹", "").trim()
        }

        var cashOutValue = widgetData.getString("cash_out_value", null)
        if (cashOutValue.isNullOrEmpty()) {
            val fullAmount = widgetData.getString("cash_out_amount", "1000") ?: "1000"
            cashOutValue = fullAmount.replace("₹", "").trim()
        }

        val layoutId = if (isMedium) {
            R.layout.widget_ledger_pulse_medium
        } else {
            R.layout.widget_ledger_pulse_small
        }

        return RemoteViews(context.packageName, layoutId).apply {
            setTextViewText(R.id.widget_company_name, companyName)
            setTextViewText(R.id.widget_cash_in_text, cashInValue)
            setTextViewText(R.id.widget_cash_out_text, cashOutValue)
            setTextViewText(R.id.widget_inflow_symbol, currencySymbol)
            setTextViewText(R.id.widget_outflow_symbol, currencySymbol)

            val deepLinkUri = Uri.parse("ledgerpulse://dashboard?company_id=$companyId")
            val pendingIntent = HomeWidgetLaunchIntent.getActivity(
                context,
                MainActivity::class.java,
                deepLinkUri
            )
            setOnClickPendingIntent(R.id.widget_root, pendingIntent)
        }
    }

    private fun createDonutChartBitmap(
        context: Context,
        sizeDp: Int,
        categoryPercents: List<Float>
    ): Bitmap {
        val density = context.resources.displayMetrics.density
        val sizePx = (sizeDp * density).toInt().coerceAtLeast(1)
        val bitmap = Bitmap.createBitmap(sizePx, sizePx, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)

        val strokeWidth = 11f * density
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            this.strokeWidth = strokeWidth
            strokeCap = Paint.Cap.BUTT
        }

        val padding = strokeWidth / 2f + 1.5f * density
        val rect = RectF(padding, padding, sizePx - padding, sizePx - padding)

        val c1 = ContextCompat.getColor(context, R.color.widget_expense_donut_1)
        val c2 = ContextCompat.getColor(context, R.color.widget_expense_donut_2)
        val c3 = ContextCompat.getColor(context, R.color.widget_expense_donut_3)
        val colors = listOf(c1, c2, c3)

        var total = categoryPercents.sum()
        val normalized = if (total <= 0f) {
            listOf(45f, 30f, 25f)
        } else {
            categoryPercents
        }
        total = normalized.sum()

        var startAngle = -90f
        val gapAngle = if (normalized.size > 1) 3f else 0f
        val totalGap = gapAngle * normalized.size
        val availableDegrees = (360f - totalGap).coerceAtLeast(0f)

        for (i in normalized.indices) {
            val sweep = (normalized[i] / total) * availableDegrees
            paint.color = colors[i % colors.size]
            canvas.drawArc(rect, startAngle + gapAngle / 2f, sweep, false, paint)
            startAngle += sweep + gapAngle
        }

        // Draw center pie icon
        val iconSize = (18f * density).toInt()
        val iconDrawable = ContextCompat.getDrawable(context, R.drawable.ic_widget_pie_chart)
        if (iconDrawable != null) {
            val cx = sizePx / 2
            val cy = sizePx / 2
            iconDrawable.setBounds(
                cx - iconSize / 2,
                cy - iconSize / 2,
                cx + iconSize / 2,
                cy + iconSize / 2
            )
            iconDrawable.draw(canvas)
        }

        return bitmap
    }
}
