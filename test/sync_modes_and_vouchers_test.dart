import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_pulse/core/network/sync_engine.dart';
import 'package:ledger_pulse/data/accounting/voucher_posting_engine.dart';
import 'package:ledger_pulse/data/local/audit_service.dart';
import 'package:ledger_pulse/data/local/database.dart';
import 'package:ledger_pulse/data/local/drift_ledger_repository.dart';
import 'package:ledger_pulse/data/local/drift_voucher_repository.dart';
import 'package:ledger_pulse/data/models/account_model.dart';
import 'package:ledger_pulse/data/models/company_model.dart';
import 'package:ledger_pulse/data/models/voucher_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Sync Architecture: Company Modes, Vouchers, Journals & Wipe-Restore', () {
    test('Push expense company with expense, income & transfer, wipe DB, pull & restore integrity', () async {
      // 1. Setup origin database and fake remote store
      final originDb = AppDatabase(NativeDatabase.memory());
      final fakeRemote = FakeRemoteSyncBackend();
      final originSyncEngine = SyncEngine(
        db: originDb,
        simulateSyncForTesting: true,
        fakeRemoteStore: fakeRemote,
      );

      final auditService = AuditService(originDb);
      final postingEngine = VoucherPostingEngine(originDb, auditService);
      const companyId = 'cmp_expense_sync_test';
      const userId = 'usr_sync_tester';

      final expenseCompany = Company(
        id: companyId,
        name: 'Personal Tracker Co',
        legalName: 'Personal Tracker Co',
        mode: CompanyMode.expenseTracker,
        enabledModules: {AppModule.vouchers, AppModule.budgets, AppModule.recurring},
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );

      final ledgerRepo1 = DriftLedgerRepository(
        db: originDb,
        postingEngine: postingEngine,
        syncEngine: originSyncEngine,
        currentCompanyId: companyId,
        currentUserId: userId,
      );
      await ledgerRepo1.createCompany(
        expenseCompany,
        initialWalletBalancesInCents: {
          ExpenseTrackerDefaults.walletCashId: 100000,
          ExpenseTrackerDefaults.walletBankId: 500000,
        },
      );

      final voucherRepo1 = DriftVoucherRepository(
        db: originDb,
        auditService: auditService,
        postingEngine: postingEngine,
        currentCompanyId: companyId,
        currentUserId: userId,
      );

      final cashWalletId = '${companyId}_${ExpenseTrackerDefaults.walletCashId}';
      final bankWalletId = '${companyId}_${ExpenseTrackerDefaults.walletBankId}';
      final groceriesCatId = '${companyId}_${ExpenseTrackerDefaults.groceriesId}';
      final salaryCatId = '${companyId}_${ExpenseTrackerDefaults.salaryId}';

      // 2. Add an Expense voucher: Groceries ₹250.00 (25,000 cents) from Cash
      final expVoucher = VoucherModel(
        id: 'vch_exp_sync_1',
        companyId: companyId,
        voucherNumber: 'EXP-0001',
        type: VoucherType.expense,
        date: DateTime(2026, 1, 15),
        totalAmountInCents: 25000,
        categoryAccountId: groceriesCatId,
        walletAccountId: cashWalletId,
        narration: 'Weekly groceries purchase',
        createdAt: DateTime(2026, 1, 15),
        updatedAt: DateTime(2026, 1, 15),
      );
      await voucherRepo1.createVoucher(expVoucher);

      // 3. Add an Income voucher: Consulting ₹10,000.00 (1,000,000 cents) into Bank
      final incVoucher = VoucherModel(
        id: 'vch_inc_sync_1',
        companyId: companyId,
        voucherNumber: 'INC-0001',
        type: VoucherType.income,
        date: DateTime(2026, 1, 16),
        totalAmountInCents: 1000000,
        categoryAccountId: salaryCatId,
        walletAccountId: bankWalletId,
        narration: 'Freelance consultation',
        createdAt: DateTime(2026, 1, 16),
        updatedAt: DateTime(2026, 1, 16),
      );
      await voucherRepo1.createVoucher(incVoucher);

      // 4. Add a Transfer voucher: Transfer ₹500.00 (50,000 cents) from Bank to Cash
      final trfVoucher = VoucherModel(
        id: 'vch_trf_sync_1',
        companyId: companyId,
        voucherNumber: 'TRF-0001',
        type: VoucherType.transfer,
        date: DateTime(2026, 1, 17),
        totalAmountInCents: 50000,
        walletAccountId: bankWalletId,
        toWalletAccountId: cashWalletId,
        narration: 'ATM withdrawal to cash wallet',
        createdAt: DateTime(2026, 1, 17),
        updatedAt: DateTime(2026, 1, 17),
      );
      await voucherRepo1.createVoucher(trfVoucher);

      // Verify origin balances before push:
      // Cash: 100,000 - 25,000 (spent) + 50,000 (transferred) = 125,000 cents
      // Bank: 500,000 + 1,000,000 (income) - 50,000 (transferred) = 1,450,000 cents
      final originCash = await ledgerRepo1.getAccountById(cashWalletId);
      final originBank = await ledgerRepo1.getAccountById(bankWalletId);
      expect(originCash.currentBalanceInCents, equals(125000));
      expect(originBank.currentBalanceInCents, equals(1450000));

      // 5. Push to fake remote
      final pushResult = await originSyncEngine.pushQueue(companyId: companyId);
      expect(pushResult.success, isTrue);
      expect(pushResult.itemsPushed, greaterThan(0));

      // Confirm outbox is emptied on origin
      final pendingCount = await originSyncEngine.getPendingCount();
      expect(pendingCount, equals(0));

      // Verify data exists in fake remote store
      expect(fakeRemote.getTableRows('companies').length, equals(1));
      expect(fakeRemote.getTableRows('accounts').length, greaterThanOrEqualTo(2));
      expect(fakeRemote.getTableRows('vouchers').length, equals(3));
      expect(fakeRemote.getTableRows('journals').length, greaterThanOrEqualTo(3));
      expect(fakeRemote.getTableRows('journal_lines').length, greaterThanOrEqualTo(6));

      // 6. WIPE: Close origin database completely
      await originDb.close();

      // 7. RESTORE: Initialize a brand new, empty local database
      final freshDb = AppDatabase(NativeDatabase.memory());
      final freshSyncEngine = SyncEngine(
        db: freshDb,
        simulateSyncForTesting: true,
        fakeRemoteStore: fakeRemote,
      );

      // Confirm freshDb has 0 companies, vouchers, accounts, journals
      final freshCompsBefore = await freshDb.select(freshDb.companies).get();
      expect(freshCompsBefore, isEmpty);

      // 8. PULL: Trigger pull on the clean device without specifying companyId (discovery mode)
      final pullResult = await freshSyncEngine.pullChanges();
      expect(pullResult.success, isTrue);
      expect(pullResult.itemsPulled, greaterThan(0));

      // 9. ASSERT RESTORED INTEGRITY
      final freshLedgerRepo = DriftLedgerRepository(
        db: freshDb,
        syncEngine: freshSyncEngine,
        currentCompanyId: companyId,
        currentUserId: userId,
      );

      // Verify restored company
      final allComps = await freshLedgerRepo.getCompanies();
      final restoredCompany = allComps.firstWhere((c) => c.id == companyId);
      expect(restoredCompany.name, equals('Personal Tracker Co'));
      expect(restoredCompany.mode, equals(CompanyMode.expenseTracker));
      expect(restoredCompany.enabledModules, containsAll([AppModule.vouchers, AppModule.budgets, AppModule.recurring]));

      // Verify restored vouchers
      final restoredVouchers = await (freshDb.select(freshDb.vouchers)..where((t) => t.companyId.equals(companyId))).get();
      expect(restoredVouchers.length, equals(3));
      final voucherTypes = restoredVouchers.map((v) => v.type).toSet();
      expect(voucherTypes, containsAll(['expense', 'income', 'transfer']));

      // Verify restored journals & balanced double-entry (Dr == Cr)
      final restoredJournals = await freshLedgerRepo.getJournals();
      expect(restoredJournals.length, greaterThanOrEqualTo(3));

      int totalDebits = 0;
      int totalCredits = 0;
      for (final j in restoredJournals) {
        expect(j.isBalanced, isTrue, reason: 'Journal ${j.journalNumber} must be balanced (Dr == Cr)');
        for (final line in j.lines) {
          totalDebits += line.debitInCents;
          totalCredits += line.creditInCents;
        }
      }
      expect(totalDebits, equals(totalCredits), reason: 'Total debits across all journals must equal total credits');

      // Verify restored wallet balances
      final restoredCash = await freshLedgerRepo.getAccountById(cashWalletId);
      final restoredBank = await freshLedgerRepo.getAccountById(bankWalletId);
      expect(restoredCash.currentBalanceInCents, equals(125000));
      expect(restoredBank.currentBalanceInCents, equals(1450000));

      await freshDb.close();
    });

    test('Old-style company row without mode or enabled_modules pulls as ledger company with all modules', () async {
      final fakeRemote = FakeRemoteSyncBackend();

      // Seed legacy row in fake remote (no mode, no enabled_modules)
      fakeRemote.upsert('companies', 'cmp_legacy_001', {
        'id': 'cmp_legacy_001',
        'name': 'Legacy Retailers',
        'legal_name': 'Legacy Retailers Pvt Ltd',
        'currency_code': 'INR',
        'is_cloud_sync_enabled': true,
        'is_active': true,
        'is_deleted': false,
        'created_at': DateTime(2025, 6, 1).toIso8601String(),
        'updated_at': DateTime(2025, 6, 1).toIso8601String(),
        // mode and enabled_modules are omitted / null
      });

      final db = AppDatabase(NativeDatabase.memory());
      final syncEngine = SyncEngine(
        db: db,
        simulateSyncForTesting: true,
        fakeRemoteStore: fakeRemote,
      );

      final pullResult = await syncEngine.pullChanges();
      expect(pullResult.success, isTrue);

      final repo = DriftLedgerRepository(
        db: db,
        syncEngine: syncEngine,
        currentCompanyId: 'cmp_legacy_001',
      );

      final allComps = await repo.getCompanies();
      final pulledCompany = allComps.firstWhere((c) => c.id == 'cmp_legacy_001');
      expect(pulledCompany.mode, equals(CompanyMode.ledger));
      expect(pulledCompany.enabledModules.length, equals(AppModule.allModules.length));
      expect(pulledCompany.enabledModules, containsAll(AppModule.allModules));

      await db.close();
    });

    test('Repair previously failed rows (syncStatus = error) resets to pending on sync', () async {
      final db = AppDatabase(NativeDatabase.memory());
      final syncEngine = SyncEngine(db: db, simulateSyncForTesting: true);

      // Insert voucher, budget, recurring rule marked with error status
      await db.into(db.vouchers).insert(
        VouchersCompanion.insert(
          id: 'vch_err_1',
          companyId: const Value('cmp_repair_test'),
          voucherNumber: 'EXP-ERR',
          type: 'expense',
          date: DateTime.now(),
          syncStatus: const Value(SyncRecordStatus.error),
        ),
      );
      await db.into(db.budgets).insert(
        BudgetsCompanion.insert(
          id: 'bdg_err_1',
          companyId: const Value('cmp_repair_test'),
          categoryAccountId: 'acc_cat',
          periodType: 'monthly',
          amountInCents: 5000,
          startDate: DateTime.now(),
          syncStatus: const Value(SyncRecordStatus.error),
        ),
      );
      await db.into(db.recurringRules).insert(
        RecurringRulesCompanion.insert(
          id: 'rcr_err_1',
          companyId: const Value('cmp_repair_test'),
          templateJson: '{}',
          intervalType: 'monthly',
          nextRunDate: DateTime.now(),
          syncStatus: const Value(SyncRecordStatus.error),
        ),
      );

      // Verify they are initially error
      final v1 = await (db.select(db.vouchers)..where((t) => t.id.equals('vch_err_1'))).getSingle();
      expect(v1.syncStatus, equals(SyncRecordStatus.error));

      // Trigger pushQueue
      await syncEngine.pushQueue(companyId: 'cmp_repair_test');

      // Verify they were reset to pending and synced
      final v2 = await (db.select(db.vouchers)..where((t) => t.id.equals('vch_err_1'))).getSingle();
      final b2 = await (db.select(db.budgets)..where((t) => t.id.equals('bdg_err_1'))).getSingle();
      final r2 = await (db.select(db.recurringRules)..where((t) => t.id.equals('rcr_err_1'))).getSingle();

      expect(v2.syncStatus, equals(SyncRecordStatus.synced));
      expect(b2.syncStatus, equals(SyncRecordStatus.synced));
      expect(r2.syncStatus, equals(SyncRecordStatus.synced));

      await db.close();
    });
  });
}
