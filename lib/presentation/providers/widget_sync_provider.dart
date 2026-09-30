import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/services/widget_sync_service.dart';
import 'company_providers.dart';
import 'ledger_providers.dart';

/// Provider that listens to active company and business summary to keep
/// native Home Screen Widgets continuously up to date in real time.
final widgetSyncProvider = Provider<void>((ref) {
  final company = ref.watch(activeCompanyProvider);
  final summaryAsync = ref.watch(businessSummaryProvider);

  summaryAsync.whenData((summary) {
    Future.microtask(() {
      WidgetSyncService.syncWidgetData(
        company: company,
        totalReceivableCents: summary.$1,
        totalPayableCents: summary.$2,
      );
    });
  });
});

/// Manual trigger helper to immediately sync current state
final syncWidgetDataActionProvider = Provider<Future<void> Function()>((ref) {
  return () async {
    try {
      final company = ref.read(activeCompanyProvider);
      final repo = ref.read(ledgerRepositoryProvider);
      final summary = await repo.getBusinessSummary();
      await WidgetSyncService.syncWidgetData(
        company: company,
        totalReceivableCents: summary.$1,
        totalPayableCents: summary.$2,
      );
    } catch (e) {
      debugPrint('syncWidgetDataActionProvider error: $e');
    }
  };
});
