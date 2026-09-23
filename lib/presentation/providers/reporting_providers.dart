import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/transaction_model.dart';
import '../../data/models/voucher_model.dart';
import '../../data/reporting/custom_sql_report_engine.dart';
import '../../data/reporting/financial_statement_engine.dart';
import '../../data/reporting/inventory_report_engine.dart';
import '../../data/reporting/report_catalog.dart';
import '../../data/reporting/report_models.dart';
import 'company_providers.dart';
import 'inventory_providers.dart';
import 'ledger_providers.dart';
import 'voucher_providers.dart';

final customSqlReportEngineProvider = Provider<CustomSqlReportEngine>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return CustomSqlReportEngine(db);
});

final reportCatalogProvider = Provider<List<ReportMetadata>>((ref) {
  return ReportCatalog.allReports;
});

class SelectedReportCategoryNotifier extends Notifier<ReportCategory?> {
  @override
  ReportCategory? build() => null;

  void selectCategory(ReportCategory? category) {
    state = category;
  }
}

final selectedReportCategoryProvider =
    NotifierProvider<SelectedReportCategoryNotifier, ReportCategory?>(
  SelectedReportCategoryNotifier.new,
);

/// Generates ReportData for a selected report ID
final dynamicReportDataProvider = FutureProvider.family<ReportData, String>((ref, reportId) async {
  final company = ref.watch(activeCompanyProvider);
  final parties = await ref.watch(partyListProvider.future);
  final vouchers = await ref.watch(vouchersListProvider(null).future);
  final items = await ref.watch(inventoryItemsListProvider.future);
  final db = ref.watch(appDatabaseProvider);
  final entries = await db.select(db.ledgerEntries).get();

  final convertedEntries = entries
      .map((row) => LedgerEntry(
            id: row.id,
            partyId: row.partyId,
            amountInCents: row.amountInCents,
            type: row.type,
            date: row.date,
            note: row.note,
            receiptPhotoUrl: row.receiptPhotoUrl,
            isVoided: row.isVoided,
          ))
      .toList();

  switch (reportId) {
    case 'rpt_balance_sheet':
      return FinancialStatementEngine.generateBalanceSheet(
        company: company,
        parties: parties,
        items: items,
        entries: convertedEntries,
        vouchers: vouchers,
      );

    case 'rpt_pnl':
      return FinancialStatementEngine.generateProfitAndLoss(
        company: company,
        vouchers: vouchers,
        items: items,
        entries: convertedEntries,
      );

    case 'rpt_trial_balance':
      return FinancialStatementEngine.generateTrialBalance(
        parties: parties,
        vouchers: vouchers,
        items: items,
      );

    case 'rpt_day_book':
      return FinancialStatementEngine.generateDayBook(
        vouchers: vouchers,
        entries: convertedEntries,
      );

    case 'rpt_cash_flow':
      return FinancialStatementEngine.generateCashFlowStatement(
        vouchers: vouchers,
        entries: convertedEntries,
      );

    case 'rpt_stock_summary':
      return InventoryReportEngine.generateStockSummary(items: items);

    case 'rpt_low_stock':
      return InventoryReportEngine.generateLowStockRegister(items: items);

    default:
      // Fallback: generate balance sheet or default statement
      return FinancialStatementEngine.generateBalanceSheet(
        company: company,
        parties: parties,
        items: items,
        entries: convertedEntries,
        vouchers: vouchers,
      );
  }
});

class DashboardBiMetrics {
  final int totalIncomeInCents;
  final int totalExpenseInCents;
  final int netProfitInCents;
  final int totalReceivableInCents;
  final int totalPayableInCents;
  final double salesVelocityPerDayInCents;
  final List<MonthlyTrendPoint> monthlyTrends;
  final List<CategoryShare> topExpenseCategories;

  const DashboardBiMetrics({
    required this.totalIncomeInCents,
    required this.totalExpenseInCents,
    required this.netProfitInCents,
    required this.totalReceivableInCents,
    required this.totalPayableInCents,
    required this.salesVelocityPerDayInCents,
    required this.monthlyTrends,
    required this.topExpenseCategories,
  });
}

class MonthlyTrendPoint {
  final String monthLabel;
  final int incomeInCents;
  final int expenseInCents;

  const MonthlyTrendPoint({
    required this.monthLabel,
    required this.incomeInCents,
    required this.expenseInCents,
  });
}

class CategoryShare {
  final String categoryName;
  final int amountInCents;
  final double percentage;

  const CategoryShare({
    required this.categoryName,
    required this.amountInCents,
    required this.percentage,
  });
}

final dashboardBiMetricsProvider = FutureProvider<DashboardBiMetrics>((ref) async {
  final (totalReceivable, totalPayable) = await ref.watch(businessSummaryProvider.future);
  final vouchers = await ref.watch(vouchersListProvider(null).future);

  int totalIncome = 0;
  int totalExpense = 0;

  final Map<String, int> monthlyIncome = {};
  final Map<String, int> monthlyExpense = {};
  final Map<String, int> expenseCategories = {};

  final now = DateTime.now();
  final monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  // Seed last 4 months
  for (int i = 3; i >= 0; i--) {
    final d = DateTime(now.year, now.month - i, 1);
    final key = '${monthNames[d.month - 1]} ${d.year.toString().substring(2)}';
    monthlyIncome[key] = 0;
    monthlyExpense[key] = 0;
  }

  for (final v in vouchers) {
    final isIncome = v.type == VoucherType.sales || v.type == VoucherType.receipt;
    final isExpense = v.type == VoucherType.purchase || v.type == VoucherType.payment;

    if (isIncome) {
      totalIncome += v.totalAmountInCents;
      final mKey = '${monthNames[v.date.month - 1]} ${v.date.year.toString().substring(2)}';
      if (monthlyIncome.containsKey(mKey)) {
        monthlyIncome[mKey] = (monthlyIncome[mKey] ?? 0) + v.totalAmountInCents;
      }
    } else if (isExpense) {
      totalExpense += v.totalAmountInCents;
      final mKey = '${monthNames[v.date.month - 1]} ${v.date.year.toString().substring(2)}';
      if (monthlyExpense.containsKey(mKey)) {
        monthlyExpense[mKey] = (monthlyExpense[mKey] ?? 0) + v.totalAmountInCents;
      }
      final cat = (v.narration != null && v.narration!.trim().isNotEmpty)
          ? v.narration!.trim()
          : (v.type == VoucherType.purchase ? 'Stock Purchases' : 'Vendor Payments');
      expenseCategories[cat] = (expenseCategories[cat] ?? 0) + v.totalAmountInCents;
    }
  }

  final trends = monthlyIncome.keys.map((k) {
    return MonthlyTrendPoint(
      monthLabel: k,
      incomeInCents: monthlyIncome[k] ?? 0,
      expenseInCents: monthlyExpense[k] ?? 0,
    );
  }).toList();

  final sortedCategories = expenseCategories.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final top5 = sortedCategories.take(5).map((e) {
    final pct = totalExpense > 0 ? (e.value / totalExpense) * 100 : 0.0;
    return CategoryShare(categoryName: e.key, amountInCents: e.value, percentage: pct);
  }).toList();

  final salesVelocity = totalIncome > 0 ? (totalIncome / 30.0) : 0.0;

  return DashboardBiMetrics(
    totalIncomeInCents: totalIncome,
    totalExpenseInCents: totalExpense,
    netProfitInCents: totalIncome - totalExpense,
    totalReceivableInCents: totalReceivable,
    totalPayableInCents: totalPayable,
    salesVelocityPerDayInCents: salesVelocity,
    monthlyTrends: trends,
    topExpenseCategories: top5,
  );
});

