import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import '../../data/models/company_model.dart';
import '../utils/currency_formatter.dart';

/// Production service managing Home Screen Widgets synchronization for Android & iOS.
class WidgetSyncService {
  static const String appGroupId = 'group.com.ledgerpulse.app';
  static const String androidWidgetProvider = 'LedgerPulseWidgetProvider';
  static const String androidWidgetQualified = 'com.ledgerpulse.ledger_pulse.LedgerPulseWidgetProvider';
  static const String androidGlanceQualified = 'com.ledgerpulse.ledger_pulse.LedgerPulseGlanceReceiver';
  static const String iOSWidgetName = 'LedgerPulseWidget';

  /// Initializes App Group and handles deep linking if the app was launched from a widget.
  static Future<void> initialize({
    Function(Uri uri)? onWidgetClick,
  }) async {
    try {
      await HomeWidget.setAppGroupId(appGroupId);

      // Check if launched directly from a home widget click
      final Uri? initialUri = await HomeWidget.initiallyLaunchedFromHomeWidget();
      if (initialUri != null && onWidgetClick != null) {
        onWidgetClick(initialUri);
      }

      // Listen for runtime clicks when app is in background/foreground
      HomeWidget.widgetClicked.listen((Uri? uri) {
        if (uri != null && onWidgetClick != null) {
          onWidgetClick(uri);
        }
      });
    } catch (e) {
      debugPrint('WidgetSyncService.initialize error: $e');
    }
  }

  /// Synchronizes the latest company metrics to native SharedPreferences (Android)
  /// and UserDefaults via App Groups (iOS), then triggers a native widget reload.
  /// In expense mode, publishes today's spend, budget progress, top categories,
  /// as well as this month's spend and income; in ledger mode,
  /// publishes receivables and payables.
  static Future<bool> syncWidgetData({
    required Company company,
    int? totalReceivableCents,
    int? totalPayableCents,
    int? monthSpendCents,
    int? monthIncomeCents,
    int? todaySpendCents,
    int? budgetCents,
    int? spendProgressPercent,
    String? spendProgressText,
    String? spendPercentText,
    List<({String name, double percent})>? topCategories,
  }) async {
    try {
      final currencySym = company.currencyCode == 'INR' ? '₹' : company.currencyCode;
      final isExpense = company.mode == CompanyMode.expenseTracker;

      // In expense mode: cash_in = income, cash_out = spend
      // In ledger mode: cash_in = receivables, cash_out = payables
      final int effectiveInCents = isExpense
          ? (monthIncomeCents ?? totalReceivableCents ?? 0)
          : (totalReceivableCents ?? 0);
      final int effectiveOutCents = isExpense
          ? (monthSpendCents ?? totalPayableCents ?? 0)
          : (totalPayableCents ?? 0);

      final cashInLabel = isExpense ? "This Month's Income" : "You'll Get";
      final cashOutLabel = isExpense ? "This Month's Spend" : "You'll Give";

      // Formatted with symbol (e.g., "₹ 2,000" or "₹ 2000")
      final cashInFormatted = CurrencyFormatter.format(
        effectiveInCents,
        includeSymbol: true,
        showDecimalsAlways: false,
      );
      final cashOutFormatted = CurrencyFormatter.format(
        effectiveOutCents,
        includeSymbol: true,
        showDecimalsAlways: false,
      );

      // Formatted numbers without symbol (e.g., "2,000")
      final cashInAmountOnly = CurrencyFormatter.format(
        effectiveInCents,
        includeSymbol: false,
        showDecimalsAlways: false,
      ).trim();
      final cashOutAmountOnly = CurrencyFormatter.format(
        effectiveOutCents,
        includeSymbol: false,
        showDecimalsAlways: false,
      ).trim();

      final double cashInRaw = effectiveInCents / 100.0;
      final double cashOutRaw = effectiveOutCents / 100.0;
      final String timestamp = DateTime.now().toIso8601String();
      final String deepLinkUri = 'ledgerpulse://dashboard?company_id=${company.id}';

      // 1. Save data fields
      await HomeWidget.saveWidgetData<String>('company_name', company.name);
      await HomeWidget.saveWidgetData<String>('company_id', company.id);
      await HomeWidget.saveWidgetData<String>('mode', company.mode.canonicalValue);
      await HomeWidget.saveWidgetData<String>('currency_symbol', currencySym);
      await HomeWidget.saveWidgetData<String>('cash_in_label', cashInLabel);
      await HomeWidget.saveWidgetData<String>('cash_out_label', cashOutLabel);
      await HomeWidget.saveWidgetData<String>('cash_in_amount', cashInFormatted);
      await HomeWidget.saveWidgetData<String>('cash_out_amount', cashOutFormatted);
      await HomeWidget.saveWidgetData<String>('cash_in_value', cashInAmountOnly);
      await HomeWidget.saveWidgetData<String>('cash_out_value', cashOutAmountOnly);
      await HomeWidget.saveWidgetData<double>('cash_in_raw', cashInRaw);
      await HomeWidget.saveWidgetData<double>('cash_out_raw', cashOutRaw);

      if (isExpense) {
        final bool showToday = (todaySpendCents != null && todaySpendCents > 0);
        final String spendLabel = showToday ? 'Today' : 'This Month';
        final int displaySpendCents = showToday ? todaySpendCents : effectiveOutCents;

        final spendFormatted = CurrencyFormatter.format(
          displaySpendCents,
          includeSymbol: true,
          showDecimalsAlways: false,
        );
        final spendAmountOnly = CurrencyFormatter.format(
          displaySpendCents,
          includeSymbol: false,
          showDecimalsAlways: false,
        ).trim();

        await HomeWidget.saveWidgetData<String>('spend_label', spendLabel);
        await HomeWidget.saveWidgetData<String>('today_label', spendLabel);
        await HomeWidget.saveWidgetData<String>('today_spend_amount', spendFormatted);
        await HomeWidget.saveWidgetData<String>('today_spend_value', spendAmountOnly);
        await HomeWidget.saveWidgetData<double>('today_spend_raw', displaySpendCents / 100.0);

        final budgetAmountOnly = budgetCents != null && budgetCents > 0
            ? CurrencyFormatter.format(
                budgetCents,
                includeSymbol: false,
                showDecimalsAlways: false,
              ).trim()
            : null;

        final calculatedPercent = budgetCents != null && budgetCents > 0
            ? ((displaySpendCents / budgetCents) * 100).round()
            : 0;
        final progressPercent = spendProgressPercent ?? calculatedPercent;

        final progressText = spendProgressText ??
            (budgetAmountOnly != null
                ? 'Spend - $spendAmountOnly/$budgetAmountOnly'
                : 'Spend - $spendAmountOnly');
        final percentText = spendPercentText ??
            (budgetCents != null && budgetCents > 0 ? '$progressPercent%' : '');

        await HomeWidget.saveWidgetData<String>('spend_progress_text', progressText);
        await HomeWidget.saveWidgetData<String>('spend_percent_text', percentText);
        await HomeWidget.saveWidgetData<int>('spend_progress_percent', progressPercent.clamp(0, 100));

        if (topCategories != null && topCategories.isNotEmpty) {
          for (int i = 0; i < 3; i++) {
            final catIndex = i + 1;
            if (i < topCategories.length) {
              await HomeWidget.saveWidgetData<String>('category_${catIndex}_name', topCategories[i].name);
              await HomeWidget.saveWidgetData<double>('category_${catIndex}_percent', topCategories[i].percent);
              await HomeWidget.saveWidgetData<int>('category_${catIndex}_percent_int', topCategories[i].percent.round());
            } else {
              await HomeWidget.saveWidgetData<String>('category_${catIndex}_name', '');
              await HomeWidget.saveWidgetData<double>('category_${catIndex}_percent', 0.0);
              await HomeWidget.saveWidgetData<int>('category_${catIndex}_percent_int', 0);
            }
          }
        }

        await HomeWidget.saveWidgetData<String>('month_spend_amount', cashOutFormatted);
        await HomeWidget.saveWidgetData<String>('month_income_amount', cashInFormatted);
        await HomeWidget.saveWidgetData<double>('month_spend_raw', cashOutRaw);
        await HomeWidget.saveWidgetData<double>('month_income_raw', cashInRaw);
      }

      await HomeWidget.saveWidgetData<String>('last_sync_timestamp', timestamp);
      await HomeWidget.saveWidgetData<String>('deep_link_uri', deepLinkUri);

      // 2. Trigger native widget updates
      if (Platform.isAndroid) {
        // Update XML RemoteViews provider
        await HomeWidget.updateWidget(
          name: androidWidgetProvider,
          qualifiedAndroidName: androidWidgetQualified,
        );
        // Also update Jetpack Glance receiver if registered
        try {
          await HomeWidget.updateWidget(
            qualifiedAndroidName: androidGlanceQualified,
          );
        } catch (_) {
          // Glance widget receiver is optional on Android and may be absent in some builds.
        }
      } else if (Platform.isIOS) {
        await HomeWidget.updateWidget(
          iOSName: iOSWidgetName,
        );
      }

      debugPrint('WidgetSyncService: Synced data for "${company.name}" (In: $cashInFormatted, Out: $cashOutFormatted)');
      return true;
    } catch (e) {
      debugPrint('WidgetSyncService.syncWidgetData error: $e');
      return false;
    }
  }
}
