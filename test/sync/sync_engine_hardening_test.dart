import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_pulse/core/network/sync_engine.dart';
import 'package:ledger_pulse/data/local/database.dart';
import 'package:ledger_pulse/data/local/outbox_helper.dart';
import 'package:ledger_pulse/data/models/party_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import 'support/fake_remote_gateway.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late FakeGateway gateway;
  late SyncEngine syncEngine;
  const testCompanyId = 'cmp_sync_hardening_test';
  const testUserId = 'usr_sync_hardening_test';

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    gateway = FakeGateway();
    syncEngine = SyncEngine(
      db: db,
      fakeRemoteStore: gateway,
      simulateSyncForTesting: true,
      activeUserId: testUserId,
    );

    // Seed test company
    await db.into(db.companies).insert(
      CompaniesCompanion(
        id: const drift.Value(testCompanyId),
        name: const drift.Value('Sync Hardening Co'),
        legalName: const drift.Value('Sync Hardening Co Ltd'),
        currencyCode: const drift.Value('INR'),
        ownerId: const drift.Value(testUserId),
        syncStatus: const drift.Value(SyncRecordStatus.synced),
      ),
    );
  });

  tearDown(() async {
    syncEngine.dispose();
    await db.close();
  });

  group('SyncEngine Hardening & Verification Suite (Prompt 6)', () {
    // 1. Unsynced local create -> outbox -> successful upload -> marked synced
    test('1. Unsynced local create -> outbox -> successful upload -> marked synced', () async {
      await db.into(db.vouchers).insert(
        VouchersCompanion(
          id: const drift.Value('v_local_1'),
          companyId: const drift.Value(testCompanyId),
          voucherNumber: const drift.Value('V-001'),
          type: const drift.Value('expense'),
          date: drift.Value(DateTime.now()),
          status: const drift.Value('draft'),
          paymentMode: const drift.Value('cash'),
          subtotalInCents: const drift.Value(5000),
          taxInCents: const drift.Value(0),
          discountInCents: const drift.Value(0),
          totalAmountInCents: const drift.Value(5000),
          syncStatus: const drift.Value(SyncRecordStatus.pending),
        ),
      );

      final result = await syncEngine.pushQueue(companyId: testCompanyId);

      expect(result.status, SyncEngineStatus.success);
      expect(result.pushedCount, greaterThanOrEqualTo(1));
      expect(gateway.tables['vouchers']?['v_local_1'], isNotNull);

      final localVoucher = await (db.select(db.vouchers)..where((t) => t.id.equals('v_local_1'))).getSingle();
      expect(localVoucher.syncStatus, SyncRecordStatus.synced);
    });

    // 2. Unsynced local update -> outbox -> successful upload -> marked synced
    test('2. Unsynced local update -> outbox -> successful upload -> marked synced', () async {
      await db.into(db.parties).insert(
        PartiesCompanion(
          id: const drift.Value('p_local_2'),
          companyId: const drift.Value(testCompanyId),
          name: const drift.Value('Original Party'),
          phoneNumber: const drift.Value('+919876543210'),
          type: const drift.Value(PartyType.customer),
          lastUpdated: drift.Value(DateTime.now()),
          syncStatus: const drift.Value(SyncRecordStatus.synced),
          revision: const drift.Value(1),
        ),
      );

      // Local update
      await (db.update(db.parties)..where((t) => t.id.equals('p_local_2'))).write(
        const PartiesCompanion(
          name: drift.Value('Updated Party Name'),
          revision: drift.Value(2),
          syncStatus: drift.Value(SyncRecordStatus.pending),
        ),
      );

      final result = await syncEngine.pushQueue(companyId: testCompanyId);

      expect(result.status, SyncEngineStatus.success);
      expect(gateway.tables['parties']?['p_local_2']?['name'], 'Updated Party Name');

      final localParty = await (db.select(db.parties)..where((t) => t.id.equals('p_local_2'))).getSingle();
      expect(localParty.syncStatus, SyncRecordStatus.synced);
    });

    // 3. Unsynced local soft delete -> outbox -> successful upload
    test('3. Unsynced local soft delete -> outbox -> successful upload', () async {
      await db.into(db.accounts).insert(
        const AccountsCompanion(
          id: drift.Value('acc_local_3'),
          companyId: drift.Value(testCompanyId),
          code: drift.Value('ACC003'),
          name: drift.Value('Account to Delete'),
          type: drift.Value('asset'),
          kind: drift.Value('other'),
          syncStatus: drift.Value(SyncRecordStatus.synced),
        ),
      );

      // Soft delete locally
      await (db.update(db.accounts)..where((t) => t.id.equals('acc_local_3'))).write(
        const AccountsCompanion(
          isDeleted: drift.Value(true),
          syncStatus: drift.Value(SyncRecordStatus.pending),
        ),
      );

      final result = await syncEngine.pushQueue(companyId: testCompanyId);

      expect(result.status, SyncEngineStatus.success);
      final remoteRow = gateway.tables['accounts']?['acc_local_3'];
      expect(remoteRow?['is_deleted'], isTrue);
    });

    // 4. Remote create -> pulled -> inserted into local Drift database
    test('4. Remote create -> pulled -> inserted into local Drift database', () async {
      gateway.upsertDirect('parties', 'p_remote_4', {
        'id': 'p_remote_4',
        'company_id': testCompanyId,
        'name': 'Remote Party',
        'phone_number': '+919999988888',
        'type': 'customer',
        'net_balance_in_cents': 0,
        'last_updated': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
        'is_deleted': false,
        'revision': 1,
      });

      final result = await syncEngine.pullChanges(companyId: testCompanyId);

      expect(result.status, SyncEngineStatus.success);
      final localParty = await (db.select(db.parties)..where((t) => t.id.equals('p_remote_4'))).getSingleOrNull();
      expect(localParty, isNotNull);
      expect(localParty!.name, 'Remote Party');
      expect(localParty.syncStatus, SyncRecordStatus.synced);
    });

    // 5. Remote update -> pulled -> updated in local Drift database
    test('5. Remote update -> pulled -> updated in local Drift database', () async {
      await db.into(db.parties).insert(
        PartiesCompanion(
          id: const drift.Value('p_remote_5'),
          companyId: const drift.Value(testCompanyId),
          name: const drift.Value('Old Local Name'),
          phoneNumber: const drift.Value('+919876543210'),
          type: const drift.Value(PartyType.customer),
          lastUpdated: drift.Value(DateTime.now()),
          syncStatus: const drift.Value(SyncRecordStatus.synced),
          updatedAt: drift.Value(DateTime.now().subtract(const Duration(minutes: 10))),
        ),
      );

      gateway.upsertDirect('parties', 'p_remote_5', {
        'id': 'p_remote_5',
        'company_id': testCompanyId,
        'name': 'New Remote Name',
        'phone_number': '+919876543210',
        'type': 'customer',
        'net_balance_in_cents': 0,
        'last_updated': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
        'is_deleted': false,
        'revision': 2,
      });

      final result = await syncEngine.pullChanges(companyId: testCompanyId);

      expect(result.status, SyncEngineStatus.success);
      final localParty = await (db.select(db.parties)..where((t) => t.id.equals('p_remote_5'))).getSingle();
      expect(localParty.name, 'New Remote Name');
    });

    // 6. Remote soft delete -> pulled -> marked deleted in local database
    test('6. Remote soft delete -> pulled -> marked deleted in local database', () async {
      await db.into(db.accounts).insert(
        const AccountsCompanion(
          id: drift.Value('acc_remote_6'),
          companyId: drift.Value(testCompanyId),
          code: drift.Value('ACC006'),
          name: drift.Value('Account Active Locally'),
          type: drift.Value('asset'),
          kind: drift.Value('other'),
          syncStatus: drift.Value(SyncRecordStatus.synced),
        ),
      );

      gateway.upsertDirect('accounts', 'acc_remote_6', {
        'id': 'acc_remote_6',
        'company_id': testCompanyId,
        'code': 'ACC006',
        'name': 'Account Active Locally',
        'type': 'asset',
        'kind': 'other',
        'is_deleted': true,
        'updated_at': DateTime.now().toIso8601String(),
        'revision': 2,
      });

      final result = await syncEngine.pullChanges(companyId: testCompanyId);

      expect(result.status, SyncEngineStatus.success);
      final localAcc = await (db.select(db.accounts)..where((t) => t.id.equals('acc_remote_6'))).getSingle();
      expect(localAcc.isDeleted, isTrue);
    });

    // 7. Concurrent edits: local pending edit preserved over remote change
    test('7. Concurrent edits: local pending edit preserved over remote change', () async {
      await db.into(db.vouchers).insert(
        VouchersCompanion(
          id: const drift.Value('v_conflict_7'),
          companyId: const drift.Value(testCompanyId),
          voucherNumber: const drift.Value('V-007'),
          type: const drift.Value('expense'),
          date: drift.Value(DateTime.now()),
          status: const drift.Value('draft'),
          paymentMode: const drift.Value('cash'),
          subtotalInCents: const drift.Value(1000),
          taxInCents: const drift.Value(0),
          discountInCents: const drift.Value(0),
          totalAmountInCents: const drift.Value(1000),
          narration: const drift.Value('Local Pending Narration'),
          syncStatus: const drift.Value(SyncRecordStatus.pending),
        ),
      );

      gateway.upsertDirect('vouchers', 'v_conflict_7', {
        'id': 'v_conflict_7',
        'company_id': testCompanyId,
        'voucher_number': 'V-007',
        'type': 'expense',
        'date': DateTime.now().toIso8601String(),
        'status': 'draft',
        'payment_mode': 'cash',
        'subtotal_in_cents': 9999,
        'total_amount_in_cents': 9999,
        'narration': 'Remote Clashing Narration',
        'updated_at': DateTime.now().toIso8601String(),
        'is_deleted': false,
        'revision': 5,
      });

      final result = await syncEngine.pullChanges(companyId: testCompanyId);

      expect(result.status, SyncEngineStatus.success);
      final localVoucher = await (db.select(db.vouchers)..where((t) => t.id.equals('v_conflict_7'))).getSingle();
      // Un-pushed local edit must be preserved!
      expect(localVoucher.narration, 'Local Pending Narration');
      expect(localVoucher.totalAmountInCents, 1000);
      expect(localVoucher.syncStatus, SyncRecordStatus.pending);
    });

    // 8. Clean remote update applied when local has no pending edits
    test('8. Clean remote update applied when local has no pending edits', () async {
      await db.into(db.vouchers).insert(
        VouchersCompanion(
          id: const drift.Value('v_clean_8'),
          companyId: const drift.Value(testCompanyId),
          voucherNumber: const drift.Value('V-008'),
          type: const drift.Value('expense'),
          date: drift.Value(DateTime.now()),
          status: const drift.Value('draft'),
          paymentMode: const drift.Value('cash'),
          subtotalInCents: const drift.Value(1000),
          taxInCents: const drift.Value(0),
          discountInCents: const drift.Value(0),
          totalAmountInCents: const drift.Value(1000),
          narration: const drift.Value('Original Clean Narration'),
          syncStatus: const drift.Value(SyncRecordStatus.synced),
        ),
      );

      gateway.upsertDirect('vouchers', 'v_clean_8', {
        'id': 'v_clean_8',
        'company_id': testCompanyId,
        'voucher_number': 'V-008',
        'type': 'expense',
        'date': DateTime.now().toIso8601String(),
        'status': 'draft',
        'payment_mode': 'cash',
        'subtotal_in_cents': 1000,
        'total_amount_in_cents': 1000,
        'narration': 'Updated Remote Narration',
        'updated_at': DateTime.now().toIso8601String(),
        'is_deleted': false,
        'revision': 2,
      });

      final result = await syncEngine.pullChanges(companyId: testCompanyId);

      expect(result.status, SyncEngineStatus.success);
      final localVoucher = await (db.select(db.vouchers)..where((t) => t.id.equals('v_clean_8'))).getSingle();
      expect(localVoucher.narration, 'Updated Remote Narration');
    });

    // 9. Foreign-key topological ordering: parent pushed before child
    test('9. Foreign-key topological ordering: parent pushed before child', () async {
      final pushOrder = <String>[];

      final orderedGateway = _OrderTrackingGateway(gateway, onUpsert: (table, id) {
        pushOrder.add(table);
      });

      final engine = SyncEngine(
        db: db,
        gateway: orderedGateway,
        simulateSyncForTesting: true,
        activeUserId: testUserId,
      );

      // Intentionally insert child (exp_transactions) with earlier createdAt in outbox
      // and parent (exp_wallets) with later createdAt in outbox
      await enqueueMutation(
        db: db,
        table: 'exp_transactions',
        recordId: 'tx_order_9',
        type: 'UPSERT',
        fullRowMap: {
          'id': 'tx_order_9',
          'profile_id': testCompanyId,
          'transaction_type': 'expense',
          'amount_in_cents': 500,
          'wallet_id': 'w_order_9',
          'transaction_date': DateTime.now().toIso8601String(),
        },
      );

      // Now enqueue parent (exp_wallets)
      await enqueueMutation(
        db: db,
        table: 'exp_wallets',
        recordId: 'w_order_9',
        type: 'UPSERT',
        fullRowMap: {
          'id': 'w_order_9',
          'profile_id': testCompanyId,
          'name': 'Wallet Parent',
          'wallet_type': 'cash',
          'currency_code': 'INR',
        },
      );

      final result = await engine.pushQueue(companyId: testCompanyId);

      expect(result.status, SyncEngineStatus.success);
      expect(pushOrder.indexOf('exp_wallets'), lessThan(pushOrder.indexOf('exp_transactions')),
          reason: 'Parent table exp_wallets MUST be pushed before child table exp_transactions');
    });

    // 10. Foreign-key topological ordering on pull: parent pulled before child
    test('10. Foreign-key topological ordering on pull: parent pulled before child', () {
      final walletIndex = SyncEngine.syncTables.indexWhere((t) => t.name == 'exp_wallets');
      final txIndex = SyncEngine.syncTables.indexWhere((t) => t.name == 'exp_transactions');
      final companyIndex = SyncEngine.syncTables.indexWhere((t) => t.name == 'companies');

      expect(companyIndex, lessThan(walletIndex), reason: 'Companies pulled before exp_wallets');
      expect(walletIndex, lessThan(txIndex), reason: 'exp_wallets pulled before exp_transactions');
    });

    // 11. Network failure -> retry with exponential backoff
    test('11. Network failure -> retry with exponential backoff', () async {
      await enqueueMutation(
        db: db,
        table: 'parties',
        recordId: 'p_net_fail_11',
        type: 'UPSERT',
        fullRowMap: {
          'id': 'p_net_fail_11',
          'company_id': testCompanyId,
          'name': 'Network Fail Party',
          'type': 'customer',
        },
      );

      gateway.simulateNetworkError = true;

      final result = await syncEngine.pushQueue(companyId: testCompanyId);

      expect(result.status, SyncEngineStatus.partial);
      final outboxItem = await (db.select(db.syncOutbox)..where((t) => t.recordId.equals('p_net_fail_11'))).getSingle();
      expect(outboxItem.attempts, 1);
      expect(outboxItem.nextAttemptAt, isNotNull);
      expect(outboxItem.lastError, contains('Simulated network error'));
    });

    // 12. Permanent error -> marked failed/error without endless retries
    test('12. Permanent error -> marked failed/error without endless retries', () async {
      await db.into(db.accounts).insert(
        const AccountsCompanion(
          id: drift.Value('acc_perm_err_12'),
          companyId: drift.Value(testCompanyId),
          code: drift.Value('ACC012'),
          name: drift.Value('Permanent Error Account'),
          type: drift.Value('asset'),
          kind: drift.Value('other'),
          syncStatus: drift.Value(SyncRecordStatus.pending),
        ),
      );

      final failingGateway = _CustomExceptionGateway(
        gateway,
        onUpsert: (table, row) {
          throw const PostgrestException(
            message: 'violates foreign key constraint "fk_accounts_company"',
            code: '23503',
          );
        },
      );

      final engine = SyncEngine(
        db: db,
        gateway: failingGateway,
        simulateSyncForTesting: true,
        activeUserId: testUserId,
      );

      final result = await engine.pushQueue(companyId: testCompanyId);

      expect(result.status, SyncEngineStatus.partial);
      final localAcc = await (db.select(db.accounts)..where((t) => t.id.equals('acc_perm_err_12'))).getSingle();
      expect(localAcc.syncStatus, SyncRecordStatus.error);
    });

    // 13. Partial batch: successful rows committed, failing rows reported
    test('13. Partial batch: successful rows committed, failing rows reported', () async {
      await enqueueMutation(
        db: db,
        table: 'parties',
        recordId: 'p_batch_ok_13',
        type: 'UPSERT',
        fullRowMap: {
          'id': 'p_batch_ok_13',
          'company_id': testCompanyId,
          'name': 'Batch OK Party',
          'type': 'customer',
        },
      );

      await enqueueMutation(
        db: db,
        table: 'vouchers',
        recordId: 'v_batch_fail_13',
        type: 'UPSERT',
        fullRowMap: {
          'id': 'v_batch_fail_13',
          'company_id': testCompanyId,
          'voucher_number': 'V-013',
        },
      );

      gateway.failedTables.add('vouchers');

      final result = await syncEngine.pushQueue(companyId: testCompanyId);

      expect(result.status, SyncEngineStatus.partial);
      expect(result.pushedCount, 1);
      expect(result.tableErrors.containsKey('vouchers'), isTrue);
      expect(gateway.tables['parties']?['p_batch_ok_13'], isNotNull);
    });

    // 14. Expense domain: exp_wallets synced correctly
    test('14. Expense domain: exp_wallets synced correctly', () async {
      await db.into(db.expenseWallets).insert(
        const ExpenseWalletsCompanion(
          id: drift.Value('w_exp_14'),
          profileId: drift.Value(testCompanyId),
          name: drift.Value('Main Cash Wallet'),
          walletType: drift.Value('cash'),
          currencyCode: drift.Value('INR'),
          startingBalanceInCents: drift.Value(10000),
          currentBalanceInCents: drift.Value(10000),
          syncStatus: drift.Value(SyncRecordStatus.pending),
        ),
      );

      final result = await syncEngine.pushQueue(companyId: testCompanyId);

      expect(result.status, SyncEngineStatus.success);
      final remoteWallet = gateway.tables['exp_wallets']?['w_exp_14'];
      expect(remoteWallet, isNotNull);
      expect(remoteWallet?['profile_id'], testCompanyId);
      expect(remoteWallet?['starting_balance_in_cents'], 10000);

      final localWallet = await (db.select(db.expenseWallets)..where((t) => t.id.equals('w_exp_14'))).getSingle();
      expect(localWallet.syncStatus, SyncRecordStatus.synced);
    });

    // 15. Expense domain: exp_categories synced correctly
    test('15. Expense domain: exp_categories synced correctly', () async {
      await db.into(db.expenseCategories).insert(
        const ExpenseCategoriesCompanion(
          id: drift.Value('cat_exp_15'),
          profileId: drift.Value(testCompanyId),
          name: drift.Value('Groceries'),
          categoryType: drift.Value('expense'),
          syncStatus: drift.Value(SyncRecordStatus.pending),
        ),
      );

      final result = await syncEngine.pushQueue(companyId: testCompanyId);

      expect(result.status, SyncEngineStatus.success);
      final remoteCat = gateway.tables['exp_categories']?['cat_exp_15'];
      expect(remoteCat, isNotNull);
      expect(remoteCat?['profile_id'], testCompanyId);
      expect(remoteCat?['name'], 'Groceries');

      final localCat = await (db.select(db.expenseCategories)..where((t) => t.id.equals('cat_exp_15'))).getSingle();
      expect(localCat.syncStatus, SyncRecordStatus.synced);
    });

    // 16. Expense domain: exp_transactions synced correctly and recalculates wallet balances
    test('16. Expense domain: exp_transactions synced correctly and recalculates wallet balances', () async {
      await db.into(db.expenseWallets).insert(
        const ExpenseWalletsCompanion(
          id: drift.Value('w_exp_16'),
          profileId: drift.Value(testCompanyId),
          name: drift.Value('Checking Wallet'),
          startingBalanceInCents: drift.Value(20000),
          currentBalanceInCents: drift.Value(20000),
          syncStatus: drift.Value(SyncRecordStatus.synced),
        ),
      );

      // Remote transaction of 5000 cents expense
      gateway.upsertDirect('exp_transactions', 'tx_exp_16', {
        'id': 'tx_exp_16',
        'profile_id': testCompanyId,
        'transaction_type': 'expense',
        'amount_in_cents': 5000,
        'wallet_id': 'w_exp_16',
        'transaction_date': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
        'is_deleted': false,
        'revision': 1,
      });

      final result = await syncEngine.pullChanges(companyId: testCompanyId);

      expect(result.status, SyncEngineStatus.success);
      final wallet = await (db.select(db.expenseWallets)..where((t) => t.id.equals('w_exp_16'))).getSingle();
      // 20000 starting - 5000 expense = 15000
      expect(wallet.currentBalanceInCents, 15000);
    });

    // 17. Expense domain: exp_budgets synced correctly
    test('17. Expense domain: exp_budgets synced correctly', () async {
      await db.into(db.expenseBudgets).insert(
        ExpenseBudgetsCompanion(
          id: const drift.Value('b_exp_17'),
          profileId: const drift.Value(testCompanyId),
          amountInCents: const drift.Value(50000),
          startDate: drift.Value(DateTime.now()),
          syncStatus: const drift.Value(SyncRecordStatus.pending),
        ),
      );

      final result = await syncEngine.pushQueue(companyId: testCompanyId);

      expect(result.status, SyncEngineStatus.success);
      final remoteBudget = gateway.tables['exp_budgets']?['b_exp_17'];
      expect(remoteBudget, isNotNull);
      expect(remoteBudget?['amount_in_cents'], 50000);

      final localBudget = await (db.select(db.expenseBudgets)..where((t) => t.id.equals('b_exp_17'))).getSingle();
      expect(localBudget.syncStatus, SyncRecordStatus.synced);
    });

    // 18. Expense domain: exp_recurring_rules synced correctly
    test('18. Expense domain: exp_recurring_rules synced correctly', () async {
      await db.into(db.expenseRecurringRules).insert(
        ExpenseRecurringRulesCompanion(
          id: const drift.Value('rec_exp_18'),
          profileId: const drift.Value(testCompanyId),
          templateJson: const drift.Value('{"desc":"Rent"}'),
          intervalType: const drift.Value('monthly'),
          nextRunDate: drift.Value(DateTime.now().add(const Duration(days: 30))),
          syncStatus: const drift.Value(SyncRecordStatus.pending),
        ),
      );

      final result = await syncEngine.pushQueue(companyId: testCompanyId);

      expect(result.status, SyncEngineStatus.success);
      final remoteRec = gateway.tables['exp_recurring_rules']?['rec_exp_18'];
      expect(remoteRec, isNotNull);
      expect(remoteRec?['template_json'], '{"desc":"Rent"}');

      final localRec = await (db.select(db.expenseRecurringRules)..where((t) => t.id.equals('rec_exp_18'))).getSingle();
      expect(localRec.syncStatus, SyncRecordStatus.synced);
    });

    // 19. Workspace isolation: remote queries scoped to active workspace/profile ID
    test('19. Workspace isolation: remote queries scoped to active workspace/profile ID', () async {
      const otherCompanyId = 'cmp_other_workspace_99';

      gateway.upsertDirect('parties', 'p_party_a', {
        'id': 'p_party_a',
        'company_id': testCompanyId,
        'name': 'Party Workspace A',
        'phone_number': '+911111111111',
        'type': 'customer',
        'updated_at': DateTime.now().toIso8601String(),
        'is_deleted': false,
        'revision': 1,
      });

      gateway.upsertDirect('parties', 'p_party_b', {
        'id': 'p_party_b',
        'company_id': otherCompanyId,
        'name': 'Party Workspace B',
        'phone_number': '+912222222222',
        'type': 'customer',
        'updated_at': DateTime.now().toIso8601String(),
        'is_deleted': false,
        'revision': 1,
      });

      final result = await syncEngine.pullChanges(companyId: testCompanyId);

      expect(result.status, SyncEngineStatus.success);
      final localPartyA = await (db.select(db.parties)..where((t) => t.id.equals('p_party_a'))).getSingleOrNull();
      final localPartyB = await (db.select(db.parties)..where((t) => t.id.equals('p_party_b'))).getSingleOrNull();

      expect(localPartyA, isNotNull);
      expect(localPartyB, isNull, reason: 'Records for other workspaces must never be pulled into active context');
    });

    // 20. User isolation: engine respects active user ID
    test('20. User isolation: engine respects active user ID', () async {
      await db.into(db.accounts).insert(
        const AccountsCompanion(
          id: drift.Value('acc_user_iso_20'),
          companyId: drift.Value(testCompanyId),
          code: drift.Value('ACC020'),
          name: drift.Value('Owner Scoped Account'),
          type: drift.Value('asset'),
          kind: drift.Value('other'),
          syncStatus: drift.Value(SyncRecordStatus.pending),
        ),
      );

      final result = await syncEngine.pushQueue(companyId: testCompanyId);

      expect(result.status, SyncEngineStatus.success);
      final remoteRow = gateway.tables['accounts']?['acc_user_iso_20'];
      expect(remoteRow?['owner_id'], testUserId);
    });

    // 21. In-flight cancellation on disposal: disposing engine halts in-flight operations safely
    test('21. In-flight cancellation on disposal: disposing engine halts in-flight operations safely', () async {
      syncEngine.dispose();

      // Executing syncAll after dispose must return safely without throwing unhandled exceptions
      final result = await syncEngine.syncAll(companyId: testCompanyId);

      expect(result.status, SyncEngineStatus.idle);
      expect(result.tableErrors.containsKey('sync'), isTrue);
    });

    // 22. Multi-table full sync (syncAll) produces expected SyncEngineStatus.success or partial
    test('22. Multi-table full sync (syncAll) produces expected SyncEngineStatus.success or partial', () async {
      // Clean syncAll produces success
      final successResult = await syncEngine.syncAll(companyId: testCompanyId);
      expect(successResult.status, SyncEngineStatus.success);

      // Now create a failing table
      gateway.failedTables.add('vouchers');
      await enqueueMutation(
        db: db,
        table: 'vouchers',
        recordId: 'v_syncall_fail',
        type: 'UPSERT',
        fullRowMap: {
          'id': 'v_syncall_fail',
          'company_id': testCompanyId,
          'voucher_number': 'V-999',
        },
      );

      // Also create a succeeding table
      await enqueueMutation(
        db: db,
        table: 'parties',
        recordId: 'p_syncall_ok',
        type: 'UPSERT',
        fullRowMap: {
          'id': 'p_syncall_ok',
          'company_id': testCompanyId,
          'name': 'SyncAll Success Party',
          'type': 'customer',
        },
      );

      final partialResult = await syncEngine.syncAll(companyId: testCompanyId);
      expect(partialResult.status, SyncEngineStatus.partial);
      expect(partialResult.pushedCount, greaterThanOrEqualTo(1));
      expect(partialResult.tableErrors.containsKey('vouchers'), isTrue);
    });
  });
}

class _OrderTrackingGateway implements RemoteGateway {
  final RemoteGateway delegate;
  final void Function(String table, String id) onUpsert;

  _OrderTrackingGateway(this.delegate, {required this.onUpsert});

  @override
  Future<Map<String, dynamic>?> upsertRow({
    required String table,
    required Map<String, dynamic> row,
  }) async {
    final id = (row['id'] ?? row['record_id'])?.toString() ?? '';
    onUpsert(table, id);
    return delegate.upsertRow(table: table, row: row);
  }

  @override
  Future<List<Map<String, dynamic>>> pullRows({
    required String table,
    required String companyId,
    DateTime? cursor,
    int pageSize = 500,
    int offset = 0,
  }) {
    return delegate.pullRows(
      table: table,
      companyId: companyId,
      cursor: cursor,
      pageSize: pageSize,
      offset: offset,
    );
  }
}

class _CustomExceptionGateway implements RemoteGateway {
  final RemoteGateway delegate;
  final void Function(String table, Map<String, dynamic> row) onUpsert;

  _CustomExceptionGateway(this.delegate, {required this.onUpsert});

  @override
  Future<Map<String, dynamic>?> upsertRow({
    required String table,
    required Map<String, dynamic> row,
  }) async {
    onUpsert(table, row);
    return delegate.upsertRow(table: table, row: row);
  }

  @override
  Future<List<Map<String, dynamic>>> pullRows({
    required String table,
    required String companyId,
    DateTime? cursor,
    int pageSize = 500,
    int offset = 0,
  }) {
    return delegate.pullRows(
      table: table,
      companyId: companyId,
      cursor: cursor,
      pageSize: pageSize,
      offset: offset,
    );
  }
}
