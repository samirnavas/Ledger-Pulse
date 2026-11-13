import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/services/widget_sync_service.dart';
import '../../data/models/budget_model.dart';
import '../../data/models/company_model.dart';
import '../../data/models/voucher_model.dart';
import 'budget_providers.dart';
import 'company_providers.dart';
import 'expense_providers.dart';
import 'ledger_providers.dart';

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
      _syncExpenseWidgetData(
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

Future<void> _syncExpenseWidgetData({
  required Company company,
  required ExpenseMonthSummary summary,
  required List<AccountModel> categories,
  required List<BudgetModel> budgets,
  required List<VoucherModel> transactions,
}) async {
  final now = DateTime.now();

  // 1. Calculate today's spend from today's expense transactions
  final todayTxns = transactions.where(
    (t) =>
        t.date.year == now.year &&
        t.date.month == now.month &&
        t.date.day == now.day &&
        t.type == VoucherType.expense,
  );
  int todaySpendCents = 0;
  for (final t in todayTxns) {
    todaySpendCents += t.totalAmountInCents;
  }

  // 2. Calculate budget from active budgets (overall allocated budget)
  int totalBudgetCents = 0;
  for (final b in budgets.where((b) => b.isActive && !b.isDeleted)) {
    totalBudgetCents += b.amountInCents;
  }

  // 3. Calculate top 3 categories by monthly expense
  final catNameMap = {for (final c in categories) c.id: c.name};
  final sortedCats =
      summary.expenseCategoryTotalsInCents.entries
          .where((e) => e.value > 0)
          .toList()
        ..sort((a, b) => b.value.compareTo(a.value));

  final int totalExpenseInCents = summary.totalExpenseInCents;
  final List<({String name, double percent})> topCategories = [];

  if (sortedCats.isNotEmpty && totalExpenseInCents > 0) {
    for (final entry in sortedCats.take(3)) {
      final rawName = catNameMap[entry.key];
      final name = (rawName != null && rawName.trim().isNotEmpty) ? rawName : 'Other';
      final double pct = (entry.value / totalExpenseInCents) * 100.0;
      topCategories.add((name: name, percent: pct));
    }
  }

  // If fewer than 3 categories with spend, fallback to available category names
  if (topCategories.length < 3) {
    for (final cat in categories) {
      if (!topCategories.any((c) => c.name == cat.name)) {
        topCategories.add((name: cat.name, percent: 0.0));
        if (topCategories.length == 3) break;
      }
    }
  }

  // Fallback defaults if still empty (brand new profile)
  if (topCategories.isEmpty) {
    topCategories.addAll([
      (name: 'Food & Dining', percent: 45.0),
      (name: 'Groceries', percent: 30.0),
      (name: 'Travel', percent: 25.0),
    ]);
  }

  // If all percentages are 0, distribute nicely for the chart
  final allZero = topCategories.every((c) => c.percent <= 0.0);
  final finalCategories = allZero
      ? [
          (name: topCategories[0].name, percent: 45.0),
          if (topCategories.length > 1)
            (name: topCategories[1].name, percent: 30.0),
          if (topCategories.length > 2)
            (name: topCategories[2].name, percent: 25.0),
        ]
      : topCategories;

  await WidgetSyncService.syncWidgetData(
    company: company,
    monthSpendCents: summary.totalExpenseInCents,
    monthIncomeCents: summary.totalIncomeInCents,
    todaySpendCents: todaySpendCents,
    budgetCents: totalBudgetCents > 0 ? totalBudgetCents : null,
    topCategories: finalCategories,
  );
}

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

        await _syncExpenseWidgetData(
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
