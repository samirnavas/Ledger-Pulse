import 'package:drift/drift.dart' hide Column;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_pulse/core/modules/module_catalog.dart';
import 'package:ledger_pulse/data/accounting/voucher_posting_engine.dart';
import 'package:ledger_pulse/data/local/audit_service.dart';
import 'package:ledger_pulse/data/local/database.dart';
import 'package:ledger_pulse/data/local/drift_budget_repository.dart';
import 'package:ledger_pulse/data/local/drift_expense_repository.dart';
import 'package:ledger_pulse/data/local/drift_ledger_repository.dart';
import 'package:ledger_pulse/data/local/drift_voucher_repository.dart';
import 'package:ledger_pulse/data/models/company_model.dart';
import 'package:ledger_pulse/data/models/user_profile_model.dart';
import 'package:ledger_pulse/data/reporting/financial_statement_engine.dart';
import 'package:ledger_pulse/data/services/recurring_service.dart';
import 'package:ledger_pulse/core/network/sync_engine.dart';
import 'package:ledger_pulse/data/models/sync_model.dart';
import 'package:ledger_pulse/presentation/home/dashboard_screen.dart';
import 'package:ledger_pulse/presentation/home/home_shell.dart';
import 'package:ledger_pulse/presentation/providers/company_providers.dart';
import 'package:ledger_pulse/presentation/providers/ledger_providers.dart';
import 'package:ledger_pulse/presentation/providers/profile_provider.dart';
import 'package:ledger_pulse/presentation/settings/settings_screen.dart';

class _TestUserProfileNotifier extends UserProfileNotifier {
  final UserProfile _initial;
  _TestUserProfileNotifier(this._initial);

  @override
  UserProfile build() => _initial;

  @override
  void updateProfile(UserProfile updated) {
    state = updated;
  }
}

class _FakeSyncEngine extends SyncEngine {
  _FakeSyncEngine({required super.db});

  @override
  Future<SyncResult> syncAll({String? companyId}) async {
    return SyncResult(
      success: true,
      itemsPushed: 0,
      itemsPulled: 0,
      timestamp: DateTime.now(),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Prompt 13 – Upgrade from expense tracker to business ledger', () {
    late AppDatabase db;
    late AuditService auditService;
    late VoucherPostingEngine postingEngine;
    late DriftLedgerRepository repo;
    late DriftExpenseRepository expenseRepo;
    late DriftVoucherRepository voucherRepo;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      auditService = AuditService(db);
      postingEngine = VoucherPostingEngine(db, auditService);
      repo = DriftLedgerRepository(
        db: db,
        postingEngine: postingEngine,
      );
      voucherRepo = DriftVoucherRepository(
        db: db,
        postingEngine: postingEngine,
        auditService: auditService,
      );
      expenseRepo = DriftExpenseRepository(
        db: db,
        postingEngine: postingEngine,
        voucherRepo: voucherRepo,
        auditService: auditService,
      );
    });

    tearDown(() async {
      await db.close();
    });

    test('account balances and journal totals identical before and after; no duplicates; idempotent if run twice', () async {
      const companyId = 'cmp_upgrade_test';

      final expenseCompany = Company(
        id: companyId,
        name: 'Personal Expenses',
        legalName: 'Personal Expenses',
        currencyCode: 'INR',
        mode: CompanyMode.expenseTracker,
        enabledModules: {AppModule.budgets, AppModule.recurring},
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      // 1. Create company with initial wallet balances
      await repo.createCompany(
        expenseCompany,
        initialWalletBalancesInCents: {
          ExpenseTrackerDefaults.walletCashId: 1000000, // ₹10,000
          ExpenseTrackerDefaults.walletBankId: 5000000, // ₹50,000
        },
      );

      expenseRepo.setContext(companyId: companyId);

      // 2. Add expense vouchers in expense mode
      final foodAccountId = '${companyId}_${ExpenseTrackerDefaults.foodDiningId}';
      final cashAccountId = '${companyId}_${ExpenseTrackerDefaults.walletCashId}';
      final groceriesAccountId = '${companyId}_${ExpenseTrackerDefaults.groceriesId}';
      final bankAccountId = '${companyId}_${ExpenseTrackerDefaults.walletBankId}';

      await expenseRepo.addExpense(
        categoryAccountId: foodAccountId,
        walletAccountId: cashAccountId,
        amountInCents: 150000, // ₹1,500
        narration: 'Team Dinner',
      );

      await expenseRepo.addExpense(
        categoryAccountId: groceriesAccountId,
        walletAccountId: bankAccountId,
        amountInCents: 350000, // ₹3,500
        narration: 'Monthly Groceries',
      );

      // 3. Capture exact state BEFORE upgrade
      final accountsBefore = await (db.select(db.accounts)
            ..where((t) => t.companyId.equals(companyId) & t.isDeleted.equals(false)))
          .get();
      final Map<String, int> balancesBefore = {
        for (final a in accountsBefore) a.id: a.currentBalanceInCents,
      };

      final journalsBefore = await (db.select(db.journals)
            ..where((t) => t.companyId.equals(companyId) & t.isDeleted.equals(false)))
          .get();
      final totalJournalAmountBefore = journalsBefore.fold<int>(
        0,
        (sum, j) => sum + j.totalAmountInCents,
      );

      final journalLinesBefore = await (db.select(db.journalLines)
            ..where((t) => t.companyId.equals(companyId) & t.isDeleted.equals(false)))
          .get();
      final totalDebitLinesBefore = journalLinesBefore.fold<int>(
        0,
        (sum, l) => sum + l.debitInCents,
      );
      final totalCreditLinesBefore = journalLinesBefore.fold<int>(
        0,
        (sum, l) => sum + l.creditInCents,
      );

      final vouchersBefore = await (db.select(db.vouchers)
            ..where((t) => t.companyId.equals(companyId)))
          .get();

      // 4. PERFORM UPGRADE TO BUSINESS LEDGER
      final upgradedCompany = await repo.upgradeToLedger(
        companyId,
        preset: ModulePresets.billingAndGst,
      );

      // Verify upgraded company mode and preset modules
      expect(upgradedCompany.mode, equals(CompanyMode.ledger));
      expect(
        upgradedCompany.enabledModules,
        equals(ModuleCatalog.defaultsFor(CompanyMode.ledger, preset: ModulePresets.billingAndGst)),
      );
      expect(upgradedCompany.enabledModules.contains(AppModule.parties), isTrue);
      expect(upgradedCompany.enabledModules.contains(AppModule.vouchers), isTrue);
      expect(upgradedCompany.enabledModules.contains(AppModule.gst), isTrue);
      expect(upgradedCompany.enabledModules.contains(AppModule.advancedReports), isTrue);
      expect(upgradedCompany.enabledModules.contains(AppModule.budgets), isFalse);
      expect(upgradedCompany.enabledModules.contains(AppModule.recurring), isFalse);

      // 5. Verify pre-existing accounts, balances, vouchers, and journals are completely untouched
      final accountsAfter = await (db.select(db.accounts)
            ..where((t) => t.companyId.equals(companyId) & t.isDeleted.equals(false)))
          .get();

      for (final accBefore in accountsBefore) {
        final accAfter = accountsAfter.firstWhere((a) => a.id == accBefore.id);
        expect(
          accAfter.currentBalanceInCents,
          equals(balancesBefore[accBefore.id]),
          reason: 'Balance for account ${accBefore.id} must be identical before and after',
        );
        expect(accAfter.name, equals(accBefore.name));
        expect(accAfter.type, equals(accBefore.type));
      }

      // Check journal totals identical before and after
      final journalsAfter = await (db.select(db.journals)
            ..where((t) => t.companyId.equals(companyId) & t.isDeleted.equals(false)))
          .get();
      final totalJournalAmountAfter = journalsAfter.fold<int>(
        0,
        (sum, j) => sum + j.totalAmountInCents,
      );
      expect(totalJournalAmountAfter, equals(totalJournalAmountBefore));
      expect(journalsAfter.length, equals(journalsBefore.length));

      final journalLinesAfter = await (db.select(db.journalLines)
            ..where((t) => t.companyId.equals(companyId) & t.isDeleted.equals(false)))
          .get();
      final totalDebitLinesAfter = journalLinesAfter.fold<int>(
        0,
        (sum, l) => sum + l.debitInCents,
      );
      final totalCreditLinesAfter = journalLinesAfter.fold<int>(
        0,
        (sum, l) => sum + l.creditInCents,
      );
      expect(totalDebitLinesAfter, equals(totalDebitLinesBefore));
      expect(totalCreditLinesAfter, equals(totalCreditLinesBefore));

      // Check vouchers count unchanged
      final vouchersAfter = await (db.select(db.vouchers)
            ..where((t) => t.companyId.equals(companyId)))
          .get();
      expect(vouchersAfter.length, equals(vouchersBefore.length));

      // 6. Verify only missing ledger accounts were seeded
      expect(accountsAfter.any((a) => a.id == '${companyId}_${DefaultAccounts.arId}'), isTrue);
      expect(accountsAfter.any((a) => a.id == '${companyId}_${DefaultAccounts.apId}'), isTrue);
      expect(accountsAfter.any((a) => a.id == '${companyId}_${DefaultAccounts.inventoryId}'), isTrue);
      expect(accountsAfter.any((a) => a.id == '${companyId}_${DefaultAccounts.salesId}'), isTrue);
      expect(accountsAfter.any((a) => a.id == '${companyId}_${DefaultAccounts.purchasesCogsId}'), isTrue);
      expect(accountsAfter.any((a) => a.id == '${companyId}_${DefaultAccounts.inputGstId}'), isTrue);
      expect(accountsAfter.any((a) => a.id == '${companyId}_${DefaultAccounts.outputGstId}'), isTrue);

      // Newly seeded accounts must have 0 initial balance
      final arAccount = accountsAfter.firstWhere((a) => a.id == '${companyId}_${DefaultAccounts.arId}');
      expect(arAccount.currentBalanceInCents, equals(0));
      final apAccount = accountsAfter.firstWhere((a) => a.id == '${companyId}_${DefaultAccounts.apId}');
      expect(apAccount.currentBalanceInCents, equals(0));

      // 7. Verify NO DUPLICATE accounts exist
      final accountIds = accountsAfter.map((a) => a.id).toList();
      expect(accountIds.toSet().length, equals(accountIds.length), reason: 'All account IDs must be unique');

      // 8. Verify audit and outbox records written
      final auditLogs = await (db.select(db.auditLogs)
            ..where((t) => t.companyId.equals(companyId) & t.action.equals('update')))
          .get();
      expect(auditLogs.any((l) => l.entityType == 'company'), isTrue);

      final outboxRecords = await (db.select(db.syncOutbox)
            ..where((t) => t.targetTable.equals('companies') & t.recordId.equals(companyId)))
          .get();
      expect(outboxRecords.isNotEmpty, isTrue);

      // 9. IDEMPOTENT IF RUN TWICE
      final accountsCountFirstRun = accountsAfter.length;
      final secondUpgrade = await repo.upgradeToLedger(
        companyId,
        preset: ModulePresets.billingAndGst,
      );

      expect(secondUpgrade.mode, equals(CompanyMode.ledger));

      final accountsAfterSecondRun = await (db.select(db.accounts)
            ..where((t) => t.companyId.equals(companyId) & t.isDeleted.equals(false)))
          .get();
      expect(
        accountsAfterSecondRun.length,
        equals(accountsCountFirstRun),
        reason: 'No duplicate accounts should be created when running upgrade twice',
      );

      final journalsAfterSecondRun = await (db.select(db.journals)
            ..where((t) => t.companyId.equals(companyId) & t.isDeleted.equals(false)))
          .get();
      final totalJournalAmountSecondRun = journalsAfterSecondRun.fold<int>(
        0,
        (sum, j) => sum + j.totalAmountInCents,
      );
      expect(totalJournalAmountSecondRun, equals(totalJournalAmountBefore));
    });

    test('existing expense vouchers appear in ledger reports through existing expense accounts', () async {
      const companyId = 'cmp_ledger_reports';

      final expenseCompany = Company(
        id: companyId,
        name: 'Retail Store',
        legalName: 'Retail Store Ltd',
        currencyCode: 'INR',
        mode: CompanyMode.expenseTracker,
        enabledModules: {AppModule.budgets, AppModule.recurring},
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await repo.createCompany(
        expenseCompany,
        initialWalletBalancesInCents: {
          ExpenseTrackerDefaults.walletCashId: 2000000, // ₹20,000 Cash
          ExpenseTrackerDefaults.walletBankId: 8000000, // ₹80,000 Bank
        },
      );

      expenseRepo.setContext(companyId: companyId);

      // Add expense voucher: ₹5,000 Food & Dining
      final foodAccountId = '${companyId}_${ExpenseTrackerDefaults.foodDiningId}';
      final cashAccountId = '${companyId}_${ExpenseTrackerDefaults.walletCashId}';
      await expenseRepo.addExpense(
        categoryAccountId: foodAccountId,
        walletAccountId: cashAccountId,
        amountInCents: 500000,
        narration: 'Client Hospitality',
      );

      // Upgrade to ledger
      final upgraded = await repo.upgradeToLedger(companyId);
      expect(upgraded.mode, equals(CompanyMode.ledger));

      // Fetch accounts, journal lines, and vouchers for ledger reporting
      final accountsData = await (db.select(db.accounts)
            ..where((t) => t.companyId.equals(companyId) & t.isDeleted.equals(false)))
          .get();
      final accounts = accountsData
          .map((r) => AccountModel(
                id: r.id,
                companyId: r.companyId,
                code: r.code,
                name: r.name,
                type: AccountType.values.firstWhere((e) => e.name == r.type),
                currentBalanceInCents: r.currentBalanceInCents,
                createdAt: r.createdAt,
                updatedAt: r.updatedAt,
              ))
          .toList();

      final linesData = await (db.select(db.journalLines)
            ..where((t) => t.companyId.equals(companyId) & t.isDeleted.equals(false)))
          .get();
      final journalLines = linesData
          .map((r) => JournalLineModel(
                id: r.id,
                companyId: r.companyId,
                journalId: r.journalId,
                accountId: r.accountId,
                debitInCents: r.debitInCents,
                creditInCents: r.creditInCents,
                narration: r.narration,
                createdAt: r.createdAt,
                updatedAt: r.updatedAt,
              ))
          .toList();

      voucherRepo.setContext(companyId: companyId);
      final vouchers = await voucherRepo.getVouchers();

      // 1. Trial Balance test
      final trialBalance = FinancialStatementEngine.generateTrialBalance(
        companyId: companyId,
        accounts: accounts,
        journalLines: journalLines,
        vouchers: vouchers,
      );

      expect(trialBalance.summary['isBalanced'], isTrue);
      // Food & Dining account appears in Trial Balance with debit
      final foodRow = trialBalance.rows.firstWhere(
        (r) => (r.cells['account'] as String).contains('Food & Dining'),
      );
      expect(foodRow.cells['debit'], contains('5,000'));

      // 2. Profit & Loss Statement test
      final pnl = FinancialStatementEngine.generateProfitAndLoss(
        company: upgraded,
        vouchers: vouchers,
        accounts: accounts,
        journalLines: journalLines,
      );

      // Operating expenses row reflects the ₹5,000 expense
      final opExpenseRow = pnl.rows.firstWhere((r) => r.cells['category'] == 'Operating Expenses');
      expect(opExpenseRow.cells['amount'], contains('5,000'));

      // 3. Day Book test
      final dayBook = FinancialStatementEngine.generateDayBook(vouchers: vouchers);
      expect(dayBook.rows.isNotEmpty, isTrue);
      final dayBookExpenseRow = dayBook.rows.firstWhere((r) => r.cells['type'] == 'Expense Voucher');
      expect(dayBookExpenseRow.cells['debit'], contains('5,000'));
      expect(dayBookExpenseRow.cells['particulars'], equals('Client Hospitality'));
    });

    test('expense-only modules (budgets, recurring) become unavailable but keep data', () async {
      const companyId = 'cmp_expense_only_guard';

      final expenseCompany = Company(
        id: companyId,
        name: 'Solopreneur',
        legalName: 'Solopreneur',
        currencyCode: 'INR',
        mode: CompanyMode.expenseTracker,
        enabledModules: {AppModule.budgets, AppModule.recurring},
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await repo.createCompany(
        expenseCompany,
        initialWalletBalancesInCents: {
          ExpenseTrackerDefaults.walletCashId: 1000000,
        },
      );

      final budgetRepo = DriftBudgetRepository(db: db, currentCompanyId: companyId);
      final recurringService = RecurringService(
        db: db,
        expenseRepo: expenseRepo,
        currentCompanyId: companyId,
      );

      // Create a budget in expense mode
      final budget = await budgetRepo.createBudget(
        categoryAccountId: '${companyId}_${ExpenseTrackerDefaults.foodDiningId}',
        amountInCents: 1000000,
      );
      expect(budget.id, isNotEmpty);

      // Upgrade to ledger
      await repo.upgradeToLedger(companyId);

      // Verify expense-only modules are not allowed in ledger mode
      expect(ModuleCatalog.isModeAllowed(CompanyMode.ledger, AppModule.budgets), isFalse);
      expect(ModuleCatalog.isModeAllowed(CompanyMode.ledger, AppModule.recurring), isFalse);

      // Invalidate cache and verify budget repository rejects operations after upgrade
      budgetRepo.invalidateCompanyCache();
      expect(
        budgetRepo.createBudget(
          categoryAccountId: '${companyId}_${ExpenseTrackerDefaults.groceriesId}',
          amountInCents: 500000,
        ),
        throwsStateError,
      );

      // Verify recurring service rejects operations after upgrade
      expect(
        await recurringService.isRecurringEnabled(),
        isFalse,
      );

      // Verify historical budget data in sqlite table is PRESERVED
      final budgetRows = await (db.select(db.budgets)
            ..where((t) => t.companyId.equals(companyId) & t.isDeleted.equals(false)))
          .get();
      expect(budgetRows.length, equals(1));
      expect(budgetRows.first.id, equals(budget.id));
      expect(budgetRows.first.amountInCents, equals(1000000));
    });

    testWidgets('Settings in expense mode displays Upgrade to Business Ledger with confirmation', (tester) async {
      const companyId = 'cmp_ui_test';

      final expenseCompany = Company(
        id: companyId,
        name: 'My Personal Workspace',
        legalName: 'My Personal Workspace',
        currencyCode: 'INR',
        mode: CompanyMode.expenseTracker,
        enabledModules: {AppModule.budgets, AppModule.recurring},
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await repo.createCompany(
        expenseCompany,
        initialWalletBalancesInCents: {
          ExpenseTrackerDefaults.walletCashId: 500000,
        },
      );

      final userProfile = UserProfile(
        id: 'usr_default',
        name: 'Owner',
        email: 'owner@example.com',
        phoneNumber: '+919999999999',
        activeCompanyId: companyId,
        companies: [expenseCompany],
      );

      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          syncEngineProvider.overrideWithValue(_FakeSyncEngine(db: db)),
          driftLedgerRepositoryProvider.overrideWithValue(repo),
          userProfileProvider.overrideWith(
            () => _TestUserProfileNotifier(userProfile),
          ),
        ],
      );

      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: SettingsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Verify 'Upgrade to Business Ledger' tile is displayed
      final upgradeTile = find.byKey(const Key('upgrade_to_business_ledger_tile'));
      expect(upgradeTile, findsOneWidget);
      expect(find.text('Upgrade to Business Ledger'), findsOneWidget);

      // 2. Tap Upgrade to Business Ledger tile
      await tester.tap(upgradeTile);
      await tester.pumpAndSettle();

      // 3. Verify confirmation dialog appears explaining it cannot be undone
      expect(find.textContaining('cannot be undone'), findsOneWidget);
      expect(find.textContaining('A ledger to expense downgrade is not offered anywhere'), findsOneWidget);
      expect(find.byKey(const Key('cancel_upgrade_button')), findsOneWidget);
      expect(find.byKey(const Key('confirm_upgrade_button')), findsOneWidget);

      // 4. Tap Confirm Upgrade
      await tester.tap(find.byKey(const Key('confirm_upgrade_button')));
      await tester.pumpAndSettle();

      // 5. Verify the active company is upgraded to ledger mode
      final activeComp = container.read(activeCompanyProvider);
      expect(activeComp.mode, equals(CompanyMode.ledger));
    });

    testWidgets('HomeShell swaps from ExpenseHomeScreen to DashboardScreen on upgrade', (tester) async {
      const companyId = 'cmp_shell_swap_test';

      final expenseCompany = Company(
        id: companyId,
        name: 'Shell Test Company',
        legalName: 'Shell Test Company',
        currencyCode: 'INR',
        mode: CompanyMode.expenseTracker,
        enabledModules: {AppModule.budgets, AppModule.recurring},
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await repo.createCompany(
        expenseCompany,
        initialWalletBalancesInCents: {
          ExpenseTrackerDefaults.walletCashId: 500000,
        },
      );

      final userProfile = UserProfile(
        id: 'usr_default',
        name: 'Owner',
        email: 'owner@example.com',
        phoneNumber: '+919999999999',
        activeCompanyId: companyId,
        companies: [expenseCompany],
      );

      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          syncEngineProvider.overrideWithValue(_FakeSyncEngine(db: db)),
          driftLedgerRepositoryProvider.overrideWithValue(repo),
          userProfileProvider.overrideWith(
            () => _TestUserProfileNotifier(userProfile),
          ),
        ],
      );

      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: HomeShell(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initially shows expense home widgets (Transactions FAB, Month Switcher)
      expect(find.byKey(const Key('expense_quick_add_fab')), findsOneWidget);
      expect(find.byType(DashboardScreen), findsNothing);

      // Perform upgrade
      await container.read(companyControllerProvider.notifier).upgradeToLedger(
        companyId,
        preset: ModulePresets.billingAndGst,
      );

      await tester.pumpAndSettle();

      // After upgrade, HomeShell displays DashboardScreen
      expect(find.byType(DashboardScreen), findsOneWidget);
      expect(find.byKey(const Key('expense_quick_add_fab')), findsNothing);
    });
  });
}
