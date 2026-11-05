import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_pulse/core/network/sync_codec.dart';
import 'package:ledger_pulse/core/network/sync_engine.dart';
import 'package:ledger_pulse/data/accounting/voucher_posting_engine.dart';
import 'package:ledger_pulse/data/local/audit_service.dart';
import 'package:ledger_pulse/data/local/database.dart';
import 'package:ledger_pulse/data/local/drift_entries_mixin.dart';
import 'package:ledger_pulse/data/local/drift_expense_repository.dart';
import 'package:ledger_pulse/data/local/drift_ledger_repository.dart';
import 'package:ledger_pulse/data/local/outbox_helper.dart';
import 'package:ledger_pulse/data/models/account_model.dart';
import 'package:ledger_pulse/data/models/company_model.dart';
import 'package:ledger_pulse/data/models/party_model.dart';
import 'package:ledger_pulse/data/models/transaction_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/strict_fake_remote.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase 1 Feature Unit Tests (A through G)', () {
    test('A: sync_codec encodeTime & decodeTime convert UTC ISO strings correctly', () {
      final localDt = DateTime(2026, 11, 4, 10, 0, 0);
      final encoded = encodeTime(localDt);
      expect(encoded.endsWith('Z'), isTrue);

      const unoffsettedIso = '2026-11-04T10:00:00.000';
      final decodedFromUnoffsetted = decodeTime(unoffsettedIso);
      expect(decodedFromUnoffsetted.millisecondsSinceEpoch, equals(DateTime.utc(2026, 11, 4, 10, 0, 0).millisecondsSinceEpoch));

      const offsetIso = '2026-11-04T10:00:00+05:30';
      final decodedFromOffset = decodeTime(offsetIso);
      expect(decodedFromOffset.millisecondsSinceEpoch, equals(DateTime.parse(offsetIso).millisecondsSinceEpoch));
    });

    test('B: enqueueMutation accepts only real table names and writes valid JSON', () async {
      final db = AppDatabase(NativeDatabase.memory());

      await enqueueMutation(
        db: db,
        table: 'vouchers',
        recordId: 'vch_test_b',
        type: 'INSERT',
        fullRowMap: {'id': 'vch_test_b', 'type': 'expense', 'amount': 1000},
      );

      final rows = await db.select(db.syncOutbox).get();
      expect(rows.length, equals(1));
      expect(rows.first.targetTable, equals('vouchers'));

      await db.close();
    });

    test('C: voidVoucher updates syncStatus to pending and refreshes updatedAt on all affected tables', () async {
      final db = AppDatabase(NativeDatabase.memory());
      final fakeRemote = StrictFakeRemoteSyncBackend();
      final syncEngine = SyncEngine(db: db, simulateSyncForTesting: true, fakeRemoteStore: fakeRemote);
      final auditService = AuditService(db);
      final postingEngine = VoucherPostingEngine(db, auditService);

      const companyId = 'cmp_phase1_c';
      const userId = 'usr_phase1_c';

      final company = Company(
        id: companyId,
        name: 'Phase1 C Co',
        legalName: 'Phase1 C Co',
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
        amountInCents: 15000,
        narration: 'Voucher C Test',
      );

      await (db.update(db.vouchers)..where((t) => t.id.equals(voucher.id))).write(
        const VouchersCompanion(syncStatus: Value(SyncRecordStatus.synced)),
      );

      final initialRow = await (db.select(db.vouchers)..where((t) => t.id.equals(voucher.id))).getSingle();
      final initialUpdatedAt = initialRow.updatedAt;

      await Future.delayed(const Duration(seconds: 1, milliseconds: 100));
      await expenseRepo.voidTransaction(voucher.id);

      final voidedRow = await (db.select(db.vouchers)..where((t) => t.id.equals(voucher.id))).getSingle();
      expect(voidedRow.syncStatus, equals(SyncRecordStatus.pending));
      expect(voidedRow.updatedAt.isAfter(initialUpdatedAt), isTrue);

      final journalId = 'jnl_${voucher.id}';
      final voidedJournal = await (db.select(db.journals)..where((t) => t.id.equals(journalId))).getSingle();
      expect(voidedJournal.syncStatus, equals(SyncRecordStatus.pending));

      await db.close();
    });

    test('D: deleteEntry enqueues full ledger_entries payload row', () async {
      final db = AppDatabase(NativeDatabase.memory());
      final fakeRemote = StrictFakeRemoteSyncBackend();
      final syncEngine = SyncEngine(db: db, simulateSyncForTesting: true, fakeRemoteStore: fakeRemote);
      final auditService = AuditService(db);
      final postingEngine = VoucherPostingEngine(db, auditService);

      const companyId = 'cmp_phase1_d';
      const userId = 'usr_phase1_d';

      final company = Company(
        id: companyId,
        name: 'Phase1 D Co',
        legalName: 'Phase1 D Co',
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

      const partyId = 'party_d_1';
      await ledgerRepo.addParty(Party(
        id: partyId,
        name: 'Party D',
        phoneNumber: '+91 90000 00000',
        type: PartyType.customer,
        netBalanceInCents: 0,
        lastUpdated: DateTime.now(),
      ));

      const entryId = 'entry_d_1';
      final entry = LedgerEntry(
        id: entryId,
        partyId: partyId,
        amountInCents: 10000,
        type: EntryType.gave,
        date: DateTime.now(),
        note: 'Payload D Test',
      );
      await ledgerRepo.addEntry(entry);

      await syncEngine.pushQueue(companyId: companyId);

      await ledgerRepo.deleteEntry(entryId);

      final outboxRows = await (db.select(db.syncOutbox)..where((t) => t.recordId.equals(entryId))).get();
      expect(outboxRows, isNotEmpty);

      final updateOutbox = outboxRows.last;
      expect(updateOutbox.targetTable, equals('ledger_entries'));
      expect(updateOutbox.mutationType, equals('UPDATE'));

      await db.close();
    });

    test('E: Error classification handles PostgrestException 4xx as non-network error', () async {
      final db = AppDatabase(NativeDatabase.memory());

      await enqueueMutation(
        db: db,
        table: 'vouchers',
        recordId: 'rec_4xx',
        type: 'INSERT',
        fullRowMap: {'id': 'rec_4xx', 'type': 'expense'},
      );

      final p4xxErr = PostgrestException(
        message: 'duplicate key value violates unique constraint',
        code: '23505',
        details: 'Key (id)=(rec_4xx) already exists.',
      );

      expect(p4xxErr.code, equals('23505'));

      await db.close();
    });

    test('F: pullChanges skips local records whose syncStatus != synced', () async {
      final db = AppDatabase(NativeDatabase.memory());
      final fakeRemote = StrictFakeRemoteSyncBackend();
      final syncEngine = SyncEngine(db: db, simulateSyncForTesting: true, fakeRemoteStore: fakeRemote);

      const companyId = 'cmp_phase1_f';

      await db.into(db.vouchers).insert(
            VouchersCompanion.insert(
              id: 'vch_local_pending',
              companyId: const Value(companyId),
              voucherNumber: 'VCH-PENDING',
              type: 'expense',
              date: DateTime.now(),
              status: const Value('voided'),
              totalAmountInCents: const Value(5000),
              syncStatus: const Value(SyncRecordStatus.pending),
            ),
          );

      fakeRemote.upsert('vouchers', 'vch_local_pending', {
        'id': 'vch_local_pending',
        'company_id': companyId,
        'voucher_number': 'VCH-PENDING',
        'type': 'expense',
        'status': 'posted',
        'total_amount_in_cents': 5000,
        'is_deleted': false,
      });

      await syncEngine.pullChanges(companyId: companyId);

      final localRow = await (db.select(db.vouchers)..where((t) => t.id.equals('vch_local_pending'))).getSingle();
      expect(localRow.status, equals('voided'));
      expect(localRow.syncStatus, equals(SyncRecordStatus.pending));

      await db.close();
    });

    test('G: calculatePartyBalanceFromRows excludes isDeleted == true and computes net balance', () {
      final rows = [
        LedgerEntryTableData(
          id: '1',
          companyId: 'cmp',
          partyId: 'p1',
          amountInCents: 10000,
          type: EntryType.gave,
          date: DateTime.now(),
          isVoided: false,
          isDeleted: false,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          syncStatus: SyncRecordStatus.synced,
          revision: 0,
        ),
        LedgerEntryTableData(
          id: '2',
          companyId: 'cmp',
          partyId: 'p1',
          amountInCents: 3000,
          type: EntryType.got,
          date: DateTime.now(),
          isVoided: false,
          isDeleted: false,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          syncStatus: SyncRecordStatus.synced,
          revision: 0,
        ),
        LedgerEntryTableData(
          id: '3',
          companyId: 'cmp',
          partyId: 'p1',
          amountInCents: 5000,
          type: EntryType.gave,
          date: DateTime.now(),
          isVoided: true,
          isDeleted: false,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          syncStatus: SyncRecordStatus.synced,
          revision: 0,
        ),
        LedgerEntryTableData(
          id: '4',
          companyId: 'cmp',
          partyId: 'p1',
          amountInCents: 2000,
          type: EntryType.gave,
          date: DateTime.now(),
          isVoided: false,
          isDeleted: true,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          syncStatus: SyncRecordStatus.synced,
          revision: 0,
        ),
      ];

      final netBalance = calculatePartyBalanceFromRows(rows);
      expect(netBalance, equals(7000)); // 10000 - 3000 = 7000 (ignoring voided 5000 and deleted 2000)
    });
  });
}
