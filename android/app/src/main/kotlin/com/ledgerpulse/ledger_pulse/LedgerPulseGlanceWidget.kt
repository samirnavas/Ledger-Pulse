package com.ledgerpulse.ledger_pulse

import android.content.ComponentName
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
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
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

        val deepLinkIntent = Intent(
            Intent.ACTION_VIEW,
            Uri.parse("ledgerpulse://dashboard?company_id=$companyId"),
            context,
            MainActivity::class.java
        ).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }

        provideContent {
            GlanceTheme {
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

    @Composable
    private fun LedgerPulseWidgetContent(
        companyName: String,
        cashIn: String,
        cashOut: String,
        currencySymbol: String,
        intent: Intent
    ) {
        // M3 Expressive Palette via resource IDs with automatic Light/Dark mode support
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

                // Inflow Row: ↑ ₹ 6,650
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

                // Outflow Row: ↓ ₹ 16,000
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
