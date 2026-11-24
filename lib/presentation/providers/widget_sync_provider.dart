import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';
import '../../core/services/widget_entry_service.dart';
import '../../core/services/widget_sync_service.dart';
import '../../data/models/budget_model.dart';
import '../../data/models/company_model.dart';
import '../../data/models/voucher_model.dart';
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

final _widgetTodayExpensesProvider =
    FutureProvider.autoDispose<List<VoucherModel>>((ref) async {
      final repo = ref.watch(expenseRepositoryProvider);
      final subscription = repo.repositoryUpdatesStream.listen((_) {
        ref.invalidateSelf();
      });
      ref.onDispose(subscription.cancel);

      final now = DateTime.now();
      return repo.getTransactions(
        startDate: DateTime(now.year, now.month, now.day),
        endDate: DateTime(
          now.year,
          now.month,
          now.day + 1,
        ).subtract(const Duration(seconds: 1)),
        type: VoucherType.expense,
      );
    });

final _widgetMonthSummaryProvider =
    FutureProvider.autoDispose<ExpenseMonthSummary>((ref) async {
      final repo = ref.watch(expenseRepositoryProvider);
      final subscription = repo.repositoryUpdatesStream.listen((_) {
        ref.invalidateSelf();
      });
      ref.onDispose(subscription.cancel);
      return repo.getMonthSummary(DateTime.now());
    });

final _widgetOverallBudgetProvider =
    FutureProvider.autoDispose<BudgetProgress?>((ref) async {
      final company = ref.watch(activeCompanyProvider);
      if (!company.isModuleEnabled(AppModule.budgets)) return null;
      final budgetRepo = ref.watch(budgetRepositoryProvider);
      final expenseRepo = ref.watch(expenseRepositoryProvider);
      final budgets = budgetRepo.repositoryUpdatesStream.listen((_) {
        ref.invalidateSelf();
      });
      final expenses = expenseRepo.repositoryUpdatesStream.listen((_) {
        ref.invalidateSelf();
      });
      ref.onDispose(budgets.cancel);
      ref.onDispose(expenses.cancel);
      return budgetRepo.getAllCategoriesBudget();
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
  final wallets = isExpense ? ref.watch(walletsProvider).asData?.value : null;
  final categories = isExpense
      ? ref.watch(categoriesProvider).asData?.value
      : null;
  final defaultWallet = isExpense ? ref.watch(defaultWalletIdProvider) : null;
  final enabled = ref.watch(widgetKeypadEnabledProvider).value;
  final hasActiveCompany = ref.watch(
    userCompaniesProvider.select(
      (companies) => companies.any((candidate) => candidate.id == company.id),
    ),
  );
  Future.microtask(() async {
    if (!ref.mounted) return;
    try {
      if (!authLoading &&
          hasActiveCompany &&
          await HomeWidget.getWidgetData<String>(
                WidgetSyncService.activeWorkspaceKey,
              ) !=
              company.id &&
          ref.mounted) {
        await HomeWidget.saveWidgetData(
          WidgetSyncService.activeWorkspaceKey,
          company.id,
        );
        await WidgetEntryService.refresh();
      }
      if (!ref.mounted) return;
      if (enabled == false) {
        await WidgetEntryService.clear();
      } else if (authLoading || !hasActiveCompany) {
        // A startup placeholder must not replace the last usable keypad context.
        return;
      } else if (!isExpense) {
        await WidgetEntryService.clear();
      } else if (enabled == true &&
          wallets != null &&
          categories != null &&
          defaultWallet?.isLoading == false) {
        await WidgetEntryService.publish(
          company: company,
          userId: userId,
          role: role,
          wallets: wallets,
          categories: categories,
          defaultWalletId: defaultWallet?.value,
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
  final companies = ref.watch(userCompaniesProvider);
  if (!companies.any((candidate) => candidate.id == company.id)) return;

  if (company.mode == CompanyMode.expenseTracker) {
    // Widget spending is independent of the transaction screen's search and filters.
    final summaryAsync = ref.watch(_widgetMonthSummaryProvider);
    final categoriesAsync = ref.watch(categoriesProvider);
    final budget = ref.watch(_widgetOverallBudgetProvider).asData;
    final transactionsAsync = ref.watch(_widgetTodayExpensesProvider);

    final summary = summaryAsync.asData?.value;
    final transactions = transactionsAsync.asData?.value;
    final categories = categoriesAsync.asData?.value;
    if (summary == null ||
        transactions == null ||
        budget == null ||
        categories == null)
      return;

    final pendingUpdate = Timer(const Duration(milliseconds: 150), () {
      syncExpenseWidgetData(
        company: company,
        summary: summary,
        categories: categories,
        overallBudget: budget.value,
        transactions: transactions,
      );
    });
    ref.onDispose(pendingUpdate.cancel);
    return;
  }

  final summaryAsync = ref.watch(businessSummaryProvider);
  summaryAsync.whenData((summary) {
    Future.microtask(() {
      if (!ref.mounted) return;
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
        final budget = company.isModuleEnabled(AppModule.budgets)
            ? await budgetRepo.getAllCategoriesBudget(month: now)
            : null;
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

        if (!ref.mounted || ref.read(activeCompanyProvider).id != company.id)
          return;
        await syncExpenseWidgetData(
          company: company,
          summary: summary,
          categories: categories,
          overallBudget: budget,
          transactions: transactions,
        );
        return;
      }
      final repo = ref.read(ledgerRepositoryProvider);
      final summary = await repo.getBusinessSummary();
      if (!ref.mounted || ref.read(activeCompanyProvider).id != company.id)
        return;
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
