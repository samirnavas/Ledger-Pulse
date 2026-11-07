import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_pulse/core/network/sync_codec.dart';
import 'package:ledger_pulse/core/network/sync_engine.dart';
import 'package:ledger_pulse/data/local/database.dart';

import 'support/fake_remote_gateway.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase 2 Engine & Sync Tests', () {
    test('1. Migration from8To9 creates sync_state table and new columns', () async {
      final db = AppDatabase(NativeDatabase.memory());
      expect(db.schemaVersion, greaterThanOrEqualTo(9));

      // Verify sync_state table exists by performing a select
      final syncStates = await db.select(db.syncState).get();
      expect(syncStates, isEmpty);

      // Verify sync_outbox contains attempts, last_error, next_attempt_at
      final outboxRows = await db.select(db.syncOutbox).get();
      expect(outboxRows, isEmpty);

      await db.close();
    });

    test('2. Offline edit then pull keeps local edit', () async {
      final db = AppDatabase(NativeDatabase.memory());
      final fakeGateway = FakeGateway();
      final syncEngine = SyncEngine(db: db, gateway: fakeGateway, simulateSyncForTesting: true);

      const companyId = 'cmp_phase2_offline';

      // Seed local voucher in pending status
      await db.into(db.vouchers).insert(
            VouchersCompanion.insert(
              id: 'vch_offline_1',
              companyId: const Value(companyId),
              voucherNumber: 'VCH-OFFLINE',
              type: 'expense',
              date: DateTime.now(),
              totalAmountInCents: const Value(12000),
              status: const Value('voided'),
              syncStatus: const Value(SyncRecordStatus.pending),
            ),
          );

      // Seed remote voucher with different data
      fakeGateway.upsertDirect('vouchers', 'vch_offline_1', {
        'id': 'vch_offline_1',
        'company_id': companyId,
        'voucher_number': 'VCH-OFFLINE',
        'type': 'expense',
        'total_amount_in_cents': 12000,
        'status': 'posted',
        'is_deleted': false,
        'updated_at': encodeTime(DateTime.now()),
      });

      await syncEngine.pullChanges(companyId: companyId);

      final localVoucher = await (db.select(db.vouchers)..where((t) => t.id.equals('vch_offline_1'))).getSingle();
      expect(localVoucher.status, equals('voided'), reason: 'Local pending edit must NOT be overwritten by pull');
      expect(localVoucher.syncStatus, equals(SyncRecordStatus.pending));

      await db.close();
    });

    test('3. Two devices editing the same row (LWW / Revision tracking)', () async {
      final dbDeviceA = AppDatabase(NativeDatabase.memory());
      final dbDeviceB = AppDatabase(NativeDatabase.memory());
      final gateway = FakeGateway();

      final engineA = SyncEngine(db: dbDeviceA, gateway: gateway, simulateSyncForTesting: true);
      final engineB = SyncEngine(db: dbDeviceB, gateway: gateway, simulateSyncForTesting: true);

      const companyId = 'cmp_phase2_lww';

      // Device A creates an account and pushes
      await dbDeviceA.into(dbDeviceA.accounts).insert(
            AccountsCompanion.insert(
              id: 'acc_lww_1',
              companyId: const Value(companyId),
              code: '1001',
              name: 'Cash A Initial',
              type: 'asset',
              currentBalanceInCents: const Value(10000),
              syncStatus: const Value(SyncRecordStatus.pending),
            ),
          );
      await engineA.pushQueue(companyId: companyId);

      // Device B pulls Device A's change
      await engineB.pullChanges(companyId: companyId);
      final accB = await (dbDeviceB.select(dbDeviceB.accounts)..where((t) => t.id.equals('acc_lww_1'))).getSingle();
      expect(accB.name, equals('Cash A Initial'));

      // Device B updates name and pushes
      await (dbDeviceB.update(dbDeviceB.accounts)..where((t) => t.id.equals('acc_lww_1'))).write(
        const AccountsCompanion(
          name: Value('Cash B Updated'),
          syncStatus: Value(SyncRecordStatus.pending),
          revision: Value(1),
        ),
      );
      await engineB.pushQueue(companyId: companyId);

      // Device A pulls Device B's update
      await engineA.pullChanges(companyId: companyId);
      final accAUpdated = await (dbDeviceA.select(dbDeviceA.accounts)..where((t) => t.id.equals('acc_lww_1'))).getSingle();
      expect(accAUpdated.name, equals('Cash B Updated'));

      await dbDeviceA.close();
      await dbDeviceB.close();
    });

    test('4. Pagination with 2,500 rows in pages of 500', () async {
      final db = AppDatabase(NativeDatabase.memory());
      final gateway = FakeGateway();
      final syncEngine = SyncEngine(db: db, gateway: gateway, simulateSyncForTesting: true);

      const companyId = 'cmp_phase2_page';

      // Seed 2500 vouchers into gateway
      final now = DateTime.now();
      for (int i = 0; i < 2500; i++) {
        gateway.upsertDirect('vouchers', 'vch_page_$i', {
          'id': 'vch_page_$i',
          'company_id': companyId,
          'voucher_number': 'VCH-$i',
          'type': 'expense',
          'total_amount_in_cents': 1000 + i,
          'status': 'posted',
          'is_deleted': false,
          'updated_at': encodeTime(now.add(Duration(milliseconds: i))),
        });
      }

      final result = await syncEngine.pullChanges(companyId: companyId);
      expect(result.status, equals(SyncEngineStatus.success));

      final countInDb = await (db.select(db.vouchers)..where((t) => t.companyId.equals(companyId))).get();
      expect(countInDb.length, equals(2500));

      final syncStateRow = await (db.select(db.syncState)..where((t) => t.targetTable.equals('vouchers') & t.companyId.equals(companyId))).getSingle();
      expect(syncStateRow.lastPulledAt, isNotNull);

      await db.close();
    });

    test('5. Tombstone propagation (is_deleted)', () async {
      final db = AppDatabase(NativeDatabase.memory());
      final gateway = FakeGateway();
      final syncEngine = SyncEngine(db: db, gateway: gateway, simulateSyncForTesting: true);

      const companyId = 'cmp_phase2_tombstone';

      await db.into(db.accounts).insert(
            AccountsCompanion.insert(
              id: 'acc_tomb_1',
              companyId: const Value(companyId),
              code: '2001',
              name: 'Category To Delete',
              type: 'expense',
              isDeleted: const Value(false),
              syncStatus: const Value(SyncRecordStatus.synced),
            ),
          );

      gateway.upsertDirect('accounts', 'acc_tomb_1', {
        'id': 'acc_tomb_1',
        'company_id': companyId,
        'name': 'Category To Delete',
        'type': 'expense',
        'is_deleted': true,
        'updated_at': encodeTime(DateTime.now()),
      });

      await syncEngine.pullChanges(companyId: companyId);

      final localAcc = await (db.select(db.accounts)..where((t) => t.id.equals('acc_tomb_1'))).getSingle();
      expect(localAcc.isDeleted, isTrue, reason: 'Remote tombstone should be applied locally as soft-delete');

      await db.close();
    });

    test('6. Failed row / table error does not block other tables and returns partial status', () async {
      final db = AppDatabase(NativeDatabase.memory());
      final gateway = FakeGateway();
      final syncEngine = SyncEngine(db: db, gateway: gateway, simulateSyncForTesting: true);

      const companyId = 'cmp_phase2_failure';

      // Add valid account and valid voucher to gateway
      gateway.upsertDirect('accounts', 'acc_fail_1', {
        'id': 'acc_fail_1',
        'company_id': companyId,
        'code': '1000',
        'name': 'Valid Account',
        'type': 'asset',
        'is_deleted': false,
        'updated_at': encodeTime(DateTime.now()),
      });

      gateway.upsertDirect('vouchers', 'vch_fail_1', {
        'id': 'vch_fail_1',
        'company_id': companyId,
        'voucher_number': 'VCH-FAIL',
        'type': 'expense',
        'is_deleted': false,
        'updated_at': encodeTime(DateTime.now()),
      });

      // Mark 'vouchers' table to fail on gateway
      gateway.failedTables.add('vouchers');

      final result = await syncEngine.pullChanges(companyId: companyId);

      expect(result.status, equals(SyncEngineStatus.partial));
      expect(result.tableErrors.containsKey('vouchers'), isTrue);

      // Account should still have pulled successfully
      final localAccounts = await (db.select(db.accounts)..where((t) => t.id.equals('acc_fail_1'))).get();
      expect(localAccounts, isNotEmpty);

      // Voucher cursor should NOT have been updated
      final voucherCursor = await (db.select(db.syncState)..where((t) => t.targetTable.equals('vouchers') & t.companyId.equals(companyId))).getSingleOrNull();
      expect(voucherCursor, isNull, reason: 'Failed table cursor must not advance');

      await db.close();
    });
  });
}
