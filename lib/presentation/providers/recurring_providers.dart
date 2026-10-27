import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/company_mode.dart';
import '../../data/models/recurring_rule_model.dart';
import '../../data/services/recurring_service.dart';
import 'company_providers.dart';
import 'database_providers.dart';
import 'expense_providers.dart';

/// Provider for RecurringService scoped to the active company.
final recurringServiceProvider = Provider<RecurringService>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final expenseRepo = ref.watch(expenseRepositoryProvider);
  final syncEngine = ref.watch(syncEngineProvider);
  final company = ref.watch(activeCompanyProvider);

  final service = RecurringService(
    db: db,
    expenseRepo: expenseRepo,
    syncEngine: syncEngine,
    currentCompanyId: company.id,
    company: company,
  );

  ref.onDispose(service.dispose);
  return service;
});

/// Reactive list of recurring rules for the active company.
final recurringRulesListProvider =
    FutureProvider<List<RecurringRuleModel>>((ref) async {
  final company = ref.watch(activeCompanyProvider);
  if (company.mode != CompanyMode.expenseTracker ||
      !company.isModuleEnabled(AppModule.recurring)) {
    return const [];
  }

  final service = ref.watch(recurringServiceProvider);
  final sub = service.repositoryUpdatesStream.listen((_) {
    ref.invalidateSelf();
  });
  ref.onDispose(sub.cancel);

  return await service.getRules(includeInactive: true);
});
