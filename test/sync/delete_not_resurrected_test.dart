import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_pulse/core/network/sync_engine.dart';
import 'package:ledger_pulse/data/accounting/voucher_posting_engine.dart';
import 'package:ledger_pulse/data/local/audit_service.dart';
import 'package:ledger_pulse/data/local/database.dart';
import 'package:ledger_pulse/data/local/drift_expense_repository.dart';
import 'package:ledger_pulse/data/local/drift_ledger_repository.dart';
import 'package:ledger_pulse/data/models/account_model.dart';
import 'package:ledger_pulse/data/models/company_model.dart';
import 'package:ledger_pulse/data/models/party_model.dart';
import 'package:ledger_pulse/data/models/transaction_model.dart';

import 'support/strict_fake_remote.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Delete / Void Not Resurrected on Pull Tests', () {
    test('1. Expense Voucher Voiding: pullChanges before pushQueue does not resurrect voided expense', () async {
      final db = AppDatabase(NativeDatabase.memory());
      final fakeRemote = StrictFakeRemoteSyncBackend();
      final syncEngine = SyncEngine(
        db: db,
        simulateSyncForTesting: true,
        fakeRemoteStore: fakeRemote,
      );

      final auditService = AuditService(db);
      final postingEngine = VoucherPostingEngine(db, auditService);
      const companyId = 'cmp_resurrect_vch';
      const userId = 'usr_resurrect_vch';

      final company = Company(
        id: companyId,
        name: 'Resurrect Vch Co',
        legalName: 'Resurrect Vch Co',
        mode: CompanyMode.expenseTracker,
        enabledModules: {AppModule.vouchers},
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final ledgerRepo = DriftLedgerRepository(
        db: db,
        postingEngine: postingEngine,
        syncEngine: syncEngine,
        currentCompanyId: companyId,
        currentUserId: userId,
      );
      await ledgerRepo.createCompany(company);
      await postingEngine.ensureCompanyAccounts(companyId);

      final expenseRepo = DriftExpenseRepository(
        db: db,
        auditService: auditService,
        postingEngine: postingEngine,
        syncEngine: syncEngine,
        currentCompanyId: companyId,
        currentUserId: userId,
      );

      final walletId = '${companyId}_${ExpenseTrackerDefaults.walletCashId}';
      final categoryId = '${companyId}_${ExpenseTrackerDefaults.groceriesId}';

      final voucher = await expenseRepo.addExpense(
        categoryAccountId: categoryId,
        walletAccountId: walletId,
        amountInCents: 50000,
        narration: 'Expense to void',
      );

      fakeRemote.upsert('exp_transactions', voucher.id, {
        'id': voucher.id,
        'profile_id': companyId,
        'transaction_type': 'expense',
        'is_deleted': false,
        'amount_in_cents': 50000,
        'category_id': categoryId,
        'wallet_id': walletId,
      });

      await expenseRepo.voidTransaction(voucher.id);

      await syncEngine.pullChanges(companyId: companyId);

      final localTx = await (db.select(db.expenseTransactions)..where((t) => t.id.equals(voucher.id))).getSingle();
      expect(
        localTx.isDeleted,
        isTrue,
        reason: 'Expense transaction should remain voided/deleted locally after pull',
      );

      await db.close();
    });

    test('2. Wallet Deletion: pullChanges before pushQueue does not resurrect deleted wallet', () async {
      final db = AppDatabase(NativeDatabase.memory());
      final fakeRemote = StrictFakeRemoteSyncBackend();
      final syncEngine = SyncEngine(
        db: db,
        simulateSyncForTesting: true,
        fakeRemoteStore: fakeRemote,
      );

      final auditService = AuditService(db);
      final postingEngine = VoucherPostingEngine(db, auditService);
      const companyId = 'cmp_resurrect_wlt';
      const userId = 'usr_resurrect_wlt';

      final company = Company(
        id: companyId,
        name: 'Resurrect Wlt Co',
        legalName: 'Resurrect Wlt Co',
        mode: CompanyMode.expenseTracker,
        enabledModules: {AppModule.vouchers},
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final ledgerRepo = DriftLedgerRepository(
        db: db,
        postingEngine: postingEngine,
        syncEngine: syncEngine,
        currentCompanyId: companyId,
        currentUserId: userId,
      );
      await ledgerRepo.createCompany(company);
      await postingEngine.ensureCompanyAccounts(companyId);

      final expenseRepo = DriftExpenseRepository(
        db: db,
        auditService: auditService,
        postingEngine: postingEngine,
        syncEngine: syncEngine,
        currentCompanyId: companyId,
        currentUserId: userId,
      );

      final customWallet = await expenseRepo.createWallet(name: 'Test Wallet Sync', type: AccountType.asset);

      fakeRemote.upsert('exp_wallets', customWallet.id, {
        'id': customWallet.id,
        'profile_id': companyId,
        'name': 'Test Wallet Sync',
        'is_deleted': false,
      });

      await expenseRepo.deleteWallet(customWallet.id);

      await syncEngine.pullChanges(companyId: companyId);

      final localWallet = await (db.select(db.expenseWallets)..where((t) => t.id.equals(customWallet.id))).getSingle();
      expect(
        localWallet.isDeleted || localWallet.isArchived,
        isTrue,
        reason: 'Wallet should remain deleted/archived locally after pull',
      );

      await db.close();
    });

    test('3. Category Deletion: pullChanges before pushQueue does not resurrect deleted category', () async {
      final db = AppDatabase(NativeDatabase.memory());
      final fakeRemote = StrictFakeRemoteSyncBackend();
      final syncEngine = SyncEngine(
        db: db,
        simulateSyncForTesting: true,
        fakeRemoteStore: fakeRemote,
      );

      final auditService = AuditService(db);
      final postingEngine = VoucherPostingEngine(db, auditService);
      const companyId = 'cmp_resurrect_cat';
      const userId = 'usr_resurrect_cat';

      final company = Company(
        id: companyId,
        name: 'Resurrect Cat Co',
        legalName: 'Resurrect Cat Co',
        mode: CompanyMode.expenseTracker,
        enabledModules: {AppModule.vouchers},
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final ledgerRepo = DriftLedgerRepository(
        db: db,
        postingEngine: postingEngine,
        syncEngine: syncEngine,
        currentCompanyId: companyId,
        currentUserId: userId,
      );
      await ledgerRepo.createCompany(company);
      await postingEngine.ensureCompanyAccounts(companyId);

      final expenseRepo = DriftExpenseRepository(
        db: db,
        auditService: auditService,
        postingEngine: postingEngine,
        syncEngine: syncEngine,
        currentCompanyId: companyId,
        currentUserId: userId,
      );

      final customCat = await expenseRepo.createCategory(name: 'Test Category Sync', type: AccountType.expense);

      fakeRemote.upsert('exp_categories', customCat.id, {
        'id': customCat.id,
        'profile_id': companyId,
        'name': 'Test Category Sync',
        'category_type': 'expense',
        'is_deleted': false,
      });

      await expenseRepo.deleteCategory(customCat.id);

      await syncEngine.pullChanges(companyId: companyId);

      final localCat = await (db.select(db.expenseCategories)..where((t) => t.id.equals(customCat.id))).getSingle();
      expect(
        localCat.isDeleted,
        isTrue,
        reason: 'Category should remain deleted/inactive locally after pull',
      );

      await db.close();
    });

    test('4. Ledger Entry Deletion: pullChanges before pushQueue does not resurrect deleted entry', () async {
      final db = AppDatabase(NativeDatabase.memory());
      final fakeRemote = StrictFakeRemoteSyncBackend();
      final syncEngine = SyncEngine(
        db: db,
        simulateSyncForTesting: true,
        fakeRemoteStore: fakeRemote,
      );

      final auditService = AuditService(db);
      final postingEngine = VoucherPostingEngine(db, auditService);
      const companyId = 'cmp_resurrect_entry';
      const userId = 'usr_resurrect_entry';

      final company = Company(
        id: companyId,
        name: 'Resurrect Entry Co',
        legalName: 'Resurrect Entry Co',
        mode: CompanyMode.expenseTracker,
        enabledModules: {AppModule.vouchers},
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final ledgerRepo = DriftLedgerRepository(
        db: db,
        postingEngine: postingEngine,
        syncEngine: syncEngine,
        currentCompanyId: companyId,
        currentUserId: userId,
      );
      await ledgerRepo.createCompany(company);
      await postingEngine.ensureCompanyAccounts(companyId);

      await db.into(db.accounts).insertOnConflictUpdate(
            AccountsCompanion.insert(
              id: '${companyId}_acc_ar',
              companyId: const Value(companyId),
              code: '1100',
              name: 'Accounts Receivable',
              type: AccountType.asset.name,
              isSystem: const Value(true),
              isActive: const Value(true),
              currentBalanceInCents: const Value(0),
              createdAt: Value(DateTime.now()),
              updatedAt: Value(DateTime.now()),
            ),
          );
      await db.into(db.accounts).insertOnConflictUpdate(
            AccountsCompanion.insert(
              id: '${companyId}_acc_sales',
              companyId: const Value(companyId),
              code: '4000',
              name: 'Sales',
              type: AccountType.income.name,
              isSystem: const Value(true),
              isActive: const Value(true),
              currentBalanceInCents: const Value(0),
              createdAt: Value(DateTime.now()),
              updatedAt: Value(DateTime.now()),
            ),
          );

      final partyId = 'party_resurrect_1';
      await ledgerRepo.addParty(Party(
        id: partyId,
        name: 'Resurrect Test Party',
        phoneNumber: '+91 91111 22222',
        type: PartyType.customer,
        netBalanceInCents: 0,
        lastUpdated: DateTime.now(),
      ));

      final entryId = 'entry_resurrect_1';
      final entry = LedgerEntry(
        id: entryId,
        partyId: partyId,
        amountInCents: 30000,
        type: EntryType.gave,
        date: DateTime.now(),
        note: 'Entry to delete',
      );
      await ledgerRepo.addEntry(entry);

      fakeRemote.upsert('ledger_entries', entryId, {
        'id': entryId,
        'company_id': companyId,
        'party_id': partyId,
        'amount_in_cents': 30000,
        'type': 'gave',
        'is_deleted': false,
        'is_voided': false,
      });

      await ledgerRepo.deleteEntry(entryId);

      await syncEngine.pullChanges(companyId: companyId);

      final localEntry = await (db.select(db.ledgerEntries)..where((t) => t.id.equals(entryId))).getSingle();
      expect(
        localEntry.isDeleted || localEntry.isVoided,
        isTrue,
        reason: 'Ledger entry should remain deleted/voided locally after pull',
      );

      await db.close();
    });

    test('5. C3 Audit: voidTransaction updates syncStatus to pending and updates updatedAt timestamp', () async {
      final db = AppDatabase(NativeDatabase.memory());
      final fakeRemote = StrictFakeRemoteSyncBackend();
      final syncEngine = SyncEngine(
        db: db,
        simulateSyncForTesting: true,
        fakeRemoteStore: fakeRemote,
      );

      final auditService = AuditService(db);
      final postingEngine = VoucherPostingEngine(db, auditService);
      const companyId = 'cmp_c3_test';
      const userId = 'usr_c3_test';

      final company = Company(
        id: companyId,
        name: 'C3 Audit Co',
        legalName: 'C3 Audit Co',
        mode: CompanyMode.expenseTracker,
        enabledModules: {AppModule.vouchers},
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final ledgerRepo = DriftLedgerRepository(
        db: db,
        postingEngine: postingEngine,
        syncEngine: syncEngine,
        currentCompanyId: companyId,
        currentUserId: userId,
      );
      await ledgerRepo.createCompany(company);
      await postingEngine.ensureCompanyAccounts(companyId);

      final expenseRepo = DriftExpenseRepository(
        db: db,
        auditService: auditService,
        postingEngine: postingEngine,
        syncEngine: syncEngine,
        currentCompanyId: companyId,
        currentUserId: userId,
      );

      final walletId = '${companyId}_${ExpenseTrackerDefaults.walletCashId}';
      final categoryId = '${companyId}_${ExpenseTrackerDefaults.groceriesId}';

      final voucher = await expenseRepo.addExpense(
        categoryAccountId: categoryId,
        walletAccountId: walletId,
        amountInCents: 20000,
        narration: 'Voucher for C3 void test',
      );

      // Simulate record having been previously synced to remote
      await (db.update(db.expenseTransactions)..where((t) => t.id.equals(voucher.id))).write(
        const ExpenseTransactionsCompanion(
          syncStatus: Value(SyncRecordStatus.synced),
        ),
      );

      final initialRow = await (db.select(db.expenseTransactions)..where((t) => t.id.equals(voucher.id))).getSingle();
      final initialUpdatedAt = initialRow.updatedAt;

      await Future.delayed(const Duration(seconds: 1, milliseconds: 100));

      await expenseRepo.voidTransaction(voucher.id);

      final voidedRow = await (db.select(db.expenseTransactions)..where((t) => t.id.equals(voucher.id))).getSingle();

      expect(
        voidedRow.syncStatus,
        equals(SyncRecordStatus.pending),
        reason: 'Transaction syncStatus should transition to pending upon voiding',
      );

      expect(
        voidedRow.updatedAt.isAfter(initialUpdatedAt),
        isTrue,
        reason: 'Transaction updatedAt timestamp should be updated when voided (before: $initialUpdatedAt, after: ${voidedRow.updatedAt})',
      );

      await db.close();
    });
  });
}
