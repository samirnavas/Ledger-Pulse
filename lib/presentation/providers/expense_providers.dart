import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/drift_expense_repository.dart';
import '../../data/models/account_model.dart';
import '../../data/models/company_model.dart';
import '../../data/models/voucher_model.dart';
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
  TransactionFilters build() => const TransactionFilters();

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

  return await repo.getTransactions(
    startDate: start,
    endDate: end,
    categoryIds: filters.categoryIds,
    walletIds: filters.walletIds,
    textQuery: filters.textQuery,
    type: filters.type,
  );
});

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

  return await repo.getWallets(includeArchived: false);
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

  return await repo.getCategories(includeArchived: false);
});
