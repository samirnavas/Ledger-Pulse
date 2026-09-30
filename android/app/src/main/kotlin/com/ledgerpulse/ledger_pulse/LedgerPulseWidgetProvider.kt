package com.ledgerpulse.ledger_pulse

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.widget.RemoteViews
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
            val companyName = widgetData.getString("company_name", "Ledger Enterprise") ?: "Ledger Enterprise"
            val companyId = widgetData.getString("company_id", "default") ?: "default"
            val currencySymbol = widgetData.getString("currency_symbol", "₹") ?: "₹"
            
            // Formatted amount (e.g., "2,000" or "2000")
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

            // Determine size based on options (width >= 220dp -> Medium layout)
            val minWidth = options?.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH) ?: 140
            val isMedium = minWidth >= 220

            val layoutId = if (isMedium) {
                R.layout.widget_ledger_pulse_medium
            } else {
                R.layout.widget_ledger_pulse_small
            }

            val views = RemoteViews(context.packageName, layoutId).apply {
                setTextViewText(R.id.widget_company_name, companyName)
                setTextViewText(R.id.widget_cash_in_text, cashInValue)
                setTextViewText(R.id.widget_cash_out_text, cashOutValue)
                setTextViewText(R.id.widget_inflow_symbol, currencySymbol)
                setTextViewText(R.id.widget_outflow_symbol, currencySymbol)

                // Deep link PendingIntent: ledgerpulse://dashboard?company_id={id}
                val deepLinkUri = Uri.parse("ledgerpulse://dashboard?company_id=$companyId")
                val pendingIntent = HomeWidgetLaunchIntent.getActivity(
                    context,
                    MainActivity::class.java,
                    deepLinkUri
                )
                setOnClickPendingIntent(R.id.widget_root, pendingIntent)
            }

            appWidgetManager.updateAppWidget(appWidgetId, views)
        } catch (e: Exception) {
            android.util.Log.e("LedgerPulseWidget", "Error updating widget: ${e.message}", e)
        }
    }
}
