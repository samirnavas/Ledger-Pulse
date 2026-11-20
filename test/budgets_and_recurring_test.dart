import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_pulse/core/network/sync_engine.dart';
import 'package:ledger_pulse/data/accounting/voucher_posting_engine.dart';
import 'package:ledger_pulse/data/local/audit_service.dart';
import 'package:ledger_pulse/data/local/database.dart';
import 'package:ledger_pulse/data/local/drift_budget_repository.dart';
import 'package:ledger_pulse/data/local/drift_expense_repository.dart';
import 'package:ledger_pulse/data/local/drift_voucher_repository.dart';
import 'package:ledger_pulse/data/models/account_model.dart';
import 'package:ledger_pulse/data/models/budget_model.dart';
import 'package:ledger_pulse/data/models/company_model.dart';
import 'package:ledger_pulse/data/models/recurring_rule_model.dart';
import 'package:ledger_pulse/data/models/user_profile_model.dart';
import 'package:ledger_pulse/data/models/voucher_model.dart';
import 'package:ledger_pulse/data/services/recurring_service.dart';
import 'package:ledger_pulse/presentation/expense/budgets_screen.dart';
import 'package:ledger_pulse/presentation/expense/quick_add_transaction_sheet.dart';
import 'package:ledger_pulse/presentation/expense/recurring_screen.dart';
import 'package:ledger_pulse/presentation/providers/budget_providers.dart';
import 'package:ledger_pulse/presentation/providers/company_providers.dart';
import 'package:ledger_pulse/presentation/providers/database_providers.dart';
import 'package:ledger_pulse/presentation/providers/expense_providers.dart';
import 'package:ledger_pulse/presentation/providers/profile_provider.dart';
import 'package:ledger_pulse/presentation/providers/recurring_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late AuditService auditService;
  late VoucherPostingEngine postingEngine;
  late DriftVoucherRepository voucherRepo;
  late DriftExpenseRepository expenseRepo;
  late DriftBudgetRepository budgetRepo;
  late RecurringService recurringService;

  const testCompanyId = 'cmp_budget_test';
  final now = DateTime(2026, 10, 15, 12, 0);

  final enabledCompany = Company(
    id: testCompanyId,
    name: 'Pulse Expense Co',
    legalName: 'Pulse Expense LLC',
    currencyCode: 'INR',
    mode: CompanyMode.expenseTracker,
    enabledModules: const {
      AppModule.vouchers,
      AppModule.budgets,
      AppModule.recurring,
    },
    createdAt: now,
    updatedAt: now,
  );

  final testProfile = UserProfile(
    id: 'usr_budget_tester',
    name: 'Budget Tester',
    phoneNumber: '+91 99999 11111',
    email: 'budget@example.com',
    companies: [enabledCompany],
    activeCompanyId: enabledCompany.id,
  );

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    auditService = AuditService(db);
    postingEngine = VoucherPostingEngine(db, auditService);
    voucherRepo = DriftVoucherRepository(
      db: db,
      auditService: auditService,
      postingEngine: postingEngine,
      currentCompanyId: testCompanyId,
    );
    expenseRepo = DriftExpenseRepository(
      db: db,
      voucherRepo: voucherRepo,
      postingEngine: postingEngine,
      auditService: auditService,
      currentCompanyId: testCompanyId,
      company: enabledCompany,
    );
    budgetRepo = DriftBudgetRepository(
      db: db,
      auditService: auditService,
      currentCompanyId: testCompanyId,
      company: enabledCompany,
    );
    recurringService = RecurringService(
      db: db,
      expenseRepo: expenseRepo,
      auditService: auditService,
      currentCompanyId: testCompanyId,
      company: enabledCompany,
    );

    // Seed company in DB
    await db
        .into(db.companies)
        .insert(
          CompaniesCompanion.insert(
            id: enabledCompany.id,
            name: enabledCompany.name,
            legalName: enabledCompany.legalName,
            mode: Value(enabledCompany.mode.name),
            enabledModulesJson: const Value(
              '["vouchers","budgets","recurring"]',
            ),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );

    // Seed chart of accounts with cash & bank
    await postingEngine.seedAccountsFor(
      enabledCompany,
      initialWalletBalancesInCents: {
        ExpenseTrackerDefaults.walletCashId: 500000,
        ExpenseTrackerDefaults.walletBankId: 500000,
      },
    );
  });

  tearDown(() async {
    budgetRepo.dispose();
    recurringService.dispose();
    expenseRepo.dispose();
    await db.close();
  });

  Widget buildTestScope({
    required Widget child,
    Company? companyOverride,
    DateTime? selectedMonth,
  }) {
    final company = companyOverride ?? enabledCompany;
    return ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        syncEngineProvider.overrideWithValue(_FakeSyncEngineForTest(db: db)),
        activeCompanyProvider.overrideWithValue(company),
        userProfileProvider.overrideWith(
          () => _TestProfileNotifier(
            testProfile.copyWith(
              companies: [company],
              activeCompanyId: company.id,
            ),
          ),
        ),
        expenseRepositoryProvider.overrideWithValue(expenseRepo),
        budgetRepositoryProvider.overrideWithValue(budgetRepo),
        recurringServiceProvider.overrideWithValue(recurringService),
        selectedMonthProvider.overrideWith(
          () => _TestMonthNotifier(selectedMonth ?? DateTime(now.year, now.month)),
        ),
      ],
      child: MaterialApp(home: child),
    );
  }

  group('Budgets - Period Math & Rollover', () {
    test(
      'Home and budget providers use the current week and track database changes',
      () async {
        final today = DateTime.now();
        final wallet = await expenseRepo.createWallet(
          name: 'Weekly cash',
          type: AccountType.asset,
        );
        final category = await expenseRepo.createCategory(
          name: 'Weekly food',
          type: AccountType.expense,
        );
        await budgetRepo.createBudget(
          categoryId: 'all',
          amountInCents: 70000,
          period: BudgetPeriodType.weekly,
          startDate: today,
        );
        final txn = await expenseRepo.addExpense(
          walletAccountId: wallet.id,
          categoryAccountId: category.id,
          amountInCents: 2500,
          date: today,
        );
        final container = ProviderContainer(
          overrides: [
            activeCompanyProvider.overrideWithValue(enabledCompany),
            budgetRepositoryProvider.overrideWithValue(budgetRepo),
            expenseRepositoryProvider.overrideWithValue(expenseRepo),
            selectedMonthProvider.overrideWith(
              () => _TestMonthNotifier(DateTime(today.year, today.month)),
            ),
          ],
        );
        addTearDown(container.dispose);
        final bounds = DriftBudgetRepository.getPeriodBounds(
          BudgetPeriodType.weekly,
          today,
        );
        final home = await container.read(allCategoriesBudgetProvider.future);
        expect(home!.periodStartDate, bounds.start);
        expect(home.spentInCents, 2500);
        expect(home.percentUsed, closeTo(2500 / 70000 * 100, 0.001));
        expect(
          (await container.read(
            budgetsProgressListProvider.future,
          )).single.spentInCents,
          2500,
        );
        expect(
          (await container.read(
            overallMonthlyBudgetProvider.future,
          )).totalSpentInCents,
          2500,
        );
        // Sync writes directly to Drift, without expense repository notifications.
        final changed = budgetRepo.repositoryUpdatesStream.first;
        await (db.update(
          db.expenseTransactions,
        )..where((t) => t.id.equals(txn.id))).write(
          const ExpenseTransactionsCompanion(amountInCents: Value(5000)),
        );
        await changed;
        expect(
          (await container.read(
            allCategoriesBudgetProvider.future,
          ))!.spentInCents,
          5000,
        );
        expect(
          (await container.read(
            budgetsProgressListProvider.future,
          )).single.spentInCents,
          5000,
        );
        expect(
          (await container.read(
            overallMonthlyBudgetProvider.future,
          )).totalSpentInCents,
          5000,
        );
      },
    );

    test('Overall budgets include uncategorized expenses', () async {
      final today = DateTime.now();
      final wallet = await expenseRepo.createWallet(
        name: 'Uncategorized cash',
        type: AccountType.asset,
      );
      final budget = await budgetRepo.createBudget(
        categoryId: 'all',
        amountInCents: 10000,
      );
      await db
          .into(db.expenseTransactions)
          .insert(
            ExpenseTransactionsCompanion.insert(
              id: 'uncategorized_budget_expense',
              profileId: testCompanyId,
              transactionType: 'expense',
              amountInCents: 1200,
              walletId: wallet.id,
              transactionDate: today,
            ),
          );
      expect(
        (await budgetRepo.calculateProgress(
          budget,
          asOfDate: today,
        )).spentInCents,
        1200,
      );
    });

    testWidgets('Budget progress refreshes after an expense changes', (
      tester,
    ) async {
      final wallet = await expenseRepo.createWallet(
        name: 'Budget refresh cash',
        type: AccountType.asset,
        openingBalanceInCents: 50000,
      );
      final category = await expenseRepo.createCategory(
        name: 'Budget refresh food',
        type: AccountType.expense,
      );
      await budgetRepo.createBudget(
        categoryId: category.id,
        amountInCents: 10000,
      );
      await tester.pumpWidget(buildTestScope(child: const BudgetsScreen()));
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(BudgetsScreen)),
      );
      expect(
        (await container.read(
          budgetsProgressListProvider.future,
        )).single.spentInCents,
        0,
      );
      await expenseRepo.addExpense(
        walletAccountId: wallet.id,
        categoryAccountId: category.id,
        amountInCents: 2500,
        date: now,
      );
      await tester.pumpAndSettle();
      expect(
        (await container.read(
          budgetsProgressListProvider.future,
        )).single.spentInCents,
        2500,
      );
      expect(
        (await container.read(
          overallMonthlyBudgetProvider.future,
        )).totalSpentInCents,
        2500,
      );
    });

    test('Budget edits and rollover survive reloading', () async {
      final category = await expenseRepo.createCategory(
        name: 'Budget edit category',
        type: AccountType.expense,
      );
      final created = await budgetRepo.createBudget(
        categoryId: 'all',
        amountInCents: 10000,
        rolloverEnabled: true,
      );
      expect(
        (await budgetRepo.getBudgetById(created.id)).rolloverEnabled,
        isTrue,
      );
      await budgetRepo.updateBudget(
        budget: created.copyWith(
          categoryId: category.id,
          allocatedInCents: 20000,
          rolloverEnabled: false,
        ),
      );
      final loaded = await budgetRepo.getBudgetById(created.id);
      expect(loaded.categoryId, category.id);
      expect(loaded.allocatedInCents, 20000);
      expect(loaded.rolloverEnabled, isFalse);
      await expectLater(
        budgetRepo.updateBudget(id: created.id, amountInCents: 0),
        throwsArgumentError,
      );
    });

    test(
      'Calculates period boundaries accurately for weekly, monthly, yearly',
      () {
        final date = DateTime(2026, 10, 15); // Thursday

        final weeklyBounds = DriftBudgetRepository.getPeriodBounds(
          BudgetPeriodType.weekly,
          date,
        );
        expect(weeklyBounds.start.weekday, DateTime.monday);
        expect(weeklyBounds.end.weekday, DateTime.sunday);

        final monthlyBounds = DriftBudgetRepository.getPeriodBounds(
          BudgetPeriodType.monthly,
          date,
        );
        expect(monthlyBounds.start, DateTime(2026, 10, 1));
        expect(monthlyBounds.end, DateTime(2026, 10, 31, 23, 59, 59, 999));

        final yearlyBounds = DriftBudgetRepository.getPeriodBounds(
          BudgetPeriodType.yearly,
          date,
        );
        expect(yearlyBounds.start, DateTime(2026, 1, 1));
        expect(yearlyBounds.end, DateTime(2026, 12, 31, 23, 59, 59, 999));
      },
    );

    test(
      'Aggregates sub-category expenses into parent category budget',
      () async {
        // 1. Create wallet
        final wallet = await expenseRepo.createWallet(
          name: 'Main Cash',
          type: AccountType.asset,
          openingBalanceInCents: 500000,
        );

        // 2. Create parent category (Food) and child category (Restaurants)
        final parentCat = await expenseRepo.createCategory(
          name: 'Food',
          type: AccountType.expense,
        );
        final subCat = await expenseRepo.createCategory(
          name: 'Restaurants',
          type: AccountType.expense,
          parentAccountId: parentCat.id,
        );

        // 3. Set monthly budget on parent Food category: 10,000 INR (1,000,000 cents)
        final budget = await budgetRepo.createBudget(
          categoryId: parentCat.id,
          amountInCents: 1000000,
          period: BudgetPeriodType.monthly,
        );

        // 4. Post expense to sub-category (Restaurants)
        await expenseRepo.addExpense(
          walletAccountId: wallet.id,
          categoryAccountId: subCat.id,
          amountInCents: 400000, // 4,000 INR
          date: DateTime(2026, 10, 10),
        );

        // 5. Compute progress for parent budget
        final progress = await budgetRepo.calculateProgress(
          budget,
          asOfDate: DateTime(2026, 10, 15),
        );

        expect(progress.spentInCents, 400000);
        expect(progress.remainingInCents, 600000);
        expect(progress.percentUsed, 40.0);
        expect(progress.isWarning, isFalse);
        expect(progress.isExceeded, isFalse);
      },
    );

    test('Calculates rollover correctly from previous period', () async {
      final wallet = await expenseRepo.createWallet(
        name: 'Bank Account',
        type: AccountType.asset,
        openingBalanceInCents: 500000,
      );

      final cat = await expenseRepo.createCategory(
        name: 'Utilities',
        type: AccountType.expense,
      );

      // Budget with rollover enabled: 10,000 INR allocated per month
      final budget = await budgetRepo.createBudget(
        categoryId: cat.id,
        amountInCents: 1000000,
        period: BudgetPeriodType.monthly,
        startDate: DateTime(2026, 9, 1),
        rolloverEnabled: true,
      );

      // In September 2026 (previous month), spent only 3,000 INR
      await expenseRepo.addExpense(
        walletAccountId: wallet.id,
        categoryAccountId: cat.id,
        amountInCents: 300000,
        date: DateTime(2026, 9, 15),
      );

      // In October 2026, check progress: 7,000 INR unspent should roll over!
      final progress = await budgetRepo.calculateProgress(
        budget,
        asOfDate: DateTime(2026, 10, 15),
      );

      expect(progress.rolloverInCents, 700000);
      expect(progress.effectiveAllocatedInCents, 1700000); // 10,000 + 7,000
      expect(progress.spentInCents, 0);
      expect(progress.remainingInCents, 1700000);
    });
  });

  group('Budgets - Threshold Banners UI', () {
    testWidgets('Does not show 80% warning or 100% exceeded banners', (
      tester,
    ) async {
      final today = DateTime.now();
      final wallet = await expenseRepo.createWallet(
        name: 'Cash',
        type: AccountType.asset,
      );

      final catWarning = await expenseRepo.createCategory(
        name: 'Groceries',
        type: AccountType.expense,
      );
      final catExceeded = await expenseRepo.createCategory(
        name: 'Shopping',
        type: AccountType.expense,
        parentAccountId: catWarning.id,
      );

      // Groceries: 10,000 budget, spent 8,500 (85% -> warning)
      await budgetRepo.createBudget(
        categoryId: catWarning.id,
        amountInCents: 1000000,
        period: BudgetPeriodType.monthly,
        startDate: today,
      );
      await expenseRepo.addExpense(
        walletAccountId: wallet.id,
        categoryAccountId: catWarning.id,
        amountInCents: 850000,
        date: today,
      );

      // Shopping: 5,000 budget, spent 6,000 (120% -> exceeded)
      await budgetRepo.createBudget(
        categoryId: catExceeded.id,
        amountInCents: 500000,
        period: BudgetPeriodType.monthly,
        startDate: today,
      );
      await expenseRepo.addExpense(
        walletAccountId: wallet.id,
        categoryAccountId: catExceeded.id,
        amountInCents: 600000,
        date: today,
      );

      await budgetRepo.createBudget(
        categoryId: 'all',
        amountInCents: 1000000,
        period: BudgetPeriodType.weekly,
        startDate: today,
      );
      await budgetRepo.createBudget(
        categoryId: catExceeded.id,
        amountInCents: 200000,
        period: BudgetPeriodType.weekly,
        startDate: today,
      );
      await budgetRepo.createBudget(
        categoryId: catExceeded.id,
        amountInCents: 3000000,
        period: BudgetPeriodType.yearly,
        startDate: today,
      );

      await tester.pumpWidget(
        buildTestScope(child: const BudgetsScreen(), selectedMonth: today),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('budget_warning_banner')), findsNothing);
      expect(find.byKey(const Key('budget_exceeded_banner')), findsNothing);
      final card = find.byKey(const Key('overall_budget_card_weekly'));
      expect(card, findsOneWidget);
      expect(
        find.descendant(of: card, matching: find.text('Overall Weekly Budget')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.text('145.0%')),
        findsOneWidget,
      );
      final monthly = find.byKey(const Key('overall_budget_card_monthly'));
      expect(
        find.descendant(
          of: monthly,
          matching: find.text('Includes Groceries, Shopping'),
        ),
        findsOneWidget,
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(BudgetsScreen)),
      );
      final summaries = await container.read(budgetSummariesByPeriodProvider.future);
      expect(summaries[0].totalAllocatedInCents, 1000000);
      expect(summaries[1].totalAllocatedInCents, 1500000);
      expect(summaries[1].totalSpentInCents, 1450000);
      expect(summaries[2].items.single.budget.periodType, BudgetPeriodType.yearly);
      expect(summaries[2].totalAllocatedInCents, 3000000);
      expect(summaries[2].totalSpentInCents, 600000);
    });
  });

  group('Recurring Transactions - Idempotency & Catch-Up', () {
    test(
      'Failed occurrences remain due and can be retried after repair',
      () async {
        final category = await expenseRepo.createCategory(
          name: 'Retry fee',
          type: AccountType.expense,
        );
        final due = DateTime(2026, 10, 1);
        final rule = await recurringService.createRule(
          template: RecurringTemplate(
            type: VoucherType.expense,
            amountInCents: 1000,
            walletAccountId: 'missing_wallet',
            categoryAccountId: category.id,
          ),
          nextRunDate: due,
        );
        await expectLater(recurringService.generateDue(due), throwsStateError);
        expect((await recurringService.getRuleById(rule.id)).nextRunDate, due);
        expect(await expenseRepo.getTransactions(), isEmpty);
        final wallet = await expenseRepo.createWallet(
          name: 'Repaired wallet',
          type: AccountType.asset,
        );
        await recurringService.updateRule(
          id: rule.id,
          template: RecurringTemplate(
            type: VoucherType.expense,
            amountInCents: 1000,
            walletAccountId: wallet.id,
            categoryAccountId: category.id,
          ),
        );
        expect(await recurringService.generateDue(due), 1);
        expect(await recurringService.generateDue(due), 0);
      },
    );

    test(
      'Concurrent runs post each occurrence once and finish ended rules',
      () async {
        final wallet = await expenseRepo.createWallet(
          name: 'Concurrent wallet',
          type: AccountType.asset,
        );
        final category = await expenseRepo.createCategory(
          name: 'Concurrent fee',
          type: AccountType.expense,
        );
        final due = DateTime(2026, 10, 1);
        final rule = await recurringService.createRule(
          template: RecurringTemplate(
            type: VoucherType.expense,
            amountInCents: 1000,
            walletAccountId: wallet.id,
            categoryAccountId: category.id,
          ),
          nextRunDate: due,
          endDate: due,
        );
        final counts = await Future.wait([
          recurringService.generateDue(due),
          recurringService.generateDue(due),
        ]);
        expect(counts.reduce((a, b) => a + b), 1);
        expect((await expenseRepo.getTransactions()).length, 1);
        expect((await recurringService.getRuleById(rule.id)).isActive, isFalse);
      },
    );

    test(
      'Rejects incomplete recurring templates and invalid intervals',
      () async {
        await expectLater(
          recurringService.createRule(
            template: const RecurringTemplate(
              type: VoucherType.expense,
              amountInCents: 1000,
              walletAccountId: 'wallet',
            ),
            nextRunDate: now,
          ),
          throwsArgumentError,
        );
        await expectLater(
          recurringService.createRule(
            template: const RecurringTemplate(
              type: VoucherType.transfer,
              amountInCents: 1000,
              walletAccountId: 'wallet',
              toWalletAccountId: 'other',
            ),
            intervalCount: 0,
            nextRunDate: now,
          ),
          throwsArgumentError,
        );
      },
    );

    test(
      'generateDue waits for the scheduled time and never duplicates vouchers',
      () async {
        final wallet = await expenseRepo.createWallet(
          name: 'Checking Wallet',
          type: AccountType.asset,
        );
        final cat = await expenseRepo.createCategory(
          name: 'Rent',
          type: AccountType.expense,
        );

        final scheduled = DateTime(2026, 10, 1, 14, 30);
        final rule = await recurringService.createRule(
          template: RecurringTemplate(
            type: VoucherType.expense,
            amountInCents: 1500000, // 15,000 INR
            walletAccountId: wallet.id,
            categoryAccountId: cat.id,
            narration: 'Office Rent',
          ),
          interval: RecurringIntervalType.monthly,
          nextRunDate: scheduled,
        );

        expect(
          await recurringService.generateDue(
            scheduled.subtract(const Duration(minutes: 1)),
          ),
          0,
        );
        final generated1 = await recurringService.generateDue(scheduled);
        expect(generated1, 1);
        expect(
          (await recurringService.getRuleById(rule.id)).nextRunDate,
          DateTime(2026, 11, 1, 14, 30),
        );

        final vouchersAfterFirst = await expenseRepo.getTransactions();
        expect(vouchersAfterFirst.length, 1);
        expect(vouchersAfterFirst.first.narration, 'Office Rent');

        // Second run immediately after: nothing is due, 0 generated!
        final generated2 = await recurringService.generateDue(
          DateTime(2026, 10, 15),
        );
        expect(generated2, 0);

        final vouchersAfterSecond = await expenseRepo.getTransactions();
        expect(vouchersAfterSecond.length, 1); // No duplicates!
      },
    );

    test('generateDue caps catch-up iterations at maxIterations', () async {
      final wallet = await expenseRepo.createWallet(
        name: 'Daily Wallet',
        type: AccountType.asset,
      );
      final cat = await expenseRepo.createCategory(
        name: 'Daily Fee',
        type: AccountType.expense,
      );

      // Rule created 500 days ago with Daily interval
      final overdueStart = DateTime(2025, 1, 1);
      await recurringService.createRule(
        template: RecurringTemplate(
          type: VoucherType.expense,
          amountInCents: 1000,
          walletAccountId: wallet.id,
          categoryAccountId: cat.id,
        ),
        interval: RecurringIntervalType.daily,
        nextRunDate: overdueStart,
      );

      // Run with custom cap of 50 iterations
      final count = await recurringService.generateDue(
        DateTime(2026, 10, 15),
        maxIterations: 50,
      );

      expect(count, 50); // Capped at exactly 50 iterations!
    });
  });

  group('Disabled Module Behavior', () {
    testWidgets(
      'BudgetsScreen shows disabled view when budgets module is off',
      (tester) async {
        final disabledCompany = enabledCompany.copyWith(
          enabledModules: const {AppModule.vouchers, AppModule.recurring},
        );

        await tester.pumpWidget(
          buildTestScope(
            child: const BudgetsScreen(),
            companyOverride: disabledCompany,
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('budgets_module_disabled')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'RecurringScreen shows disabled view when recurring module is off',
      (tester) async {
        final disabledCompany = enabledCompany.copyWith(
          enabledModules: const {AppModule.vouchers, AppModule.budgets},
        );

        await tester.pumpWidget(
          buildTestScope(
            child: const RecurringScreen(),
            companyOverride: disabledCompany,
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('recurring_module_disabled')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'QuickAddTransactionSheet shows repeat option only when recurring is on',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        // 1. With recurring module ON
        await tester.pumpWidget(
          buildTestScope(
            child: const Scaffold(body: QuickAddTransactionSheet()),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('quick_add_repeat_switch')),
          findsOneWidget,
        );

        // 2. With recurring module OFF
        final disabledCompany = enabledCompany.copyWith(
          enabledModules: const {AppModule.vouchers, AppModule.budgets},
        );

        await tester.pumpWidget(
          buildTestScope(
            child: const Scaffold(body: QuickAddTransactionSheet()),
            companyOverride: disabledCompany,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('quick_add_repeat_switch')), findsNothing);
      },
    );
  });
}

class _FakeSyncEngineForTest extends SyncEngine {
  _FakeSyncEngineForTest({required super.db});

  @override
  Future<SyncResult> pushQueue({String? companyId}) async {
    return SyncResult(success: true, itemsPushed: 0, timestamp: DateTime.now());
  }
}

class _TestProfileNotifier extends UserProfileNotifier {
  final UserProfile _initial;
  _TestProfileNotifier(this._initial);

  @override
  UserProfile build() => _initial;

  @override
  void updateProfile(UserProfile updated) {
    state = updated;
  }
}

class _TestMonthNotifier extends SelectedMonthNotifier {
  final DateTime _initial;
  _TestMonthNotifier(this._initial);

  @override
  DateTime build() => _initial;
}
