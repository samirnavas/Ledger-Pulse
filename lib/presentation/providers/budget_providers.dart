import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/drift_budget_repository.dart';
import '../../data/models/budget_model.dart';
import '../../data/models/company_mode.dart';
import 'company_providers.dart';
import 'database_providers.dart';
import 'expense_providers.dart';

/// Active instance of DriftBudgetRepository scoped to the active company.
final budgetRepositoryProvider = Provider<DriftBudgetRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final syncEngine = ref.watch(syncEngineProvider);
  final company = ref.watch(activeCompanyProvider);

  final repo = DriftBudgetRepository(
    db: db,
    syncEngine: syncEngine,
    currentCompanyId: company.id,
    company: company,
  );

  ref.onDispose(repo.dispose);
  return repo;
});

/// Reactive stream of active budgets for the current company.
final budgetsListProvider = FutureProvider<List<BudgetModel>>((ref) async {
  final company = ref.watch(activeCompanyProvider);
  if (company.mode != CompanyMode.expenseTracker ||
      !company.isModuleEnabled(AppModule.budgets)) {
    return const [];
  }

  final repo = ref.watch(budgetRepositoryProvider);
  final sub = repo.repositoryUpdatesStream.listen((_) {
    ref.invalidateSelf();
  });
  ref.onDispose(sub.cancel);

  return await repo.getBudgets(includeInactive: false);
});

/// Reactive stream of calculated BudgetProgress for all active budgets.
final budgetsProgressListProvider =
    FutureProvider<List<BudgetProgress>>((ref) async {
  final company = ref.watch(activeCompanyProvider);
  if (company.mode != CompanyMode.expenseTracker ||
      !company.isModuleEnabled(AppModule.budgets)) {
    return const [];
  }

  final repo = ref.watch(budgetRepositoryProvider);
  final selectedMonth = ref.watch(selectedMonthProvider);

  // Invalidate when repo updates or transactions change
  final sub = repo.repositoryUpdatesStream.listen((_) {
    ref.invalidateSelf();
  });
  ref.onDispose(sub.cancel);

  final budgets = await repo.getBudgets(includeInactive: false);
  final result = <BudgetProgress>[];
  for (final b in budgets) {
    final progress = await repo.calculateProgress(b, asOfDate: selectedMonth);
    result.add(progress);
  }
  return result;
});

/// Overall monthly budget summary combining all active budgets.
final overallMonthlyBudgetProvider =
    FutureProvider<OverallBudgetSummary>((ref) async {
  final company = ref.watch(activeCompanyProvider);
  if (company.mode != CompanyMode.expenseTracker ||
      !company.isModuleEnabled(AppModule.budgets)) {
    return OverallBudgetSummary.empty();
  }

  final repo = ref.watch(budgetRepositoryProvider);
  final selectedMonth = ref.watch(selectedMonthProvider);

  final sub = repo.repositoryUpdatesStream.listen((_) {
    ref.invalidateSelf();
  });
  ref.onDispose(sub.cancel);

  return await repo.getOverallMonthlyBudget(month: selectedMonth);
});
