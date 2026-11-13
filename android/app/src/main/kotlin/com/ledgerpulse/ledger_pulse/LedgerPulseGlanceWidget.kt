package com.ledgerpulse.ledger_pulse

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.GlanceTheme
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.LinearProgressIndicator
import androidx.glance.appwidget.ProgressIndicatorDefaults
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.action.actionStartActivity
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.provideContent
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxHeight
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.width
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import es.antonborri.home_widget.HomeWidgetPlugin

class LedgerPulseGlanceWidget : GlanceAppWidget() {

    companion object {
        private val SMALL_SQUARE = DpSize(120.dp, 120.dp)
        private val MEDIUM_RECT = DpSize(220.dp, 110.dp)
    }

    override val sizeMode = SizeMode.Responsive(
        setOf(SMALL_SQUARE, MEDIUM_RECT)
    )

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val prefs = HomeWidgetPlugin.getData(context)
        val companyName = prefs.getString("company_name", "Ledger Enterprise") ?: "Ledger Enterprise"
        val companyId = prefs.getString("company_id", "default") ?: "default"
        val currencySymbol = prefs.getString("currency_symbol", "₹") ?: "₹"
        val mode = prefs.getString("mode", "ledger") ?: "ledger"
        val isExpense = mode.equals("expense", ignoreCase = true) ||
                        mode.equals("expenseTracker", ignoreCase = true) ||
                        mode.equals("expense_tracker", ignoreCase = true)

        var cashIn = prefs.getString("cash_in_value", null)
        if (cashIn.isNullOrEmpty()) {
            val raw = prefs.getString("cash_in_amount", "2000") ?: "2000"
            cashIn = raw.replace("₹", "").trim()
        }

        var cashOut = prefs.getString("cash_out_value", null)
        if (cashOut.isNullOrEmpty()) {
            val raw = prefs.getString("cash_out_amount", "1000") ?: "1000"
            cashOut = raw.replace("₹", "").trim()
        }

        var todaySpend = prefs.getString("today_spend_amount", null)
        if (todaySpend.isNullOrEmpty()) {
            val rawValue = prefs.getString("today_spend_value", null)
                ?: prefs.getString("cash_out_value", "2,000")
                ?: "2,000"
            todaySpend = "$currencySymbol$rawValue"
        }

        val spendLabel = prefs.getString("spend_label", null)
            ?: prefs.getString("today_label", "Today")
            ?: "Today"
        val spendProgress = prefs.getString("spend_progress_text", "Spend - 2000/3700") ?: "Spend - 2000/3700"
        val spendPercent = prefs.getString("spend_percent_text", "58%") ?: "58%"
        val progressInt = getSafeInt(prefs, "spend_progress_percent", 58)

        val cat1 = prefs.getString("category_1_name", "Food & Dining") ?: "Food & Dining"
        val cat2 = prefs.getString("category_2_name", "Groceries") ?: "Groceries"
        val cat3 = prefs.getString("category_3_name", "Travel") ?: "Travel"

        val deepLinkIntent = Intent(
            Intent.ACTION_VIEW,
            Uri.parse("ledgerpulse://dashboard?company_id=$companyId"),
            context,
            MainActivity::class.java
        ).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }

        val quickAddIntent = Intent(
            Intent.ACTION_VIEW,
            Uri.parse("ledgerpulse://dashboard?company_id=$companyId&action=quick_add"),
            context,
            MainActivity::class.java
        ).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }

        provideContent {
            GlanceTheme {
                if (isExpense) {
                    ExpenseWidgetContent(
                        companyName = companyName,
                        spendLabel = spendLabel,
                        todaySpend = todaySpend,
                        spendProgress = spendProgress,
                        spendPercent = spendPercent,
                        progressPercent = progressInt,
                        cat1 = cat1,
                        cat2 = cat2,
                        cat3 = cat3,
                        intent = deepLinkIntent,
                        quickAddIntent = quickAddIntent
                    )
                } else {
                    LedgerPulseWidgetContent(
                        companyName = companyName,
                        cashIn = cashIn,
                        cashOut = cashOut,
                        currencySymbol = currencySymbol,
                        intent = deepLinkIntent
                    )
                }
            }
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

    @Composable
    private fun ExpenseWidgetContent(
        companyName: String,
        spendLabel: String,
        todaySpend: String,
        spendProgress: String,
        spendPercent: String,
        progressPercent: Int,
        cat1: String,
        cat2: String,
        cat3: String,
        intent: Intent,
        quickAddIntent: Intent
    ) {
        val widgetBgColor = androidx.glance.unit.ColorProvider(R.color.widget_expense_bg)
        val textColor = androidx.glance.unit.ColorProvider(R.color.widget_expense_text)
        val trackColor = androidx.glance.unit.ColorProvider(R.color.widget_expense_track)
        val fillColor = androidx.glance.unit.ColorProvider(R.color.widget_expense_fill)

        Box(
            modifier = GlanceModifier
                .fillMaxSize()
                .cornerRadius(28.dp)
                .background(widgetBgColor)
                .clickable(actionStartActivity(intent))
                .padding(14.dp),
            contentAlignment = Alignment.TopStart
        ) {
            Column(
                modifier = GlanceModifier.fillMaxSize()
            ) {
                // Header: Profile Name & Plus Quick Add Action
                Row(
                    modifier = GlanceModifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = companyName,
                        style = TextStyle(
                            color = textColor,
                            fontSize = 15.sp,
                            fontWeight = FontWeight.Bold
                        ),
                        maxLines = 1,
                        modifier = GlanceModifier.defaultWeight()
                    )
                    Image(
                        provider = ImageProvider(R.drawable.ic_widget_add),
                        contentDescription = "Add Expense",
                        modifier = GlanceModifier
                            .width(22.dp)
                            .height(22.dp)
                            .clickable(actionStartActivity(quickAddIntent))
                    )
                }

                Spacer(modifier = GlanceModifier.defaultWeight())

                // Subtitle: Today or This Month
                Text(
                    text = spendLabel,
                    style = TextStyle(
                        color = textColor,
                        fontSize = 13.sp,
                        fontWeight = FontWeight.Normal
                    )
                )

                // Large Amount: ₹2,000
                Text(
                    text = todaySpend,
                    style = TextStyle(
                        color = textColor,
                        fontSize = 32.sp,
                        fontWeight = FontWeight.Bold
                    ),
                    maxLines = 1
                )

                Spacer(modifier = GlanceModifier.defaultWeight())

                // Progress Bar
                LinearProgressIndicator(
                    progress = (progressPercent.coerceIn(0, 100) / 100f),
                    modifier = GlanceModifier.fillMaxWidth().height(8.dp).cornerRadius(4.dp),
                    color = fillColor,
                    backgroundColor = trackColor
                )

                Spacer(modifier = GlanceModifier.height(4.dp))

                // Spend - 2000/3700 and 58%
                Row(
                    modifier = GlanceModifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = spendProgress,
                        style = TextStyle(
                            color = textColor,
                            fontSize = 11.sp
                        ),
                        maxLines = 1,
                        modifier = GlanceModifier.defaultWeight()
                    )
                    Text(
                        text = spendPercent,
                        style = TextStyle(
                            color = textColor,
                            fontSize = 11.sp,
                            fontWeight = FontWeight.Bold
                        )
                    )
                }
            }
        }
    }

    @Composable
    private fun LedgerPulseWidgetContent(
        companyName: String,
        cashIn: String,
        cashOut: String,
        currencySymbol: String,
        intent: Intent
    ) {
        val widgetBgColor = androidx.glance.unit.ColorProvider(R.color.widget_bg)
        val onSurfaceColor = androidx.glance.unit.ColorProvider(R.color.widget_on_surface)
        val onSurfaceVariant = androidx.glance.unit.ColorProvider(R.color.widget_on_surface_variant)
        val dividerColor = androidx.glance.unit.ColorProvider(R.color.widget_divider)

        Box(
            modifier = GlanceModifier
                .fillMaxSize()
                .cornerRadius(28.dp)
                .background(widgetBgColor)
                .clickable(actionStartActivity(intent))
                .padding(14.dp),
            contentAlignment = Alignment.TopStart
        ) {
            Column(
                modifier = GlanceModifier.fillMaxSize()
            ) {
                // Header: Company Name
                Text(
                    text = companyName,
                    style = TextStyle(
                        color = onSurfaceColor,
                        fontSize = 14.sp,
                        fontWeight = FontWeight.Bold
                    ),
                    maxLines = 1
                )

                Spacer(modifier = GlanceModifier.defaultWeight())

                // You'll Get Row (Receivable): ↓ ₹ 6,650
                Row(
                    modifier = GlanceModifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = "↓",
                        style = TextStyle(
                            color = onSurfaceVariant,
                            fontSize = 18.sp,
                            fontWeight = FontWeight.Bold
                        )
                    )
                    Spacer(modifier = GlanceModifier.width(4.dp))
                    Text(
                        text = currencySymbol,
                        style = TextStyle(
                            color = onSurfaceColor,
                            fontSize = 20.sp
                        )
                    )
                    Spacer(modifier = GlanceModifier.width(4.dp))
                    Text(
                        text = cashIn,
                        style = TextStyle(
                            color = onSurfaceColor,
                            fontSize = 24.sp,
                            fontWeight = FontWeight.Medium
                        ),
                        maxLines = 1
                    )
                }

                Spacer(modifier = GlanceModifier.defaultWeight())

                // Structural Tonal Divider
                Box(
                    modifier = GlanceModifier
                        .fillMaxWidth()
                        .height(1.dp)
                        .background(dividerColor)
                ) {}

                Spacer(modifier = GlanceModifier.defaultWeight())

                // You'll Give Row (Payable): ↑ ₹ 16,000
                Row(
                    modifier = GlanceModifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = "↑",
                        style = TextStyle(
                            color = onSurfaceVariant,
                            fontSize = 18.sp,
                            fontWeight = FontWeight.Bold
                        )
                    )
                    Spacer(modifier = GlanceModifier.width(4.dp))
                    Text(
                        text = currencySymbol,
                        style = TextStyle(
                            color = onSurfaceColor,
                            fontSize = 20.sp
                        )
                    )
                    Spacer(modifier = GlanceModifier.width(4.dp))
                    Text(
                        text = cashOut,
                        style = TextStyle(
                            color = onSurfaceColor,
                            fontSize = 24.sp,
                            fontWeight = FontWeight.Medium
                        ),
                        maxLines = 1
                    )
                }

                Spacer(modifier = GlanceModifier.defaultWeight())
            }
        }
    }
}
