import 'package:flutter/foundation.dart';
import '../../data/models/expense/expense_category_model.dart';
import '../../data/models/expense/expense_transaction_model.dart';
import '../../data/models/expense/expense_wallet_model.dart';

@immutable
class ExpenseSummary {
  final int totalIncomeInCents;
  final int totalExpenseInCents;
  final int netSavingsInCents;
  final int transactionCount;

  const ExpenseSummary({
    this.totalIncomeInCents = 0,
    this.totalExpenseInCents = 0,
    this.netSavingsInCents = 0,
    this.transactionCount = 0,
  });

  double get totalIncome => totalIncomeInCents / 100.0;
  double get totalExpense => totalExpenseInCents / 100.0;
  double get netSavings => netSavingsInCents / 100.0;
}

@immutable
class ExpenseTransactionFilter {
  final String? walletId;
  final String? categoryId;
  final ExpenseTransactionType? type;
  final DateTime? startDate;
  final DateTime? endDate;
  final String? searchQuery;

  const ExpenseTransactionFilter({
    this.walletId,
    this.categoryId,
    this.type,
    this.startDate,
    this.endDate,
    this.searchQuery,
  });
}

abstract class IExpenseRepository {
  String get currentProfileId;

  // Transactions
  Future<List<ExpenseTransactionModel>> getTransactions({
    ExpenseTransactionFilter? filter,
    int? limit,
    int? offset,
  });

  Future<ExpenseTransactionModel> addTransaction(ExpenseTransactionModel transaction);
  Future<ExpenseTransactionModel> updateTransaction(ExpenseTransactionModel transaction);
  Future<void> deleteTransaction(String id);

  // Wallets
  Future<List<ExpenseWalletModel>> getWallets({bool includeArchived = false});
  Future<ExpenseWalletModel> addWallet(ExpenseWalletModel wallet);
  Future<ExpenseWalletModel> updateWallet(ExpenseWalletModel wallet);
  Future<void> deleteWallet(String id);

  // Categories
  Future<List<ExpenseCategoryModel>> getCategories({ExpenseCategoryType? type});
  Future<ExpenseCategoryModel> addCategory(ExpenseCategoryModel category);
  Future<ExpenseCategoryModel> updateCategory(ExpenseCategoryModel category);
  Future<void> deleteCategory(String id);

  // Metrics
  Future<ExpenseSummary> getSummary({DateTime? startDate, DateTime? endDate});

  Stream<void> get repositoryUpdatesStream;
  void dispose();
}

