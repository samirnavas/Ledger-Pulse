import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ledger_pulse/core/network/sync_engine.dart';
import 'package:ledger_pulse/data/local/database.dart';
import 'package:ledger_pulse/data/local/outbox_helper.dart';
import 'package:ledger_pulse/data/local/drift_expense_repository.dart';
import 'package:ledger_pulse/data/local/drift_budget_repository.dart';
import 'package:ledger_pulse/data/models/account_model.dart';
import 'package:ledger_pulse/data/models/budget_model.dart';
import 'package:ledger_pulse/data/models/company_model.dart';
import 'package:ledger_pulse/data/models/rbac_model.dart';
import 'package:ledger_pulse/data/models/voucher_model.dart';
import 'package:ledger_pulse/data/models/party_model.dart';
import 'package:ledger_pulse/data/models/inventory_item_model.dart';
import 'package:ledger_pulse/data/accounting/voucher_posting_engine.dart';
import 'package:ledger_pulse/data/local/audit_service.dart';
import 'package:ledger_pulse/data/local/drift_voucher_repository.dart';
import 'package:ledger_pulse/data/local/drift_inventory_repository.dart';
import 'package:ledger_pulse/data/local/drift_ledger_repository.dart';
import 'package:ledger_pulse/domain/models/workspace_profile_header.dart';
import 'package:ledger_pulse/presentation/providers/profile_session_controller.dart';

import '../generated_migrations/schema.dart';

class FailingRemoteGateway implements RemoteGateway {
  @override
  Future<Map<String, dynamic>?> upsertRow({
    required String table,
    required Map<String, dynamic> row,
  }) async {
    throw const PostgrestException(
      message: 'relation "exp_transactions" does not exist',
      code: '42P01',
    );
  }

  @override
  Future<List<Map<String, dynamic>>> pullRows({
    required String table,
    required String companyId,
    String? activeUserId,
    DateTime? cursor,
    int pageSize = 500,
    int offset = 0,
    DateTime? afterUpdatedAt,
    String? afterId,
  }) async {
    return [];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  const testUserId = '11111111-1111-4111-8111-111111111111';

  group('Database Architecture & Domain Invariants Tests', () {
    late AppDatabase db;
    late SyncEngine syncEngine;
    late DriftProfileRepository profileRepo;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory(), testUserId);
      syncEngine = SyncEngine(db: db, simulateSyncForTesting: true);
      profileRepo = DriftProfileRepository(db: db, syncEngine: syncEngine);
    });

    tearDown(() async {
      syncEngine.dispose();
      await db.close();
    });

    test('1. Profile creation creates canonical profile row, links 1:1 company, and seeds appropriate domain records', () async {
      // 1A. Create Expense Profile
      final expenseProfile = await profileRepo.createProfile(
        name: 'Personal Wallet',
        type: ProfileType.expense,
        accountId: testUserId,
      );

      // Verify canonical profile row exists in `profiles` table
      final canonicalExp = await (db.select(db.profiles)..where((p) => p.id.equals(expenseProfile.id))).getSingle();
      expect(canonicalExp.name, equals('Personal Wallet'));
      expect(canonicalExp.profileType, equals('expense'));
      expect(canonicalExp.ownerId, equals(testUserId));

      // Verify company row links back via profileId
      final compExp = await (db.select(db.companies)..where((c) => c.id.equals(expenseProfile.id))).getSingle();
      expect(compExp.profileId, equals(expenseProfile.id));

      // Verify expense default wallets and categories exist
      final wallets = await (db.select(db.expenseWallets)..where((w) => w.profileId.equals(expenseProfile.id))).get();
      expect(wallets.isNotEmpty, isTrue);
      final categories = await (db.select(db.expenseCategories)..where((c) => c.profileId.equals(expenseProfile.id))).get();
      expect(categories.isNotEmpty, isTrue);

      // Verify zero double-entry accounting accounts were seeded for expense profile
      final expAccounts = await (db.select(db.accounts)..where((a) => a.companyId.equals(expenseProfile.id))).get();
      expect(expAccounts, isEmpty);

      // 1B. Create Ledger Profile
      final ledgerProfile = await profileRepo.createProfile(
        name: 'Alpha Traders',
        type: ProfileType.ledger,
        accountId: testUserId,
      );

      // Verify canonical profile row exists in `profiles` table
      final canonicalLedger = await (db.select(db.profiles)..where((p) => p.id.equals(ledgerProfile.id))).getSingle();
      expect(canonicalLedger.name, equals('Alpha Traders'));
      expect(canonicalLedger.profileType, equals('ledger'));
      expect(canonicalLedger.ownerId, equals(testUserId));

      // Verify company row exists with matching profileId
      final compLedger = await (db.select(db.companies)..where((c) => c.id.equals(ledgerProfile.id))).getSingle();
      expect(compLedger.profileId, equals(ledgerProfile.id));

      // Verify double-entry accounts WERE seeded for ledger profile
      final ledgerAccounts = await (db.select(db.accounts)..where((a) => a.companyId.equals(ledgerProfile.id))).get();
      expect(ledgerAccounts.isNotEmpty, isTrue);
    });

    test('2. Expense transactions persist strictly to exp_transactions with ZERO vouchers, journals, journal_lines, or ledger accounts', () async {
      // Setup expense profile
      final expProfile = await profileRepo.createProfile(
        name: 'Household',
        type: ProfileType.expense,
        accountId: testUserId,
      );

      final wallets = await (db.select(db.expenseWallets)..where((w) => w.profileId.equals(expProfile.id))).get();
      final defaultWallet = wallets.first;

      final categories = await (db.select(db.expenseCategories)..where((c) => c.profileId.equals(expProfile.id))).get();
      final defaultCategory = categories.first;

      final expenseRepo = DriftExpenseRepository(
        db: db,
        currentCompanyId: expProfile.id,
        currentUserId: testUserId,
        currentRole: Role.admin,
      );

      // Add a second wallet for transfers
      final secondWallet = await expenseRepo.createWallet(
        name: 'Bank Savings',
        type: AccountType.asset,
      );

      // 2A. Record Expense
      final expenseTxn = await expenseRepo.addExpense(
        categoryAccountId: defaultCategory.id,
        walletAccountId: defaultWallet.id,
        amountInCents: 1500,
        narration: 'Grocery store receipt',
      );
      expect(expenseTxn.id, isNotEmpty);

      // 2B. Record Income
      final incomeTxn = await expenseRepo.addIncome(
        categoryAccountId: defaultCategory.id,
        walletAccountId: defaultWallet.id,
        amountInCents: 10000,
        narration: 'Freelance payment',
      );
      expect(incomeTxn.id, isNotEmpty);

      // 2C. Record Transfer
      final transferTxn = await expenseRepo.addTransfer(
        walletAccountId: defaultWallet.id,
        toWalletAccountId: secondWallet.id,
        amountInCents: 2000,
        narration: 'Transfer to savings',
      );
      expect(transferTxn.id, isNotEmpty);

      // Verify dedicated table contains exactly 3 records
      final allExpTxns = await (db.select(db.expenseTransactions)..where((t) => t.profileId.equals(expProfile.id))).get();
      expect(allExpTxns.length, equals(3));

      // CRITICAL INVARIANT: Zero vouchers, journals, journal lines, ledger entries, or accounts
      final vouchers = await (db.select(db.vouchers)..where((v) => v.companyId.equals(expProfile.id))).get();
      expect(vouchers, isEmpty, reason: 'Expense operations must never write to vouchers table');

      final journals = await (db.select(db.journals)..where((j) => j.companyId.equals(expProfile.id))).get();
      expect(journals, isEmpty, reason: 'Expense operations must never write to journals table');

      final journalLines = await (db.select(db.journalLines)..where((jl) => jl.companyId.equals(expProfile.id))).get();
      expect(journalLines, isEmpty, reason: 'Expense operations must never write to journal_lines table');

      final ledgerEntries = await (db.select(db.ledgerEntries)..where((le) => le.companyId.equals(expProfile.id))).get();
      expect(ledgerEntries, isEmpty, reason: 'Expense operations must never write to ledger_entries table');

      final accounts = await (db.select(db.accounts)..where((a) => a.companyId.equals(expProfile.id))).get();
      expect(accounts, isEmpty, reason: 'Expense operations must never create accounting accounts');

      expenseRepo.dispose();
    });

    test('3. Expense budgets persist strictly to exp_budgets and calculate progress from exp_transactions', () async {
      final expProfile = await profileRepo.createProfile(
        name: 'Budget Test Profile',
        type: ProfileType.expense,
        accountId: testUserId,
      );

      final wallets = await (db.select(db.expenseWallets)..where((w) => w.profileId.equals(expProfile.id))).get();
      final defaultWallet = wallets.first;

      final categories = await (db.select(db.expenseCategories)..where((c) => c.profileId.equals(expProfile.id))).get();
      final foodCategory = categories.first;

      final budgetRepo = DriftBudgetRepository(
        db: db,
        currentCompanyId: expProfile.id,
      );

      // 3A. Create Budget
      final budget = await budgetRepo.createBudget(
        categoryAccountId: foodCategory.id,
        periodType: BudgetPeriodType.monthly,
        amountInCents: 20000,
        startDate: DateTime.now(),
      );
      expect(budget.id, isNotEmpty);

      // Verify written to dedicated exp_budgets table
      final expBudgets = await (db.select(db.expenseBudgets)..where((b) => b.profileId.equals(expProfile.id))).get();
      expect(expBudgets.length, equals(1));
      expect(expBudgets.first.amountInCents, equals(20000));

      // CRITICAL INVARIANT: Zero writes to legacy `budgets` table
      final legacyBudgets = await (db.select(db.budgets)..where((b) => b.companyId.equals(expProfile.id))).get();
      expect(legacyBudgets, isEmpty, reason: 'Expense budgets must never be written to legacy budgets table');

      // 3B. Record an expense transaction and verify budget progress computation
      final expenseRepo = DriftExpenseRepository(
        db: db,
        currentCompanyId: expProfile.id,
        currentUserId: testUserId,
        currentRole: Role.admin,
      );

      await expenseRepo.addExpense(
        categoryAccountId: foodCategory.id,
        walletAccountId: defaultWallet.id,
        amountInCents: 7500,
      );

      final progress = await budgetRepo.calculateProgress(budget, asOfDate: DateTime.now());
      expect(progress.spentInCents, equals(7500));
      expect(progress.remainingInCents, equals(12500));

      budgetRepo.dispose();
      expenseRepo.dispose();
    });

    test('4. Remote sync failures rethrow PostgrestException and preserve pending outbox records without fake success', () async {
      final failingSyncEngine = SyncEngine(
        db: db,
        fakeRemoteStore: FailingRemoteGateway(),
        activeUserId: testUserId,
        simulateSyncForTesting: false,
      );

      // Enqueue an outbox mutation
      await enqueueMutation(
        db: db,
        table: 'exp_transactions',
        recordId: 'txn_test_error_handling',
        type: 'UPSERT',
        fullRowMap: {
          'id': 'txn_test_error_handling',
          'profile_id': 'prf_error_test',
          'amount_in_cents': 5000,
        },
      );

      final outboxBefore = await db.select(db.syncOutbox).get();
      expect(outboxBefore.length, equals(1));
      expect(outboxBefore.first.recordId, equals('txn_test_error_handling'));

      // Attempt pushQueue - must fail and record error without marking as synced or deleting
      final syncResult = await failingSyncEngine.pushQueue(companyId: 'prf_error_test');
      expect(syncResult.isSuccess, isFalse);

      // CRITICAL INVARIANT: The mutation MUST still be in the outbox with an error recorded
      final outboxAfter = await db.select(db.syncOutbox).get();
      expect(outboxAfter.length, equals(1), reason: 'Outbox mutation must not be deleted or marked synced on error');
      expect(outboxAfter.first.attempts, greaterThanOrEqualTo(1));
      expect(outboxAfter.first.lastError, matcherNotNull);
      expect(outboxAfter.first.lastError, contains('42P01'));

      failingSyncEngine.dispose();
    });

    test('5. Drift migration from v11 to v12 populates profiles table and backfills companies.profile_id', () async {
      final verifier = SchemaVerifier(GeneratedHelper());

      final schema = await verifier.schemaAt(11);
      final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      // Seed a company and legacy expense records into schema v11
      schema.rawDatabase.execute('''
        INSERT INTO companies (
          id, name, legal_name, mode, owner_id, currency_code, is_cloud_sync_enabled, is_active, is_deleted, created_at, updated_at
        ) VALUES (
          'cmp_v11_test', 'V11 Company', 'V11 Company Ltd', 'expenseTracker', '$testUserId', 'INR', 1, 1, 0, $nowSeconds, $nowSeconds
        );
      ''');

      schema.rawDatabase.execute('''
        INSERT INTO accounts (
          id, company_id, code, name, type, kind, is_system, is_active, current_balance_in_cents, is_deleted, created_at, updated_at
        ) VALUES (
          'acc_v11_wallet', 'cmp_v11_test', '1010', 'Cash Wallet', 'asset', 'wallet', 0, 1, 35000, 0, $nowSeconds, $nowSeconds
        );
      ''');

      // Migrate to latest v12
      final migratedDb = AppDatabase(schema.newConnection());
      // Trigger opening which executes drift onUpgrade (from11To12)
      await migratedDb.customSelect('SELECT 1').get();

      // Verify canonical profiles table has the migrated profile
      final profileRows = await (migratedDb.select(migratedDb.profiles)..where((p) => p.id.equals('cmp_v11_test'))).get();
      expect(profileRows.length, equals(1));
      expect(profileRows.first.name, equals('V11 Company'));
      expect(profileRows.first.profileType, equals('expense'));
      expect(profileRows.first.ownerId, equals(testUserId));

      // Verify companies.profile_id is backfilled and equals company id
      final companyRows = await (migratedDb.select(migratedDb.companies)..where((c) => c.id.equals('cmp_v11_test'))).get();
      expect(companyRows.first.profileId, equals('cmp_v11_test'));

      // Verify expense_wallets was backfilled
      final walletRows = await (migratedDb.select(migratedDb.expenseWallets)..where((w) => w.id.equals('acc_v11_wallet'))).get();
      expect(walletRows.length, equals(1));
      expect(walletRows.first.currentBalanceInCents, equals(35000));

      await migratedDb.close();
    });

    test('6. Companies profileId unique constraint prevents multiple companies sharing the same profileId', () async {
      await db.into(db.profiles).insert(
        ProfilesCompanion.insert(
          id: 'prf_unique_1',
          name: 'Unique Profile',
          profileType: const Value('ledger'),
          ownerId: const Value(testUserId),
        ),
      );

      await db.into(db.companies).insert(
        CompaniesCompanion.insert(
          id: 'cmp_unique_1',
          profileId: const Value('prf_unique_1'),
          name: 'Company One',
          legalName: 'Company One Ltd',
          ownerId: const Value(testUserId),
        ),
      );

      // Attempting to insert a second company with the same profileId must throw SQLite constraint failure
      expect(
        () => db.into(db.companies).insert(
          CompaniesCompanion.insert(
            id: 'cmp_unique_2',
            profileId: const Value('prf_unique_1'),
            name: 'Company Two',
            legalName: 'Company Two Ltd',
            ownerId: const Value(testUserId),
          ),
        ),
        throwsA(isA<SqliteException>()),
      );
    });

    test('7. Ledger operations create correctly balanced accounting entries (debits == credits)', () async {
      final ledgerProfile = await profileRepo.createProfile(
        name: 'Ledger Audit Corp',
        type: ProfileType.ledger,
        accountId: testUserId,
        enabledModules: {
          AppModule.vouchers,
          AppModule.parties,
          AppModule.inventory,
        },
      );

      final auditService = AuditService(db);
      final postingEngine = VoucherPostingEngine(db, auditService);
      final voucherRepo = DriftVoucherRepository(
        db: db,
        auditService: auditService,
        postingEngine: postingEngine,
        currentCompanyId: ledgerProfile.id,
      );
      final ledgerRepo = DriftLedgerRepository(
        db: db,
        syncEngine: syncEngine,
        currentCompanyId: ledgerProfile.id,
      );
      final inventoryRepo = DriftInventoryRepository(
        db: db,
        auditService: auditService,
        currentCompanyId: ledgerProfile.id,
      );

      // Add party & item
      final now = DateTime.now();
      await ledgerRepo.addParty(Party(
        id: 'party_customer_audit',
        name: 'Audit Retailer',
        phoneNumber: '9876543210',
        type: PartyType.customer,
        netBalanceInCents: 0,
        lastUpdated: now,
      ));

      await inventoryRepo.addItem(InventoryItem(
        id: 'sku_item_audit',
        companyId: ledgerProfile.id,
        name: 'Audit Widget',
        sku: 'AUD-001',
        sellingPriceInCents: 10000,
        purchasePriceInCents: 5000,
        currentStockQuantity: 100.0,
        minimumStockAlert: 5.0,
        unit: 'pcs',
        createdAt: now,
        updatedAt: now,
      ));

      // Post Sales Voucher for 5 units @ 100.00 = 500.00 (50000 cents)
      final voucher = VoucherModel(
        id: 'vch_sales_audit_1',
        companyId: ledgerProfile.id,
        voucherNumber: 'INV-AUD-001',
        type: VoucherType.sales,
        partyId: 'party_customer_audit',
        partyName: 'Audit Retailer',
        date: now,
        subtotalInCents: 50000,
        taxInCents: 0,
        discountInCents: 0,
        totalAmountInCents: 50000,
        status: VoucherStatus.posted,
        items: const [
          VoucherItemModel(
            itemId: 'sku_item_audit',
            itemName: 'Audit Widget',
            sku: 'AUD-001',
            quantity: 5.0,
            unitPriceInCents: 10000,
            taxRatePercent: 0,
            discountInCents: 0,
            totalInCents: 50000,
          ),
        ],
        createdAt: now,
        updatedAt: now,
      );

      await voucherRepo.createVoucher(voucher);

      // Verify journals were created for this voucher
      final journals = await (db.select(db.journals)..where((t) => t.voucherId.equals('vch_sales_audit_1'))).get();
      expect(journals.length, equals(1));

      // Verify journal lines are strictly balanced
      final lines = await (db.select(db.journalLines)..where((t) => t.journalId.equals(journals.first.id))).get();
      expect(lines.isNotEmpty, isTrue);

      final totalDebit = lines.fold<int>(0, (sum, l) => sum + l.debitInCents);
      final totalCredit = lines.fold<int>(0, (sum, l) => sum + l.creditInCents);
      expect(totalDebit, equals(50000));
      expect(totalCredit, equals(50000));
      expect(totalDebit == totalCredit, isTrue, reason: 'Ledger double-entry debits must strictly equal credits');
    });
  });
}
const matcherNotNull = isNotNull;
