import 'package:drift/drift.dart' show TableUpdateQuery;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/drift_expense_repository.dart';
import '../../data/models/account_model.dart';
import '../../data/models/company_model.dart';
import '../../data/models/voucher_model.dart';
import 'auth_providers.dart';
import 'company_providers.dart';
import 'database_providers.dart';
import 'profile_provider.dart';

export '../../data/local/drift_expense_repository.dart'
    show ExpenseMonthSummary, TransactionFilters;

/// Scoped instance of [DriftExpenseRepository] for the active company and authenticated user.
final expenseRepositoryProvider = Provider<DriftExpenseRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final syncEngine = ref.watch(syncEngineProvider);
  final activeCompany = ref.watch(activeCompanyProvider);
  final userId = ref.watch(userProfileProvider.select((p) => p.id));
  final role = ref.watch(userProfileProvider.select((p) => p.role));

  final repo = DriftExpenseRepository(
    db: db,
    syncEngine: syncEngine,
    currentCompanyId: activeCompany.id,
    currentUserId: userId,
    currentRole: role,
    company: activeCompany,
  );

  ref.onDispose(() {
    repo.dispose();
  });

  return repo;
});

/// Notifier controlling currently selected viewing month in expense mode.
class SelectedMonthNotifier extends Notifier<DateTime> {
  @override
  DateTime build() {
    ref.watch(activeCompanyProvider.select((company) => company.id));
    final now = DateTime.now();
    return DateTime(now.year, now.month);
  }

  void setMonth(DateTime month) {
    state = DateTime(month.year, month.month);
  }
}

/// Currently selected viewing month in expense mode (defaults to current year and month).
final selectedMonthProvider =
    NotifierProvider<SelectedMonthNotifier, DateTime>(
  SelectedMonthNotifier.new,
);

/// Notifier controlling active transaction filters.
class TransactionFiltersNotifier extends Notifier<TransactionFilters> {
  @override
  TransactionFilters build() {
    ref.watch(activeCompanyProvider.select((company) => company.id));
    return const TransactionFilters();
  }

  void updateFilters(TransactionFilters filters) {
    state = filters;
  }

  void reset() {
    state = const TransactionFilters();
  }
}

/// Active transaction filter criteria (category, wallet, search query, type, custom date range).
final transactionFiltersProvider =
    NotifierProvider<TransactionFiltersNotifier, TransactionFilters>(
  TransactionFiltersNotifier.new,
);

final dashboardTransactionHistoryProvider =
    FutureProvider.autoDispose<({bool hasActivity, bool hasExpense})>((ref) {
  _watchDashboardTransactionUpdates(ref);
  return ref.watch(expenseRepositoryProvider).getTransactionHistory();
});

/// The dashboard uses the selected reporting month independently of list filters.
final dashboardRecentTransactionsProvider = FutureProvider.autoDispose<List<VoucherModel>>((ref) {
  _watchDashboardTransactionUpdates(ref);
  final month = ref.watch(selectedMonthProvider);
  return ref.watch(expenseRepositoryProvider).getTransactions(
    startDate: DateTime(month.year, month.month),
    endDate: DateTime(month.year, month.month + 1).subtract(const Duration(milliseconds: 1)),
    limit: 10,
  );
});

void _watchDashboardTransactionUpdates(Ref ref) {
  final db = ref.watch(appDatabaseProvider);
  final changes = db.tableUpdates(TableUpdateQuery.onTable(db.expenseTransactions))
      .listen((_) => ref.invalidateSelf());
  ref.onDispose(changes.cancel);
}

String dashboardSetupPreferenceKey(String userId, String workspaceId) =>
    'dashboard_setup_${userId}_$workspaceId';

/// True when dismissed, false when setup was offered during workspace creation.
final dashboardSetupPreferenceProvider = Provider.autoDispose.family<bool?, String>((ref, workspaceId) {
  final user = ref.watch(activeUserIdProvider);
  return ref.watch(sharedPreferencesProvider)?.getBool(dashboardSetupPreferenceKey(user, workspaceId));
});

/// Reactive stream of transactions for the selected month and active filters.
/// Automatically refreshed when the repository updates stream emits.
final transactionsProvider = FutureProvider<List<VoucherModel>>((ref) async {
  final company = ref.watch(activeCompanyProvider);
  if (company.mode != CompanyMode.expenseTracker) {
    return const [];
  }

  final repo = ref.watch(expenseRepositoryProvider);
  final sub = repo.repositoryUpdatesStream.listen((_) {
    ref.invalidateSelf();
  });
  ref.onDispose(sub.cancel);

  final filters = ref.watch(transactionFiltersProvider);
  final selectedMonth = ref.watch(selectedMonthProvider);

  // If filters do not specify explicit dates, constrain to the selected month
  final start = filters.startDate ??
      DateTime(selectedMonth.year, selectedMonth.month, 1);
  final end = filters.endDate ??
      DateTime(selectedMonth.year, selectedMonth.month + 1, 0, 23, 59, 59, 999);
  final categoryIds = filters.categoryIds;
  final expandedCategoryIds = categoryIds == null || categoryIds.isEmpty
      ? categoryIds
      : await _includeSubcategories(repo, categoryIds);

  return await repo.getTransactions(
    startDate: start,
    endDate: end,
    categoryIds: expandedCategoryIds,
    walletIds: filters.walletIds,
    textQuery: filters.textQuery,
    type: filters.type,
  );
});

Future<List<String>> _includeSubcategories(
  DriftExpenseRepository repo,
  List<String> categoryIds,
) async {
  final categories = await repo.getCategories(includeArchived: true);
  final childrenByParent = <String, List<String>>{};
  for (final category in categories) {
    final parent = category.parentAccountId;
    if (parent != null) {
      childrenByParent.putIfAbsent(parent, () => []).add(category.id);
    }
  }

  final matchedIds = categoryIds.toSet();
  final pending = matchedIds.toList();
  while (pending.isNotEmpty) {
    final children = childrenByParent[pending.removeLast()] ?? const <String>[];
    for (final child in children) {
      if (matchedIds.add(child)) pending.add(child);
    }
  }
  return matchedIds.toList();
}

/// Reactive summary for the selected month (total income, total expense, net, wallet balances, category totals).
/// Refreshed from repositoryUpdatesStream like partyListProvider.
final monthSummaryProvider = FutureProvider<ExpenseMonthSummary>((ref) async {
  final company = ref.watch(activeCompanyProvider);
  if (company.mode != CompanyMode.expenseTracker) {
    return ExpenseMonthSummary.empty(DateTime.now());
  }

  final repo = ref.watch(expenseRepositoryProvider);
  final sub = repo.repositoryUpdatesStream.listen((_) {
    ref.invalidateSelf();
  });
  ref.onDispose(sub.cancel);

  final selectedMonth = ref.watch(selectedMonthProvider);
  _watchDashboardTransactionUpdates(ref);
  return await repo.getMonthSummary(selectedMonth);
});

/// Reactive list of active wallets (Asset and Liability accounts).
/// Refreshed from repositoryUpdatesStream.
final walletsProvider = FutureProvider<List<AccountModel>>((ref) async {
  final company = ref.watch(activeCompanyProvider);
  if (company.mode != CompanyMode.expenseTracker) {
    return const [];
  }

  final repo = ref.watch(expenseRepositoryProvider);
  final sub = repo.repositoryUpdatesStream.listen((_) {
    ref.invalidateSelf();
  });
  ref.onDispose(sub.cancel);
  final db = ref.watch(appDatabaseProvider);
  final projection = db.tableUpdates(TableUpdateQuery.onTable(db.expenseWallets))
      .listen((_) => ref.invalidateSelf());
  ref.onDispose(projection.cancel);

  return await repo.getWallets(includeArchived: false);
});

final defaultWalletIdProvider = FutureProvider<String?>((ref) async {
  if (ref.watch(activeCompanyProvider).mode != CompanyMode.expenseTracker) {
    return null;
  }
  final db = ref.watch(appDatabaseProvider);
  final subscription = db.tableUpdates(TableUpdateQuery.onTable(db.userPreferences))
      .listen((_) => ref.invalidateSelf());
  ref.onDispose(subscription.cancel);
  return ref.watch(expenseRepositoryProvider).getDefaultWalletId();
});

final archivedWalletsProvider = FutureProvider.autoDispose<List<AccountModel>>((ref) async {
  final company = ref.watch(activeCompanyProvider);
  if (!company.isExpense) return const [];
  final repo = ref.watch(expenseRepositoryProvider);
  final sub = repo.repositoryUpdatesStream.listen((_) => ref.invalidateSelf());
  ref.onDispose(sub.cancel);
  final db = ref.watch(appDatabaseProvider);
  final projection = db.tableUpdates(TableUpdateQuery.onTable(db.expenseWallets))
      .listen((_) => ref.invalidateSelf());
  ref.onDispose(projection.cancel);
  final wallets = await repo.getWallets(includeArchived: true);
  return wallets.where((wallet) => !wallet.isActive).toList();
});

/// Reactive list of active expense and income categories.
/// Refreshed from repositoryUpdatesStream.
final categoriesProvider = FutureProvider<List<AccountModel>>((ref) async {
  final company = ref.watch(activeCompanyProvider);
  if (company.mode != CompanyMode.expenseTracker) {
    return const [];
  }

  final repo = ref.watch(expenseRepositoryProvider);
  final sub = repo.repositoryUpdatesStream.listen((_) {
    ref.invalidateSelf();
  });
  ref.onDispose(sub.cancel);
  final db = ref.watch(appDatabaseProvider);
  final projection = db.tableUpdates(TableUpdateQuery.onTable(db.expenseCategories))
      .listen((_) => ref.invalidateSelf());
  ref.onDispose(projection.cancel);

  return await repo.getCategories(usePriority: true);
});

final archivedCategoriesProvider =
    FutureProvider.autoDispose<List<AccountModel>>((ref) async {
  if (ref.watch(activeCompanyProvider).mode != CompanyMode.expenseTracker) {
    return const [];
  }
  final repo = ref.watch(expenseRepositoryProvider);
  final sub = repo.repositoryUpdatesStream.listen((_) => ref.invalidateSelf());
  ref.onDispose(sub.cancel);
  final db = ref.watch(appDatabaseProvider);
  final projection = db.tableUpdates(TableUpdateQuery.onTable(db.expenseCategories))
      .listen((_) => ref.invalidateSelf());
  ref.onDispose(projection.cancel);

  final categories = await repo.getCategories(includeArchived: true);
  return categories.where((category) => !category.isActive).toList();
});
