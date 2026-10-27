import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/services/widget_sync_service.dart';
import '../../data/models/company_mode.dart';
import 'company_providers.dart';
import 'expense_providers.dart';
import 'ledger_providers.dart';

/// Provider that listens to active company and business/expense summary to keep
/// native Home Screen Widgets continuously up to date in real time.
final widgetSyncProvider = Provider<void>((ref) {
  final company = ref.watch(activeCompanyProvider);

  if (company.mode == CompanyMode.expenseTracker) {
    // In expense mode, watch this month's expense summary (spend and income)
    final summaryAsync = ref.watch(monthSummaryProvider);
    summaryAsync.whenData((summary) {
      Future.microtask(() {
        WidgetSyncService.syncWidgetData(
          company: company,
          monthSpendCents: summary.totalExpenseInCents,
          monthIncomeCents: summary.totalIncomeInCents,
        );
      });
    });
    return;
  }

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
      if (company.mode == CompanyMode.expenseTracker) {
        final repo = ref.read(expenseRepositoryProvider);
        final summary = await repo.getMonthSummary(DateTime.now());
        await WidgetSyncService.syncWidgetData(
          company: company,
          monthSpendCents: summary.totalExpenseInCents,
          monthIncomeCents: summary.totalIncomeInCents,
        );
        return;
      }
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

