import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_pulse/core/network/sync_engine.dart';
import 'package:ledger_pulse/data/accounting/voucher_posting_engine.dart';
import 'package:ledger_pulse/data/local/audit_service.dart';
import 'package:ledger_pulse/data/local/database.dart';
import 'package:ledger_pulse/data/local/drift_expense_repository.dart';
import 'package:ledger_pulse/data/local/drift_voucher_repository.dart';
import 'package:ledger_pulse/data/models/account_model.dart';
import 'package:ledger_pulse/data/models/company_model.dart';
import 'package:ledger_pulse/data/models/rbac_model.dart';
import 'package:ledger_pulse/data/models/sync_model.dart';
import 'package:ledger_pulse/data/models/voucher_model.dart';
import 'package:ledger_pulse/data/security/access_control_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ledger_pulse/data/models/user_profile_model.dart';
import 'package:ledger_pulse/domain/exceptions/ledger_exceptions.dart';
import 'package:ledger_pulse/presentation/providers/database_providers.dart';
import 'package:ledger_pulse/presentation/providers/expense_providers.dart';
import 'package:ledger_pulse/presentation/providers/profile_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late AuditService auditService;
  late VoucherPostingEngine postingEngine;
  late DriftVoucherRepository voucherRepo;
  late DriftExpenseRepository expenseRepo;

  const expenseCompanyId = 'cmp_expense_unit_test';
  const ledgerCompanyId = 'cmp_ledger_unit_test';
  final now = DateTime(2026, 10, 15, 12, 0);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    auditService = AuditService(db);
    postingEngine = VoucherPostingEngine(db, auditService);
    voucherRepo = DriftVoucherRepository(
      db: db,
      auditService: auditService,
      postingEngine: postingEngine,
      currentCompanyId: expenseCompanyId,
    );

    // Create Expense Tracker company in db
    await db.into(db.companies).insert(
          CompaniesCompanion.insert(
            id: expenseCompanyId,
            name: 'Expense Co',
            legalName: 'Expense Co Ltd',
            mode: Value(CompanyMode.expenseTracker.name),
            enabledModulesJson: const Value('["vouchers","budgets"]'),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );

    // Seed default expense accounts
    final expenseCompany = Company(
      id: expenseCompanyId,
      name: 'Expense Co',
      legalName: 'Expense Co Ltd',
      mode: CompanyMode.expenseTracker,
      enabledModules: const {AppModule.vouchers, AppModule.budgets},
      createdAt: now,
      updatedAt: now,
    );
    await postingEngine.seedAccountsFor(
      expenseCompany,
      initialWalletBalancesInCents: {
        ExpenseTrackerDefaults.walletCashId: 50000, // 500.00
        ExpenseTrackerDefaults.walletBankId: 100000, // 1,000.00
      },
    );

    // Create Ledger company in db
    await db.into(db.companies).insert(
          CompaniesCompanion.insert(
            id: ledgerCompanyId,
            name: 'Ledger Co',
            legalName: 'Ledger Co Ltd',
            mode: Value(CompanyMode.ledger.name),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );

    expenseRepo = DriftExpenseRepository(
      db: db,
      postingEngine: postingEngine,
      voucherRepo: voucherRepo,
      auditService: auditService,
      currentCompanyId: expenseCompanyId,
      currentUserId: 'usr_test_admin',
      currentRole: Role.admin,
    );
  });

  tearDown(() async {
    expenseRepo.dispose();
    await db.close();
  });

  group('Prompt 9 - Refusal in Ledger Mode', () {
    test('DriftExpenseRepository throws ExpenseModeRequiredException when company mode is ledger', () async {
      final repoInLedgerMode = DriftExpenseRepository(
        db: db,
        postingEngine: postingEngine,
        voucherRepo: voucherRepo,
        auditService: auditService,
        currentCompanyId: ledgerCompanyId,
        currentUserId: 'usr_test_admin',
        currentRole: Role.admin,
      );

      final cashWalletId = '${expenseCompanyId}_${ExpenseTrackerDefaults.walletCashId}';
      final foodCatId = '${expenseCompanyId}_${ExpenseTrackerDefaults.foodDiningId}';

      // All expense repository operations must throw ExpenseModeRequiredException
      expect(
        () => repoInLedgerMode.addExpense(
          categoryAccountId: foodCatId,
          walletAccountId: cashWalletId,
          amountInCents: 5000,
        ),
        throwsA(isA<ExpenseModeRequiredException>()),
      );

      expect(
        () => repoInLedgerMode.getWallets(),
        throwsA(isA<ExpenseModeRequiredException>()),
      );

      expect(
        () => repoInLedgerMode.getCategories(),
        throwsA(isA<ExpenseModeRequiredException>()),
      );

      expect(
        () => repoInLedgerMode.getMonthSummary(now),
        throwsA(isA<ExpenseModeRequiredException>()),
      );
    });
  });

  group('Prompt 9 - RBAC Permissions & Denial', () {
    test('Warehouse operator is denied creating, editing, and managing wallets/categories', () async {
      expenseRepo.setContext(role: Role.warehouseOperator);

      final cashWalletId = '${expenseCompanyId}_${ExpenseTrackerDefaults.walletCashId}';
      final foodCatId = '${expenseCompanyId}_${ExpenseTrackerDefaults.foodDiningId}';

      // Warehouse operator cannot create expense
      expect(
        () => expenseRepo.addExpense(
          categoryAccountId: foodCatId,
          walletAccountId: cashWalletId,
          amountInCents: 1500,
        ),
        throwsA(isA<RbacException>()),
      );

      // Warehouse operator cannot manage wallets/categories
      expect(
        () => expenseRepo.createWallet(
          name: 'Secret Stash',
          type: AccountType.asset,
        ),
        throwsA(isA<RbacException>()),
      );

      expect(
        () => expenseRepo.createCategory(
          name: 'Snacks',
          type: AccountType.expense,
        ),
        throwsA(isA<RbacException>()),
      );

      expect(
        () => expenseRepo.setOpeningBalance(cashWalletId, 100000),
        throwsA(isA<RbacException>()),
      );
    });

    test('Sales staff can create expense but cannot manage wallets or void transactions', () async {
      expenseRepo.setContext(role: Role.salesStaff);

      final cashWalletId = '${expenseCompanyId}_${ExpenseTrackerDefaults.walletCashId}';
      final foodCatId = '${expenseCompanyId}_${ExpenseTrackerDefaults.foodDiningId}';

      // Sales staff CAN create expense
      final voucher = await expenseRepo.addExpense(
        categoryAccountId: foodCatId,
        walletAccountId: cashWalletId,
        amountInCents: 2500,
        narration: 'Client dinner',
      );
      expect(voucher.id, isNotEmpty);

      // Sales staff CANNOT manage wallets/categories
      expect(
        () => expenseRepo.createWallet(
          name: 'Petty Cash',
          type: AccountType.asset,
        ),
        throwsA(isA<RbacException>()),
      );

      // Sales staff CANNOT void transactions
      expect(
        () => expenseRepo.voidTransaction(voucher.id),
        throwsA(isA<RbacException>()),
      );
    });
  });

  group('Prompt 9 - Category CRUD and Archive Behavior', () {
    test('Category without transactions is soft-deleted; category with transactions is archived', () async {
      expenseRepo.setContext(role: Role.admin);

      // 1. Create a fresh category with no transactions
      final unusedCat = await expenseRepo.createCategory(
        name: 'Subscriptions',
        type: AccountType.expense,
        description: 'Software subscriptions',
      );
      expect(unusedCat.isActive, isTrue);

      // 2. Delete the unused category -> hard/soft deleted
      final wasDeleted = await expenseRepo.deleteCategory(unusedCat.id);
      expect(wasDeleted, isTrue);

      final activeCategories = await expenseRepo.getCategories(includeArchived: false);
      expect(activeCategories.any((c) => c.id == unusedCat.id), isFalse);

      // 3. Create a category and post a transaction with it
      final groceryCat = await expenseRepo.createCategory(
        name: 'Weekly Groceries',
        type: AccountType.expense,
      );

      final cashWalletId = '${expenseCompanyId}_${ExpenseTrackerDefaults.walletCashId}';
      await expenseRepo.addExpense(
        categoryAccountId: groceryCat.id,
        walletAccountId: cashWalletId,
        amountInCents: 3000,
      );

      // 4. Delete the category with transactions -> archived (isActive = false, isDeleted = false)
      final wasDeletedWithTxn = await expenseRepo.deleteCategory(groceryCat.id);
      expect(wasDeletedWithTxn, isFalse, reason: 'Category with transactions must be archived, not deleted');

      final activeCatsAfterArchive = await expenseRepo.getCategories(includeArchived: false);
      expect(activeCatsAfterArchive.any((c) => c.id == groceryCat.id), isFalse);

      final allCatsIncludingArchived = await expenseRepo.getCategories(includeArchived: true);
      final archivedCat = allCatsIncludingArchived.firstWhere((c) => c.id == groceryCat.id);
      expect(archivedCat.isActive, isFalse);
      final catRow = await (db.select(db.accounts)..where((t) => t.id.equals(groceryCat.id))).getSingle();
      expect(catRow.isDeleted, isFalse);
    });

    test('Category allows optional parent for sub-categories with type validation', () async {
      expenseRepo.setContext(role: Role.admin);

      final parentCat = await expenseRepo.createCategory(
        name: 'Housing & Home',
        type: AccountType.expense,
      );

      // Sub-category matching parent type
      final subCat = await expenseRepo.createCategory(
        name: 'Electricity Bill',
        type: AccountType.expense,
        parentAccountId: parentCat.id,
      );
      expect(subCat.parentAccountId, equals(parentCat.id));

      // Sub-category with mismatched type throws ArgumentError
      expect(
        () => expenseRepo.createCategory(
          name: 'Rental Income',
          type: AccountType.income,
          parentAccountId: parentCat.id,
        ),
        throwsArgumentError,
      );
    });
  });

  group('Prompt 9 - Wallet CRUD and Opening Balance', () {
    test('Setting opening balance updates asset wallet and equity account balances', () async {
      expenseRepo.setContext(role: Role.admin);

      final newBank = await expenseRepo.createWallet(
        name: 'Savings Account',
        type: AccountType.asset,
      );

      // Set opening balance to 2,000.00 (200000 cents)
      await expenseRepo.setOpeningBalance(newBank.id, 200000);

      final refreshedBank = await expenseRepo.getWalletById(newBank.id);
      expect(refreshedBank.currentBalanceInCents, equals(200000));
    });

    test('Credit card wallet opening balance and spending increase liability owed', () async {
      expenseRepo.setContext(role: Role.admin);

      final creditCard = await expenseRepo.createWallet(
        name: 'Corporate Amex',
        type: AccountType.liability,
      );

      // Opening balance of 40,000 cents (400.00 owed)
      await expenseRepo.setOpeningBalance(creditCard.id, 40000);

      final cardAfterOpening = await expenseRepo.getWalletById(creditCard.id);
      expect(cardAfterOpening.currentBalanceInCents, equals(40000));

      // Spend 15,000 cents using the credit card
      final foodCatId = '${expenseCompanyId}_${ExpenseTrackerDefaults.foodDiningId}';
      await expenseRepo.addExpense(
        categoryAccountId: foodCatId,
        walletAccountId: creditCard.id,
        amountInCents: 15000,
        narration: 'Team lunch on card',
      );

      // Liability balance must increase to 55,000 cents owed
      final cardAfterSpend = await expenseRepo.getWalletById(creditCard.id);
      expect(cardAfterSpend.currentBalanceInCents, equals(55000));
    });
  });

  group('Prompt 9 - Transaction Filters', () {
    test('Filtering by category, wallet, date range, type, and text query', () async {
      expenseRepo.setContext(role: Role.admin);

      final cashWalletId = '${expenseCompanyId}_${ExpenseTrackerDefaults.walletCashId}';
      final bankWalletId = '${expenseCompanyId}_${ExpenseTrackerDefaults.walletBankId}';
      final foodCatId = '${expenseCompanyId}_${ExpenseTrackerDefaults.foodDiningId}';
      final salaryCatId = '${expenseCompanyId}_${ExpenseTrackerDefaults.salaryId}';

      // 1. Expense in October
      final exp1 = await expenseRepo.addExpense(
        categoryAccountId: foodCatId,
        walletAccountId: cashWalletId,
        amountInCents: 1200,
        date: DateTime(2026, 10, 5),
        narration: 'Dinner with client',
        referenceNumber: 'REF-DINNER-01',
      );

      // 2. Income in October
      final inc1 = await expenseRepo.addIncome(
        categoryAccountId: salaryCatId,
        walletAccountId: bankWalletId,
        amountInCents: 85000,
        date: DateTime(2026, 10, 10),
        narration: 'Monthly wage payment',
      );

      // 3. Transfer in October
      final trf1 = await expenseRepo.addTransfer(
        walletAccountId: bankWalletId,
        toWalletAccountId: cashWalletId,
        amountInCents: 10000,
        date: DateTime(2026, 10, 12),
        narration: 'ATM Cash Withdrawal',
      );

      // 4. Expense in September (prior month)
      await expenseRepo.addExpense(
        categoryAccountId: foodCatId,
        walletAccountId: cashWalletId,
        amountInCents: 900,
        date: DateTime(2026, 9, 20),
        narration: 'Coffee',
      );

      // Test Category Filter
      final foodTxns = await expenseRepo.getTransactions(categoryIds: [foodCatId]);
      expect(foodTxns.length, equals(2));
      expect(foodTxns.every((t) => t.categoryAccountId == foodCatId), isTrue);

      // Test Wallet Filter
      final bankTxns = await expenseRepo.getTransactions(walletIds: [bankWalletId]);
      expect(bankTxns.length, equals(2)); // inc1 (wallet) + trf1 (walletAccountId)

      // Test Type Filter
      final incomeTxns = await expenseRepo.getTransactions(type: VoucherType.income);
      expect(incomeTxns.length, equals(1));
      expect(incomeTxns.first.id, equals(inc1.id));

      final transferTxns = await expenseRepo.getTransactions(type: VoucherType.transfer);
      expect(transferTxns.length, equals(1));
      expect(transferTxns.first.id, equals(trf1.id));

      // Test Text Query
      final searchDinner = await expenseRepo.getTransactions(textQuery: 'DINNER');
      expect(searchDinner.length, equals(1));
      expect(searchDinner.first.id, equals(exp1.id));

      // Test Date Range Filter (October only)
      final octTxns = await expenseRepo.getTransactions(
        startDate: DateTime(2026, 10, 1),
        endDate: DateTime(2026, 10, 31, 23, 59, 59),
      );
      expect(octTxns.length, equals(3));
    });
  });

  group('Prompt 9 - Month Summary Correctness', () {
    test('getMonthSummary computes correct income, expense, net, wallet balances, and category totals', () async {
      expenseRepo.setContext(role: Role.admin);

      final cashWalletId = '${expenseCompanyId}_${ExpenseTrackerDefaults.walletCashId}';
      final bankWalletId = '${expenseCompanyId}_${ExpenseTrackerDefaults.walletBankId}';
      final foodCatId = '${expenseCompanyId}_${ExpenseTrackerDefaults.foodDiningId}';
      final salaryCatId = '${expenseCompanyId}_${ExpenseTrackerDefaults.salaryId}';

      // October transactions
      await expenseRepo.addIncome(
        categoryAccountId: salaryCatId,
        walletAccountId: bankWalletId,
        amountInCents: 90000, // 900.00
        date: DateTime(2026, 10, 2),
      );

      await expenseRepo.addExpense(
        categoryAccountId: foodCatId,
        walletAccountId: cashWalletId,
        amountInCents: 25000, // 250.00
        date: DateTime(2026, 10, 10),
      );

      await expenseRepo.addTransfer(
        walletAccountId: bankWalletId,
        toWalletAccountId: cashWalletId,
        amountInCents: 15000, // 150.00
        date: DateTime(2026, 10, 15),
      );

      // November transaction (should not be included in October summary)
      await expenseRepo.addExpense(
        categoryAccountId: foodCatId,
        walletAccountId: cashWalletId,
        amountInCents: 5000,
        date: DateTime(2026, 11, 1),
      );

      final summary = await expenseRepo.getMonthSummary(DateTime(2026, 10, 1));

      expect(summary.totalIncomeInCents, equals(90000));
      expect(summary.totalExpenseInCents, equals(25000));
      expect(summary.netInCents, equals(65000)); // 90000 - 25000

      expect(summary.categoryTotalsInCents[salaryCatId], equals(90000));
      expect(summary.categoryTotalsInCents[foodCatId], equals(25000));

      // Initial wallet balances: Cash = 50,000, Bank = 100,000
      // Income into Bank: +90,000 => Bank = 190,000
      // Expense from Cash: -25,000 => Cash = 25,000
      // Transfer: Bank -> Cash (15,000) => Bank = 175,000, Cash = 40,000
      // Plus November Cash expense: -5,000 => Cash = 35,000
      expect(summary.walletBalancesInCents[bankWalletId], equals(175000));
      expect(summary.walletBalancesInCents[cashWalletId], equals(35000));
    });

    test('Voiding a transaction updates month summary and recalculates balances', () async {
      expenseRepo.setContext(role: Role.admin);

      final cashWalletId = '${expenseCompanyId}_${ExpenseTrackerDefaults.walletCashId}';
      final foodCatId = '${expenseCompanyId}_${ExpenseTrackerDefaults.foodDiningId}';

      final exp = await expenseRepo.addExpense(
        categoryAccountId: foodCatId,
        walletAccountId: cashWalletId,
        amountInCents: 10000,
        date: DateTime(2026, 10, 18),
      );

      var summary = await expenseRepo.getMonthSummary(DateTime(2026, 10, 1));
      expect(summary.totalExpenseInCents, equals(10000));

      // Void the expense
      await expenseRepo.voidTransaction(exp.id);

      summary = await expenseRepo.getMonthSummary(DateTime(2026, 10, 1));
      expect(summary.totalExpenseInCents, equals(0));
    });
  });

  group('Prompt 9 - Repository Updates Stream', () {
    test('Mutations emit events on repositoryUpdatesStream', () async {
      expenseRepo.setContext(role: Role.admin);

      final cashWalletId = '${expenseCompanyId}_${ExpenseTrackerDefaults.walletCashId}';
      final foodCatId = '${expenseCompanyId}_${ExpenseTrackerDefaults.foodDiningId}';

      int eventCount = 0;
      final sub = expenseRepo.repositoryUpdatesStream.listen((_) {
        eventCount++;
      });

      await expenseRepo.addExpense(
        categoryAccountId: foodCatId,
        walletAccountId: cashWalletId,
        amountInCents: 1000,
      );

      await expenseRepo.createWallet(
        name: 'Travel Cash',
        type: AccountType.asset,
      );

      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(eventCount, equals(2));

      await sub.cancel();
    });
  });

  group('Prompt 9 - Riverpod Expense Providers', () {
    test('expense_providers refresh reactively when repository updates stream emits', () async {
      final expenseCompany = Company(
        id: expenseCompanyId,
        name: 'Expense Co',
        legalName: 'Expense Co Ltd',
        mode: CompanyMode.expenseTracker,
        enabledModules: const {AppModule.vouchers, AppModule.budgets},
        createdAt: now,
        updatedAt: now,
      );

      final profile = UserProfile(
        id: 'usr_test_admin',
        name: 'Test Admin',
        phoneNumber: '+91 99999 11111',
        email: 'admin@expense.co',
        companies: [expenseCompany],
        activeCompanyId: expenseCompany.id,
      );

      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          syncEngineProvider.overrideWithValue(_FakeSyncEngineForRepo(db: db)),
          userProfileProvider.overrideWith(() => _TestProfileNotifier(profile)),
        ],
      );
      addTearDown(container.dispose);

      // Verify selectedMonthProvider and transactionFiltersProvider defaults
      final selectedMonth = container.read(selectedMonthProvider);
      expect(selectedMonth.month, equals(DateTime.now().month));

      final filters = container.read(transactionFiltersProvider);
      expect(filters.type, isNull);
      expect(filters.categoryIds, isNull);

      // Read walletsProvider
      final wallets = await container.read(walletsProvider.future);
      expect(wallets.length, equals(2)); // Cash and Bank

      // Read categoriesProvider
      final categories = await container.read(categoriesProvider.future);
      expect(categories.isNotEmpty, isTrue);

      // Read initial monthSummaryProvider
      final initialSummary = await container.read(monthSummaryProvider.future);
      expect(initialSummary.totalExpenseInCents, equals(0));

      // Post an expense via repository
      final foodCatId = '${expenseCompanyId}_${ExpenseTrackerDefaults.foodDiningId}';
      final cashWalletId = '${expenseCompanyId}_${ExpenseTrackerDefaults.walletCashId}';
      final repo = container.read(expenseRepositoryProvider);

      await repo.addExpense(
        categoryAccountId: foodCatId,
        walletAccountId: cashWalletId,
        amountInCents: 4500,
        date: DateTime.now(),
      );

      // Allow microtask/stream propagation
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // monthSummaryProvider should have invalidated and updated
      final updatedSummary = await container.read(monthSummaryProvider.future);
      expect(updatedSummary.totalExpenseInCents, equals(4500));

      // transactionsProvider should contain the newly added transaction
      final txns = await container.read(transactionsProvider.future);
      expect(txns.length, equals(1));
      expect(txns.first.totalAmountInCents, equals(4500));
    });
  });
}

class _FakeSyncEngineForRepo extends SyncEngine {
  _FakeSyncEngineForRepo({required super.db});

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

