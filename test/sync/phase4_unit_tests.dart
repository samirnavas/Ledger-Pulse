import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_pulse/core/network/sync_engine.dart';
import 'package:ledger_pulse/data/accounting/voucher_posting_engine.dart';
import 'package:ledger_pulse/data/local/audit_service.dart';
import 'package:ledger_pulse/data/local/database.dart';
import 'package:ledger_pulse/data/local/drift_expense_repository.dart';
import 'package:ledger_pulse/data/local/drift_ledger_repository.dart';
import 'package:ledger_pulse/data/models/company_model.dart';
import 'package:ledger_pulse/data/models/party_model.dart';

import 'support/fake_remote_gateway.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase 4 Hardening & Schema v10 Tests', () {
    test('1. Schema v10 contains kind column, indexes, and recomputeAllBalances works', () async {
      final db = AppDatabase(NativeDatabase.memory(), 'usr_v10_test');
      expect(db.schemaVersion, equals(10));

      final fakeGateway = FakeGateway();
      final syncEngine = SyncEngine(db: db, gateway: fakeGateway, simulateSyncForTesting: true);
      final auditService = AuditService(db);
      final postingEngine = VoucherPostingEngine(db, auditService);

      const companyId = 'cmp_v10_test';

      final ledgerRepo = DriftLedgerRepository(
        db: db,
        postingEngine: postingEngine,
        syncEngine: syncEngine,
        currentCompanyId: companyId,
        currentUserId: 'usr_v10_test',
      );

      await ledgerRepo.createCompany(Company(
        id: companyId,
        name: 'Hardened Company',
        legalName: 'Hardened Company',
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
        currentUserId: 'usr_v10_test',
      );

      final wallets = await expenseRepo.getWallets();
      expect(wallets, isNotEmpty);
      for (final w in wallets) {
        expect(w.kind, equals('wallet'));
      }

      final categories = await expenseRepo.getCategories();
      expect(categories, isNotEmpty);

      // Recompute all balances locally
      await ledgerRepo.recomputeAllBalances(companyId);

      syncEngine.dispose();
      await db.close();
    });

    test('2. Cached balances are excluded from sync payload to remote', () {
      final partyData = PartyTableData(
        id: 'p_sync_1',
        companyId: 'cmp_1',
        name: 'Sync Test Party',
        phoneNumber: '+91 90000 00000',
        type: PartyType.customer,
        netBalanceInCents: 50000,
        lastUpdated: DateTime.now(),
        isDeleted: false,
        updatedAt: DateTime.now(),
        syncStatus: SyncRecordStatus.pending,
        revision: 0,
      );

      final partyTable = SyncEngine.syncTables.firstWhere((t) => t.name == 'parties');
      final remoteMap = (partyTable.toRemote as dynamic)(partyData) as Map<String, dynamic>;

      expect(remoteMap.containsKey('net_balance_in_cents'), isFalse, reason: 'net_balance_in_cents must be excluded from sync payload');
      expect(remoteMap.containsKey('netBalanceInCents'), isFalse);
    });
  });
}
