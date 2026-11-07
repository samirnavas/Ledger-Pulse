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

import 'support/fake_remote_gateway.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase 6 Accounting Behavior Tests', () {
    test('1. Add, edit, void, and restore expense across wallets A and B', () async {
      final db = AppDatabase(NativeDatabase.memory(), 'usr_phase6_1');
      final fakeGateway = FakeGateway();
      final syncEngine = SyncEngine(db: db, gateway: fakeGateway, simulateSyncForTesting: true);
      final auditService = AuditService(db);
      final postingEngine = VoucherPostingEngine(db, auditService);

      const companyId = 'cmp_phase6_vch';

      final ledgerRepo = DriftLedgerRepository(
        db: db,
        postingEngine: postingEngine,
        syncEngine: syncEngine,
        currentCompanyId: companyId,
        currentUserId: 'usr_phase6_1',
      );

      await ledgerRepo.createCompany(Company(
        id: companyId,
        name: 'Phase 6 Co',
        legalName: 'Phase 6 Co',
        mode: CompanyMode.expenseTracker,
        enabledModules: {AppModule.vouchers},
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));

      final expenseRepo = DriftExpenseRepository(
        db: db,
        auditService: auditService,
        postingEngine: postingEngine,
        syncEngine: syncEngine,
        currentCompanyId: companyId,
        currentUserId: 'usr_phase6_1',
      );

      final walletA = await expenseRepo.createWallet(name: 'Wallet A', type: AccountType.asset);
      await expenseRepo.createWallet(name: 'Wallet B', type: AccountType.asset);
      final category = await expenseRepo.createCategory(name: 'Groceries', type: AccountType.expense);

      // 1. Add expense on Wallet A
      final voucher = await expenseRepo.addExpense(
        categoryAccountId: category.id,
        walletAccountId: walletA.id,
        amountInCents: 5000,
        narration: 'Groceries on A',
      );

      var summary = await expenseRepo.getMonthSummary(DateTime.now());
      expect(summary.walletBalancesInCents[walletA.id], equals(-5000));

      // 2. Void expense
      await expenseRepo.voidTransaction(voucher.id);
      summary = await expenseRepo.getMonthSummary(DateTime.now());
      expect(summary.walletBalancesInCents[walletA.id], equals(0));

      // 3. Restore expense
      await postingEngine.restoreVoucher(voucherId: voucher.id, companyId: companyId, userId: 'usr_phase6_1');
      summary = await expenseRepo.getMonthSummary(DateTime.now());
      expect(summary.walletBalancesInCents[walletA.id], equals(-5000));

      syncEngine.dispose();
      await db.close();
    });

    test('2. Wallet-to-wallet transfer correctly moves balance from A to B', () async {
      final db = AppDatabase(NativeDatabase.memory(), 'usr_phase6_2');
      final fakeGateway = FakeGateway();
      final syncEngine = SyncEngine(db: db, gateway: fakeGateway, simulateSyncForTesting: true);
      final auditService = AuditService(db);
      final postingEngine = VoucherPostingEngine(db, auditService);

      const companyId = 'cmp_phase6_xfer';

      final ledgerRepo = DriftLedgerRepository(
        db: db,
        postingEngine: postingEngine,
        syncEngine: syncEngine,
        currentCompanyId: companyId,
        currentUserId: 'usr_phase6_2',
      );

      await ledgerRepo.createCompany(Company(
        id: companyId,
        name: 'Phase 6 Xfer Co',
        legalName: 'Phase 6 Xfer Co',
        mode: CompanyMode.expenseTracker,
        enabledModules: {AppModule.vouchers},
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));

      final expenseRepo = DriftExpenseRepository(
        db: db,
        auditService: auditService,
        postingEngine: postingEngine,
        syncEngine: syncEngine,
        currentCompanyId: companyId,
        currentUserId: 'usr_phase6_2',
      );

      final walletA = await expenseRepo.createWallet(name: 'Wallet Cash', type: AccountType.asset, openingBalanceInCents: 100000);
      final walletB = await expenseRepo.createWallet(name: 'Wallet Bank', type: AccountType.asset, openingBalanceInCents: 50000);

      // Transfer 20,000 cents from Cash (A) to Bank (B)
      await expenseRepo.addTransfer(
        walletAccountId: walletA.id,
        toWalletAccountId: walletB.id,
        amountInCents: 20000,
        narration: 'Deposit cash to bank',
      );

      final summary = await expenseRepo.getMonthSummary(DateTime.now());
      expect(summary.walletBalancesInCents[walletA.id], equals(80000));
      expect(summary.walletBalancesInCents[walletB.id], equals(70000));

      syncEngine.dispose();
      await db.close();
    });

    test('3. Ledger gave/got then void -> trial balance net effect equals zero', () async {
      final db = AppDatabase(NativeDatabase.memory(), 'usr_phase6_3');
      final fakeGateway = FakeGateway();
      final syncEngine = SyncEngine(db: db, gateway: fakeGateway, simulateSyncForTesting: true);
      final auditService = AuditService(db);
      final postingEngine = VoucherPostingEngine(db, auditService);

      const companyId = 'cmp_phase6_ledger';

      final ledgerRepo = DriftLedgerRepository(
        db: db,
        postingEngine: postingEngine,
        syncEngine: syncEngine,
        currentCompanyId: companyId,
        currentUserId: 'usr_phase6_3',
      );

      await ledgerRepo.createCompany(Company(
        id: companyId,
        name: 'Phase 6 Trial Balance Co',
        legalName: 'Phase 6 Trial Balance Co',
        mode: CompanyMode.ledger,
        enabledModules: {AppModule.vouchers},
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));

      await ledgerRepo.addParty(Party(
        id: 'party_tb_1',
        name: 'TB Party',
        phoneNumber: '+91 90000 00000',
        type: PartyType.customer,
        netBalanceInCents: 0,
        lastUpdated: DateTime.now(),
      ));

      final entryId = 'entry_tb_1';
      await ledgerRepo.addEntry(LedgerEntry(
        id: entryId,
        partyId: 'party_tb_1',
        amountInCents: 25000,
        type: EntryType.gave,
        date: DateTime.now(),
        note: 'Gave entry for trial balance test',
      ));

      // Balance before delete/void
      var party = await ledgerRepo.getPartyById('party_tb_1');
      expect(party.netBalanceInCents, equals(25000));

      // Void/Delete entry
      await ledgerRepo.deleteEntry(entryId);

      // Balance after void must equal 0
      party = await ledgerRepo.getPartyById('party_tb_1');
      expect(party.netBalanceInCents, equals(0));

      syncEngine.dispose();
      await db.close();
    });
  });
}
