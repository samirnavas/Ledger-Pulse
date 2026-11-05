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

  final isUtcMachine = DateTime.now().timeZoneOffset.inMinutes == 0;
  final skipReason = isUtcMachine
      ? 'Skipping timezone roundtrip test on 0 offset (UTC) machine'
      : null;

  group('Time Roundtrip Sync Tests', () {
    test(
      'add ledger entry and expense voucher at 10:00 IST (04:30 UTC), push, wipe, pull, assert instant',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        final fakeRemote = StrictFakeRemoteSyncBackend();
        final syncEngine = SyncEngine(
          db: db,
          simulateSyncForTesting: true,
          fakeRemoteStore: fakeRemote,
        );

        final auditService = AuditService(db);
        final postingEngine = VoucherPostingEngine(db, auditService);
        const companyId = 'cmp_time_test_1';
        const userId = 'usr_time_test_1';

        final company = Company(
          id: companyId,
          name: 'Time Test Co 1',
          legalName: 'Time Test Co 1',
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

        final partyId = 'party_time_1';
        await ledgerRepo.addParty(Party(
          id: partyId,
          name: 'Time Test Party 1',
          phoneNumber: '+91 90000 00000',
          type: PartyType.customer,
          netBalanceInCents: 0,
          lastUpdated: DateTime.now(),
        ));

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

        // Instant 1: 10:00 IST (04:30 UTC)
        final intended1 = DateTime.utc(2026, 11, 4, 4, 30).toLocal();

        final entry = LedgerEntry(
          id: 'entry_time_1',
          partyId: partyId,
          amountInCents: 15000,
          type: EntryType.gave,
          date: intended1,
          note: 'Instant 1 ledger entry',
        );
        await ledgerRepo.addEntry(entry);

        final voucher = await expenseRepo.addExpense(
          categoryAccountId: categoryId,
          walletAccountId: walletId,
          amountInCents: 25000,
          date: intended1,
          narration: 'Instant 1 expense voucher',
        );

        await syncEngine.pushQueue(companyId: companyId);

        await db.close();
        final freshDb = AppDatabase(NativeDatabase.memory());
        final freshSyncEngine = SyncEngine(
          db: freshDb,
          simulateSyncForTesting: true,
          fakeRemoteStore: fakeRemote,
        );

        await freshSyncEngine.pullChanges(companyId: companyId);

        final pulledEntries = await (freshDb.select(freshDb.ledgerEntries)
          ..where((t) => t.id.equals('entry_time_1'))).get();
        expect(pulledEntries.isNotEmpty, isTrue, reason: 'Ledger entry 1 should be pulled');
        final pulledEntry = pulledEntries.first;
        expect(
          pulledEntry.date.millisecondsSinceEpoch ~/ 1000,
          equals(intended1.millisecondsSinceEpoch ~/ 1000),
          reason: 'Ledger entry instant 1 (10:00 IST) should match original epoch seconds',
        );

        final pulledVouchers = await (freshDb.select(freshDb.vouchers)
          ..where((t) => t.id.equals(voucher.id))).get();
        expect(pulledVouchers.isNotEmpty, isTrue, reason: 'Expense voucher 1 should be pulled');
        final pulledVoucher = pulledVouchers.first;
        expect(
          pulledVoucher.date.millisecondsSinceEpoch ~/ 1000,
          equals(intended1.millisecondsSinceEpoch ~/ 1000),
          reason: 'Expense voucher instant 1 (10:00 IST) should match original epoch seconds',
        );

        await freshDb.close();
      },
      skip: skipReason,
    );

    test(
      'add ledger entry and expense voucher at 23:30 IST (18:00 UTC) for day/month rollover, push, wipe, pull, assert instant',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        final fakeRemote = StrictFakeRemoteSyncBackend();
        final syncEngine = SyncEngine(
          db: db,
          simulateSyncForTesting: true,
          fakeRemoteStore: fakeRemote,
        );

        final auditService = AuditService(db);
        final postingEngine = VoucherPostingEngine(db, auditService);
        const companyId = 'cmp_time_test_2';
        const userId = 'usr_time_test_2';

        final company = Company(
          id: companyId,
          name: 'Time Test Co 2',
          legalName: 'Time Test Co 2',
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

        final partyId = 'party_time_2';
        await ledgerRepo.addParty(Party(
          id: partyId,
          name: 'Time Test Party 2',
          phoneNumber: '+91 90000 00001',
          type: PartyType.customer,
          netBalanceInCents: 0,
          lastUpdated: DateTime.now(),
        ));

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

        // Instant 2: 23:30 IST (18:00 UTC)
        final intended2 = DateTime.utc(2026, 11, 4, 18, 0).toLocal();

        final entry = LedgerEntry(
          id: 'entry_time_2',
          partyId: partyId,
          amountInCents: 18000,
          type: EntryType.gave,
          date: intended2,
          note: 'Instant 2 ledger entry (rollover test)',
        );
        await ledgerRepo.addEntry(entry);

        final voucher = await expenseRepo.addExpense(
          categoryAccountId: categoryId,
          walletAccountId: walletId,
          amountInCents: 35000,
          date: intended2,
          narration: 'Instant 2 expense voucher (rollover test)',
        );

        await syncEngine.pushQueue(companyId: companyId);

        await db.close();
        final freshDb = AppDatabase(NativeDatabase.memory());
        final freshSyncEngine = SyncEngine(
          db: freshDb,
          simulateSyncForTesting: true,
          fakeRemoteStore: fakeRemote,
        );

        await freshSyncEngine.pullChanges(companyId: companyId);

        final pulledEntries = await (freshDb.select(freshDb.ledgerEntries)
          ..where((t) => t.id.equals('entry_time_2'))).get();
        expect(pulledEntries.isNotEmpty, isTrue, reason: 'Ledger entry 2 should be pulled');
        final pulledEntry = pulledEntries.first;
        expect(
          pulledEntry.date.millisecondsSinceEpoch ~/ 1000,
          equals(intended2.millisecondsSinceEpoch ~/ 1000),
          reason: 'Ledger entry instant 2 (23:30 IST) should match original epoch seconds',
        );

        final pulledVouchers = await (freshDb.select(freshDb.vouchers)
          ..where((t) => t.id.equals(voucher.id))).get();
        expect(pulledVouchers.isNotEmpty, isTrue, reason: 'Expense voucher 2 should be pulled');
        final pulledVoucher = pulledVouchers.first;
        expect(
          pulledVoucher.date.millisecondsSinceEpoch ~/ 1000,
          equals(intended2.millisecondsSinceEpoch ~/ 1000),
          reason: 'Expense voucher instant 2 (23:30 IST) should match original epoch seconds',
        );

        await freshDb.close();
      },
      skip: skipReason,
    );
  });
}
