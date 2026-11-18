import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';
import '../../core/services/widget_entry_service.dart';
import '../../core/services/widget_sync_service.dart';
import '../../data/models/company_model.dart';
import 'auth_providers.dart';
import 'budget_providers.dart';
import 'company_providers.dart';
import 'expense_providers.dart';
import 'ledger_providers.dart';
import 'profile_provider.dart';

final widgetKeypadEnabledProvider = FutureProvider<bool>((ref) async {
  return await HomeWidget.getWidgetData<bool>(WidgetEntryService.enabledKey) ??
      false;
});

final widgetEntryContextProvider = Provider<void>((ref) {
  if (kIsWeb || !Platform.isAndroid) return;
  final company = ref.watch(activeCompanyProvider);
  final userId = ref.watch(activeUserIdProvider);
  final authLoading = ref.watch(
    authControllerProvider.select((auth) => auth.isLoading),
  );
  final role = ref.watch(userProfileProvider.select((profile) => profile.role));
  final isExpense = company.mode == CompanyMode.expenseTracker;
  final wallets = isExpense ? ref.watch(walletsProvider).value : null;
  final categories = isExpense ? ref.watch(categoriesProvider).value : null;
  final enabled = ref.watch(widgetKeypadEnabledProvider).value;
  Future.microtask(() async {
    if (!ref.mounted) return;
    try {
      if (authLoading || !isExpense || enabled == false) {
        await WidgetEntryService.clear();
      } else if (enabled == true && wallets != null && categories != null) {
        await WidgetEntryService.publish(
          company: company,
          userId: userId,
          role: role,
          wallets: wallets,
          categories: categories,
        );
      }
    } catch (error) {
      debugPrint('Could not update widget keypad settings: $error');
    }
  });
});

/// Provider that listens to active company and business/expense summary to keep
/// native Home Screen Widgets continuously up to date in real time.
final widgetSyncProvider = Provider<void>((ref) {
  final company = ref.watch(activeCompanyProvider);

  if (company.mode == CompanyMode.expenseTracker) {
    // In expense mode, watch this month's expense summary, categories, budgets, and transactions
    final summaryAsync = ref.watch(monthSummaryProvider);
    final categoriesAsync = ref.watch(categoriesProvider);
    final budgetsAsync = ref.watch(budgetsListProvider);
    final transactionsAsync = ref.watch(transactionsProvider);

    final summary = summaryAsync.value;
    if (summary == null) return;

    final categories = categoriesAsync.value ?? [];
    final budgets = budgetsAsync.value ?? [];
    final transactions = transactionsAsync.value ?? [];

    Future.microtask(() {
      syncExpenseWidgetData(
        company: company,
        summary: summary,
        categories: categories,
        budgets: budgets,
        transactions: transactions,
      );
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
        final budgetRepo = ref.read(budgetRepositoryProvider);
        final now = DateTime.now();
        final summary = await repo.getMonthSummary(now);
        final categories = await repo.getCategories();
        final budgets = await budgetRepo.getBudgets(includeInactive: false);
        final startOfMonth = DateTime(now.year, now.month, 1);
        final endOfMonth = DateTime(
          now.year,
          now.month + 1,
          0,
          23,
          59,
          59,
          999,
        );
        final transactions = await repo.getTransactions(
          startDate: startOfMonth,
          endDate: endOfMonth,
        );

        await syncExpenseWidgetData(
          company: company,
          summary: summary,
          categories: categories,
          budgets: budgets,
          transactions: transactions,
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
