import 'package:intl/intl.dart';

import '../local/drift_expense_repository.dart';
import '../models/account_model.dart';
import '../models/company_model.dart';
import '../models/journal_model.dart';
import '../models/voucher_model.dart';
import 'financial_statement_engine.dart';
import 'report_models.dart';

/// Item representing spending in a single expense category.
class CategorySpendingItem {
  final String categoryId;
  final String categoryName;
  final int totalSpentInCents;
  final double percentage;
  final int transactionCount;
  final List<CategorySpendingItem> subCategories;

  const CategorySpendingItem({
    required this.categoryId,
    required this.categoryName,
    required this.totalSpentInCents,
    required this.percentage,
    required this.transactionCount,
    this.subCategories = const [],
  });

  double get totalSpent => totalSpentInCents / 100.0;
}

/// Aggregated report for spending across categories in a specific date range.
class CategorySpendingReport {
  final DateTime startDate;
  final DateTime endDate;
  final int totalSpentInCents;
  final List<CategorySpendingItem> categories;

  const CategorySpendingReport({
    required this.startDate,
    required this.endDate,
    required this.totalSpentInCents,
    required this.categories,
  });

  double get totalSpent => totalSpentInCents / 100.0;
}

/// Data for a single month in monthly trend reports.
class MonthlyTrendItem {
  final DateTime month;
  final String monthLabel;
  final int totalIncomeInCents;
  final int totalExpenseInCents;
  final int netSavingsInCents;
  final double savingsRate;

  const MonthlyTrendItem({
    required this.month,
    required this.monthLabel,
    required this.totalIncomeInCents,
    required this.totalExpenseInCents,
    required this.netSavingsInCents,
    required this.savingsRate,
  });

  double get totalIncome => totalIncomeInCents / 100.0;
  double get totalExpense => totalExpenseInCents / 100.0;
  double get netSavings => netSavingsInCents / 100.0;
}

/// Aggregated monthly trends report over a sequence of 6 to 12 months.
class MonthlyTrendReport {
  final List<MonthlyTrendItem> months;
  final int totalIncomeInCents;
  final int totalExpenseInCents;
  final int totalNetSavingsInCents;
  final double averageMonthlyExpenseInCents;

  const MonthlyTrendReport({
    required this.months,
    required this.totalIncomeInCents,
    required this.totalExpenseInCents,
    required this.totalNetSavingsInCents,
    required this.averageMonthlyExpenseInCents,
  });

  double get totalIncome => totalIncomeInCents / 100.0;
  double get totalExpense => totalExpenseInCents / 100.0;
  double get totalNetSavings => totalNetSavingsInCents / 100.0;
  double get averageMonthlyExpense => averageMonthlyExpenseInCents / 100.0;
}

/// Summary report comparing income against expense for a given period.
class IncomeVsExpenseReport {
  final DateTime startDate;
  final DateTime endDate;
  final int totalIncomeInCents;
  final int totalExpenseInCents;
  final int netSavingsInCents;
  final double savingsRate;
  final int incomeTransactionCount;
  final int expenseTransactionCount;
  final int transferTransactionCount;
  final double averageDailySpendInCents;

  const IncomeVsExpenseReport({
    required this.startDate,
    required this.endDate,
    required this.totalIncomeInCents,
    required this.totalExpenseInCents,
    required this.netSavingsInCents,
    required this.savingsRate,
    required this.incomeTransactionCount,
    required this.expenseTransactionCount,
    required this.transferTransactionCount,
    required this.averageDailySpendInCents,
  });

  double get totalIncome => totalIncomeInCents / 100.0;
  double get totalExpense => totalExpenseInCents / 100.0;
  double get netSavings => netSavingsInCents / 100.0;
  double get averageDailySpend => averageDailySpendInCents / 100.0;
}

/// Details of inflows, outflows, and balance for a specific wallet account.
class WalletBalanceHistoryItem {
  final String walletId;
  final String walletName;
  final int openingBalanceInCents;
  final int currentBalanceInCents;
  final int totalInInCents;
  final int totalOutInCents;
  final int transactionCount;

  const WalletBalanceHistoryItem({
    required this.walletId,
    required this.walletName,
    required this.openingBalanceInCents,
    required this.currentBalanceInCents,
    required this.totalInInCents,
    required this.totalOutInCents,
    required this.transactionCount,
  });

  double get openingBalance => openingBalanceInCents / 100.0;
  double get currentBalance => currentBalanceInCents / 100.0;
  double get totalIn => totalInInCents / 100.0;
  double get totalOut => totalOutInCents / 100.0;
}

/// Overview of all wallet accounts and their balance movement.
class WalletBalanceHistoryReport {
  final DateTime asOfDate;
  final int totalBalanceInCents;
  final List<WalletBalanceHistoryItem> wallets;

  const WalletBalanceHistoryReport({
    required this.asOfDate,
    required this.totalBalanceInCents,
    required this.wallets,
  });

  double get totalBalance => totalBalanceInCents / 100.0;
}

/// Pure computation engine for personal/business expense reporting.
/// Generates category breakdowns, monthly trends (6-12 months), income vs expense ratios,
/// wallet balance histories, and reuses [FinancialStatementEngine] for statutory/personal Profit and Loss.
class ExpenseReportEngine {
  // ==========================================
  // SPENDING BY CATEGORY
  // ==========================================

  /// Computes category spending breakdown for a specific period with sub-category rollups.
  static CategorySpendingReport calculateSpendingByCategory({
    required List<VoucherModel> vouchers,
    required List<AccountModel> categories,
    required DateTime startDate,
    required DateTime endDate,
  }) {
    // 1. Filter expense vouchers in range and not voided
    final expenseVouchers = vouchers.where((v) {
      if (v.status == VoucherStatus.voided) return false;
      if (v.type != VoucherType.expense) return false;
      return v.date.isAfter(startDate.subtract(const Duration(milliseconds: 1))) &&
          v.date.isBefore(endDate.add(const Duration(milliseconds: 1)));
    }).toList();

    // 2. Tally spending and transaction count by category ID
    final Map<String, int> spendByCat = {};
    final Map<String, int> countByCat = {};
    int totalSpentInCents = 0;

    for (final v in expenseVouchers) {
      final catId = v.categoryAccountId ?? 'uncategorized';
      spendByCat[catId] = (spendByCat[catId] ?? 0) + v.totalAmountInCents;
      countByCat[catId] = (countByCat[catId] ?? 0) + 1;
      totalSpentInCents += v.totalAmountInCents;
    }

    // Index categories by ID
    final catMap = {for (final c in categories) c.id: c};

    // Separate top-level categories and subcategories
    final topLevelCats = categories.where((c) => c.parentAccountId == null).toList();
    final subCats = categories.where((c) => c.parentAccountId != null).toList();

    final List<CategorySpendingItem> items = [];

    for (final parent in topLevelCats) {
      final ownSpend = spendByCat[parent.id] ?? 0;
      final ownCount = countByCat[parent.id] ?? 0;

      // Find sub-categories of this parent
      final directSubs = subCats.where((s) => s.parentAccountId == parent.id).toList();
      final List<CategorySpendingItem> subItems = [];
      int subTotalSpend = 0;
      int subTotalCount = 0;

      for (final sub in directSubs) {
        final subSpend = spendByCat[sub.id] ?? 0;
        final subCount = countByCat[sub.id] ?? 0;
        subTotalSpend += subSpend;
        subTotalCount += subCount;

        if (subSpend > 0 || subCount > 0) {
          subItems.add(
            CategorySpendingItem(
              categoryId: sub.id,
              categoryName: sub.name,
              totalSpentInCents: subSpend,
              percentage: totalSpentInCents > 0 ? (subSpend / totalSpentInCents) * 100 : 0.0,
              transactionCount: subCount,
            ),
          );
        }
      }

      final combinedSpend = ownSpend + subTotalSpend;
      final combinedCount = ownCount + subTotalCount;

      if (combinedSpend > 0 || combinedCount > 0) {
        // Sort subItems descending by spend
        subItems.sort((a, b) => b.totalSpentInCents.compareTo(a.totalSpentInCents));

        items.add(
          CategorySpendingItem(
            categoryId: parent.id,
            categoryName: parent.name,
            totalSpentInCents: combinedSpend,
            percentage: totalSpentInCents > 0 ? (combinedSpend / totalSpentInCents) * 100 : 0.0,
            transactionCount: combinedCount,
            subCategories: subItems,
          ),
        );
      }
    }

    // Check for categories in spendByCat that weren't captured in topLevelCats (e.g. orphan sub-categories or deleted)
    for (final entry in spendByCat.entries) {
      final catId = entry.key;
      final catObj = catMap[catId];
      final isTopLevel = catObj != null && catObj.parentAccountId == null;
      final isSubOfTopLevel = catObj != null && catObj.parentAccountId != null && topLevelCats.any((t) => t.id == catObj.parentAccountId);

      if (!isTopLevel && !isSubOfTopLevel && entry.value > 0) {
        items.add(
          CategorySpendingItem(
            categoryId: catId,
            categoryName: catObj?.name ?? (catId == 'uncategorized' ? 'Uncategorized' : 'Other Expense'),
            totalSpentInCents: entry.value,
            percentage: totalSpentInCents > 0 ? (entry.value / totalSpentInCents) * 100 : 0.0,
            transactionCount: countByCat[catId] ?? 0,
          ),
        );
      }
    }

    // Sort top items descending by spend
    items.sort((a, b) => b.totalSpentInCents.compareTo(a.totalSpentInCents));

    return CategorySpendingReport(
      startDate: startDate,
      endDate: endDate,
      totalSpentInCents: totalSpentInCents,
      categories: items,
    );
  }

  // ==========================================
  // MONTHLY TREND (LAST 6 TO 12 MONTHS)
  // ==========================================

  /// Computes monthly income, expense, and savings trends for the last [months] months (clamped 1 to 12).
  static MonthlyTrendReport calculateMonthlyTrend({
    required List<VoucherModel> vouchers,
    required DateTime referenceDate,
    int months = 6,
  }) {
    final count = months.clamp(1, 12);
    final activeVouchers = vouchers.where((v) => v.status != VoucherStatus.voided).toList();

    final List<MonthlyTrendItem> trendItems = [];
    int grandTotalIncome = 0;
    int grandTotalExpense = 0;

    // Generate month slots backwards from referenceDate, then reverse for chronological order
    final List<DateTime> monthSlots = [];
    for (int i = count - 1; i >= 0; i--) {
      // Calculate month accurately taking year boundary into account
      int targetYear = referenceDate.year;
      int targetMonth = referenceDate.month - i;
      while (targetMonth < 1) {
        targetMonth += 12;
        targetYear -= 1;
      }
      monthSlots.add(DateTime(targetYear, targetMonth, 1));
    }

    final monthFormat = DateFormat('MMM yyyy');

    for (final slot in monthSlots) {
      final slotStart = slot;
      final slotEnd = DateTime(slot.year, slot.month + 1, 0, 23, 59, 59, 999);

      int monthIncome = 0;
      int monthExpense = 0;

      for (final v in activeVouchers) {
        if (v.date.isAfter(slotStart.subtract(const Duration(milliseconds: 1))) &&
            v.date.isBefore(slotEnd.add(const Duration(milliseconds: 1)))) {
          if (v.type == VoucherType.income) {
            monthIncome += v.totalAmountInCents;
          } else if (v.type == VoucherType.expense) {
            monthExpense += v.totalAmountInCents;
          }
        }
      }

      final net = monthIncome - monthExpense;
      final double savingsRate = monthIncome > 0 ? (net / monthIncome) * 100 : 0.0;

      grandTotalIncome += monthIncome;
      grandTotalExpense += monthExpense;

      trendItems.add(
        MonthlyTrendItem(
          month: slotStart,
          monthLabel: monthFormat.format(slotStart),
          totalIncomeInCents: monthIncome,
          totalExpenseInCents: monthExpense,
          netSavingsInCents: net,
          savingsRate: savingsRate,
        ),
      );
    }

    final grandNet = grandTotalIncome - grandTotalExpense;
    final avgMonthlyExpense = count > 0 ? grandTotalExpense / count : 0.0;

    return MonthlyTrendReport(
      months: trendItems,
      totalIncomeInCents: grandTotalIncome,
      totalExpenseInCents: grandTotalExpense,
      totalNetSavingsInCents: grandNet,
      averageMonthlyExpenseInCents: avgMonthlyExpense,
    );
  }

  // ==========================================
  // INCOME VS EXPENSE
  // ==========================================

  /// Computes income vs expense metrics and savings rate for a date range.
  static IncomeVsExpenseReport calculateIncomeVsExpense({
    required List<VoucherModel> vouchers,
    required DateTime startDate,
    required DateTime endDate,
  }) {
    final filtered = vouchers.where((v) {
      if (v.status == VoucherStatus.voided) return false;
      return v.date.isAfter(startDate.subtract(const Duration(milliseconds: 1))) &&
          v.date.isBefore(endDate.add(const Duration(milliseconds: 1)));
    }).toList();

    int totalIncome = 0;
    int totalExpense = 0;
    int incomeCount = 0;
    int expenseCount = 0;
    int transferCount = 0;

    for (final v in filtered) {
      if (v.type == VoucherType.income) {
        totalIncome += v.totalAmountInCents;
        incomeCount++;
      } else if (v.type == VoucherType.expense) {
        totalExpense += v.totalAmountInCents;
        expenseCount++;
      } else if (v.type == VoucherType.transfer) {
        transferCount++;
      }
    }

    final netSavings = totalIncome - totalExpense;
    final double savingsRate = totalIncome > 0 ? (netSavings / totalIncome) * 100 : 0.0;

    final days = endDate.difference(startDate).inDays.abs() + 1;
    final avgDailySpend = days > 0 ? totalExpense / days : 0.0;

    return IncomeVsExpenseReport(
      startDate: startDate,
      endDate: endDate,
      totalIncomeInCents: totalIncome,
      totalExpenseInCents: totalExpense,
      netSavingsInCents: netSavings,
      savingsRate: savingsRate,
      incomeTransactionCount: incomeCount,
      expenseTransactionCount: expenseCount,
      transferTransactionCount: transferCount,
      averageDailySpendInCents: avgDailySpend,
    );
  }

  // ==========================================
  // WALLET BALANCE HISTORY
  // ==========================================

  /// Computes historical inflows, outflows, and net balances for all wallets.
  static WalletBalanceHistoryReport calculateWalletBalanceHistory({
    required List<AccountModel> wallets,
    required List<VoucherModel> vouchers,
    DateTime? asOfDate,
  }) {
    final activeVouchers = vouchers.where((v) {
      if (v.status == VoucherStatus.voided) return false;
      if (asOfDate != null && v.date.isAfter(asOfDate)) return false;
      return true;
    }).toList();

    final List<WalletBalanceHistoryItem> items = [];
    int totalBalanceInCents = 0;

    for (final wallet in wallets) {
      int totalIn = 0;
      int totalOut = 0;
      int txnCount = 0;

      for (final v in activeVouchers) {
        if (v.type == VoucherType.income && v.walletAccountId == wallet.id) {
          totalIn += v.totalAmountInCents;
          txnCount++;
        } else if (v.type == VoucherType.expense && v.walletAccountId == wallet.id) {
          totalOut += v.totalAmountInCents;
          txnCount++;
        } else if (v.type == VoucherType.transfer) {
          if (v.walletAccountId == wallet.id) {
            totalOut += v.totalAmountInCents;
            txnCount++;
          }
          if (v.toWalletAccountId == wallet.id) {
            totalIn += v.totalAmountInCents;
            txnCount++;
          }
        }
      }

      // Current balance directly from account or derived
      final currentBalance = wallet.currentBalanceInCents;
      totalBalanceInCents += currentBalance;

      items.add(
        WalletBalanceHistoryItem(
          walletId: wallet.id,
          walletName: wallet.name,
          openingBalanceInCents: currentBalance - totalIn + totalOut,
          currentBalanceInCents: currentBalance,
          totalInInCents: totalIn,
          totalOutInCents: totalOut,
          transactionCount: txnCount,
        ),
      );
    }

    return WalletBalanceHistoryReport(
      asOfDate: asOfDate ?? DateTime.now(),
      totalBalanceInCents: totalBalanceInCents,
      wallets: items,
    );
  }

  // ==========================================
  // OPTIONAL PROFIT AND LOSS
  // ==========================================

  /// Reuses [FinancialStatementEngine.generateProfitAndLoss] for statutory / personal P&L reports.
  static ReportData generateProfitAndLoss({
    required Company company,
    required List<VoucherModel> vouchers,
    List<AccountModel> accounts = const [],
    List<JournalLineModel> journalLines = const [],
    DateTime? startDate,
    DateTime? endDate,
  }) {
    List<VoucherModel> filteredVouchers = vouchers;
    if (startDate != null || endDate != null) {
      filteredVouchers = vouchers.where((v) {
        if (v.status == VoucherStatus.voided) return false;
        if (startDate != null && v.date.isBefore(startDate)) return false;
        if (endDate != null && v.date.isAfter(endDate)) return false;
        return true;
      }).toList();
    }

    return FinancialStatementEngine.generateProfitAndLoss(
      company: company,
      vouchers: filteredVouchers,
      accounts: accounts,
      journalLines: journalLines,
    );
  }

  // ==========================================
  // REPOSITORY ASYNC HELPERS
  // ==========================================

  /// Asynchronously fetches data from [DriftExpenseRepository] and returns [CategorySpendingReport].
  static Future<CategorySpendingReport> loadCategorySpending(
    DriftExpenseRepository repo, {
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final vouchers = await repo.getTransactions(
      startDate: startDate,
      endDate: endDate,
      includeVoided: false,
    );
    final categories = await repo.getCategories(includeArchived: true);
    return calculateSpendingByCategory(
      vouchers: vouchers,
      categories: categories,
      startDate: startDate,
      endDate: endDate,
    );
  }

  /// Asynchronously fetches data from [DriftExpenseRepository] and returns [MonthlyTrendReport].
  static Future<MonthlyTrendReport> loadMonthlyTrend(
    DriftExpenseRepository repo, {
    DateTime? referenceDate,
    int months = 6,
  }) async {
    final ref = referenceDate ?? DateTime.now();
    final count = months.clamp(1, 12);
    // Earliest start date is count months before referenceDate
    int startYear = ref.year;
    int startMonth = ref.month - count + 1;
    while (startMonth < 1) {
      startMonth += 12;
      startYear -= 1;
    }
    final earliestDate = DateTime(startYear, startMonth, 1);
    final latestDate = DateTime(ref.year, ref.month + 1, 0, 23, 59, 59, 999);

    final vouchers = await repo.getTransactions(
      startDate: earliestDate,
      endDate: latestDate,
      includeVoided: false,
    );

    return calculateMonthlyTrend(
      vouchers: vouchers,
      referenceDate: ref,
      months: count,
    );
  }

  /// Asynchronously fetches data from [DriftExpenseRepository] and returns [IncomeVsExpenseReport].
  static Future<IncomeVsExpenseReport> loadIncomeVsExpense(
    DriftExpenseRepository repo, {
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final vouchers = await repo.getTransactions(
      startDate: startDate,
      endDate: endDate,
      includeVoided: false,
    );
    return calculateIncomeVsExpense(
      vouchers: vouchers,
      startDate: startDate,
      endDate: endDate,
    );
  }

  /// Asynchronously fetches data from [DriftExpenseRepository] and returns [WalletBalanceHistoryReport].
  static Future<WalletBalanceHistoryReport> loadWalletBalanceHistory(
    DriftExpenseRepository repo, {
    DateTime? asOfDate,
  }) async {
    final wallets = await repo.getWallets(includeArchived: false);
    final vouchers = await repo.getTransactions(includeVoided: false);
    return calculateWalletBalanceHistory(
      wallets: wallets,
      vouchers: vouchers,
      asOfDate: asOfDate,
    );
  }
}
