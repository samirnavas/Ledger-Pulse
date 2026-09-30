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
  static Future<bool> syncWidgetData({
    required Company company,
    required int totalReceivableCents,
    required int totalPayableCents,
  }) async {
    try {
      final currencySym = company.currencyCode == 'INR' ? '₹' : company.currencyCode;
      
      // Formatted with symbol (e.g., "₹ 2,000" or "₹ 2000")
      final cashInFormatted = CurrencyFormatter.format(
        totalReceivableCents,
        includeSymbol: true,
        showDecimalsAlways: false,
      );
      final cashOutFormatted = CurrencyFormatter.format(
        totalPayableCents,
        includeSymbol: true,
        showDecimalsAlways: false,
      );

      // Formatted numbers without symbol (e.g., "2,000")
      final cashInAmountOnly = CurrencyFormatter.format(
        totalReceivableCents,
        includeSymbol: false,
        showDecimalsAlways: false,
      ).trim();
      final cashOutAmountOnly = CurrencyFormatter.format(
        totalPayableCents,
        includeSymbol: false,
        showDecimalsAlways: false,
      ).trim();

      final double cashInRaw = totalReceivableCents / 100.0;
      final double cashOutRaw = totalPayableCents / 100.0;
      final String timestamp = DateTime.now().toIso8601String();
      final String deepLinkUri = 'ledgerpulse://dashboard?company_id=${company.id}';

      // 1. Save data fields
      await HomeWidget.saveWidgetData<String>('company_name', company.name);
      await HomeWidget.saveWidgetData<String>('company_id', company.id);
      await HomeWidget.saveWidgetData<String>('currency_symbol', currencySym);
      await HomeWidget.saveWidgetData<String>('cash_in_amount', cashInFormatted);
      await HomeWidget.saveWidgetData<String>('cash_out_amount', cashOutFormatted);
      await HomeWidget.saveWidgetData<String>('cash_in_value', cashInAmountOnly);
      await HomeWidget.saveWidgetData<String>('cash_out_value', cashOutAmountOnly);
      await HomeWidget.saveWidgetData<double>('cash_in_raw', cashInRaw);
      await HomeWidget.saveWidgetData<double>('cash_out_raw', cashOutRaw);
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
        } catch (_) {}
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
