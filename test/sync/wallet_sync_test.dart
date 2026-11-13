import 'dart:convert';
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

import 'support/strict_fake_remote.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Wallet & Category Sync Tests', () {
    test('create a wallet and a category, push, and assert FakeRemoteSyncBackend has them in accounts table', () async {
      final db = AppDatabase(NativeDatabase.memory());
      final fakeRemote = StrictFakeRemoteSyncBackend();
      final syncEngine = SyncEngine(
        db: db,
        simulateSyncForTesting: true,
        fakeRemoteStore: fakeRemote,
      );

      final auditService = AuditService(db);
      final postingEngine = VoucherPostingEngine(db, auditService);
      const companyId = 'cmp_wallet_sync_test';
      const userId = 'usr_wallet_sync_test';

      final company = Company(
        id: companyId,
        name: 'Wallet Sync Test Co',
        legalName: 'Wallet Sync Test Co',
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

      // Create wallet and category
      final wallet = await expenseRepo.createWallet(name: 'HDFC Savings Wallet', type: AccountType.asset);
      final category = await expenseRepo.createCategory(name: 'Dining Out Category', type: AccountType.expense);

      // Inspect outbox state after wallet & category creation
      final outboxRows = await (db.select(db.syncOutbox)).get();
      final outboxSummary = outboxRows.map((r) {
        bool decodes = false;
        try {
          jsonDecode(r.payload);
          decodes = true;
        } catch (_) {
          decodes = false;
        }
        return '(targetTable: ${r.targetTable}, recordId: ${r.recordId}, decodesJson: $decodes)';
      }).join(', ');

      // Push outbox queue to fake remote backend
      final pushResult = await syncEngine.pushQueue(companyId: companyId);
      expect(pushResult.success, isTrue);

      // Query exp_wallets and exp_categories from FakeRemoteSyncBackend
      final remoteWallets = fakeRemote.getTableRows('exp_wallets', companyId: companyId);
      final remoteCategories = fakeRemote.getTableRows('exp_categories', companyId: companyId);
      final remoteAccounts = fakeRemote.getTableRows('accounts', companyId: companyId);

      final walletRow = (remoteWallets.isNotEmpty ? remoteWallets : remoteAccounts).firstWhere(
        (r) => r['id'] == wallet.id,
        orElse: () => <String, dynamic>{},
      );
      expect(
        walletRow,
        isNotEmpty,
        reason: 'FakeRemoteSyncBackend should contain created wallet in "exp_wallets" table. Outbox actual rows after creation: [$outboxSummary]',
      );

      final categoryRow = (remoteCategories.isNotEmpty ? remoteCategories : remoteAccounts).firstWhere(
        (r) => r['id'] == category.id,
        orElse: () => <String, dynamic>{},
      );
      expect(
        categoryRow,
        isNotEmpty,
        reason: 'FakeRemoteSyncBackend should contain created category in "exp_categories" table. Outbox actual rows after creation: [$outboxSummary]',
      );

      await db.close();
    });
  });
}
