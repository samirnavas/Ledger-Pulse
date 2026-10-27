import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_pulse/core/network/sync_engine.dart';
import 'package:ledger_pulse/data/accounting/voucher_posting_engine.dart';
import 'package:ledger_pulse/data/models/sync_model.dart';
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
    await db.into(db.companies).insert(
          CompaniesCompanion.insert(
            id: enabledCompany.id,
            name: enabledCompany.name,
            legalName: enabledCompany.legalName,
            mode: Value(enabledCompany.mode.name),
            enabledModulesJson: const Value('["vouchers","budgets","recurring"]'),
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
      ],
      child: MaterialApp(
        home: child,
      ),
    );
  }

  group('Budgets - Period Math & Rollover', () {
    test('Calculates period boundaries accurately for weekly, monthly, yearly', () {
      final date = DateTime(2026, 10, 15); // Thursday

      final weeklyBounds =
          DriftBudgetRepository.getPeriodBounds(BudgetPeriodType.weekly, date);
      expect(weeklyBounds.start.weekday, DateTime.monday);
      expect(weeklyBounds.end.weekday, DateTime.sunday);

      final monthlyBounds =
          DriftBudgetRepository.getPeriodBounds(BudgetPeriodType.monthly, date);
      expect(monthlyBounds.start, DateTime(2026, 10, 1));
      expect(monthlyBounds.end, DateTime(2026, 10, 31, 23, 59, 59, 999));

      final yearlyBounds =
          DriftBudgetRepository.getPeriodBounds(BudgetPeriodType.yearly, date);
      expect(yearlyBounds.start, DateTime(2026, 1, 1));
      expect(yearlyBounds.end, DateTime(2026, 12, 31, 23, 59, 59, 999));
    });

    test('Aggregates sub-category expenses into parent category budget', () async {
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
    });

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
    testWidgets('Shows 80% warning banner and 100% exceeded banner', (tester) async {
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
      );

      // Groceries: 10,000 budget, spent 8,500 (85% -> warning)
      await budgetRepo.createBudget(
        categoryId: catWarning.id,
        amountInCents: 1000000,
        period: BudgetPeriodType.monthly,
      );
      await expenseRepo.addExpense(
        walletAccountId: wallet.id,
        categoryAccountId: catWarning.id,
        amountInCents: 850000,
        date: now,
      );

      // Shopping: 5,000 budget, spent 6,000 (120% -> exceeded)
      await budgetRepo.createBudget(
        categoryId: catExceeded.id,
        amountInCents: 500000,
        period: BudgetPeriodType.monthly,
      );
      await expenseRepo.addExpense(
        walletAccountId: wallet.id,
        categoryAccountId: catExceeded.id,
        amountInCents: 600000,
        date: now,
      );

      await tester.pumpWidget(buildTestScope(child: const BudgetsScreen()));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('budget_warning_banner')), findsOneWidget);
      expect(find.byKey(const Key('budget_exceeded_banner')), findsOneWidget);
      expect(find.byKey(const Key('overall_budget_card')), findsOneWidget);
    });
  });

  group('Recurring Transactions - Idempotency & Catch-Up', () {
    test('generateDue is idempotent: multiple executions never duplicate vouchers', () async {
      final wallet = await expenseRepo.createWallet(
        name: 'Checking Wallet',
        type: AccountType.asset,
      );
      final cat = await expenseRepo.createCategory(
        name: 'Rent',
        type: AccountType.expense,
      );

      // Active rule due today
      await recurringService.createRule(
        template: RecurringTemplate(
          type: VoucherType.expense,
          amountInCents: 1500000, // 15,000 INR
          walletAccountId: wallet.id,
          categoryAccountId: cat.id,
          narration: 'Office Rent',
        ),
        interval: RecurringIntervalType.monthly,
        nextRunDate: DateTime(2026, 10, 1),
      );

      // First run: should post 1 transaction and advance nextRunDate to 2026-11-01
      final generated1 = await recurringService.generateDue(DateTime(2026, 10, 15));
      expect(generated1, 1);

      final vouchersAfterFirst = await expenseRepo.getTransactions();
      expect(vouchersAfterFirst.length, 1);
      expect(vouchersAfterFirst.first.narration, 'Office Rent');

      // Second run immediately after: nothing is due, 0 generated!
      final generated2 = await recurringService.generateDue(DateTime(2026, 10, 15));
      expect(generated2, 0);

      final vouchersAfterSecond = await expenseRepo.getTransactions();
      expect(vouchersAfterSecond.length, 1); // No duplicates!
    });

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
    testWidgets('BudgetsScreen shows disabled view when budgets module is off', (tester) async {
      final disabledCompany = enabledCompany.copyWith(
        enabledModules: const {AppModule.vouchers, AppModule.recurring},
      );

      await tester.pumpWidget(buildTestScope(
        child: const BudgetsScreen(),
        companyOverride: disabledCompany,
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('budgets_module_disabled')), findsOneWidget);
    });

    testWidgets('RecurringScreen shows disabled view when recurring module is off', (tester) async {
      final disabledCompany = enabledCompany.copyWith(
        enabledModules: const {AppModule.vouchers, AppModule.budgets},
      );

      await tester.pumpWidget(buildTestScope(
        child: const RecurringScreen(),
        companyOverride: disabledCompany,
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('recurring_module_disabled')), findsOneWidget);
    });

    testWidgets('QuickAddTransactionSheet shows repeat option only when recurring is on', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // 1. With recurring module ON
      await tester.pumpWidget(buildTestScope(
        child: const Scaffold(
          body: QuickAddTransactionSheet(),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('quick_add_repeat_switch')), findsOneWidget);

      // 2. With recurring module OFF
      final disabledCompany = enabledCompany.copyWith(
        enabledModules: const {AppModule.vouchers, AppModule.budgets},
      );

      await tester.pumpWidget(buildTestScope(
        child: const Scaffold(
          body: QuickAddTransactionSheet(),
        ),
        companyOverride: disabledCompany,
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('quick_add_repeat_switch')), findsNothing);
    });
  });
}

class _FakeSyncEngineForTest extends SyncEngine {
  _FakeSyncEngineForTest({required super.db});

  @override
  Future<SyncResult> pushQueue({String? companyId}) async {
    return SyncResult(
      success: true,
      itemsPushed: 0,
      timestamp: DateTime.now(),
    );
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
