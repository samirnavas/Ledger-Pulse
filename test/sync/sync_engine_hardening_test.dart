import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:ledger_pulse/core/network/sync_codec.dart';
import 'package:ledger_pulse/core/network/sync_engine.dart';
import 'package:ledger_pulse/data/local/database.dart';
import 'package:ledger_pulse/data/local/outbox_helper.dart';
import 'package:ledger_pulse/data/models/party_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show PostgrestException, SupabaseClient;

import 'support/fake_remote_gateway.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  drift.driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

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

  group('SyncEngine Defect Hardening & Isolation Suite (Prompt 6.1)', () {
    // 23. Outbox enqueue failure observability
    test('23. Outbox enqueue failure observability', () async {
      // (a) Invalid table name throws ArgumentError
      expect(
        () => enqueueMutation(
          db: db,
          table: 'non_existent_table',
          recordId: 'rec_invalid',
          type: 'INSERT',
          fullRowMap: {'id': 'rec_invalid'},
        ),
        throwsA(isA<ArgumentError>()),
      );

      // (b) Propagates database exception as OutboxEnqueueException
      final errorDb = AppDatabase(NativeDatabase.memory());
      await errorDb.customStatement('DROP TABLE sync_outbox;');
      expect(
        () => enqueueMutation(
          db: errorDb,
          table: 'vouchers',
          recordId: 'v_fail_1',
          type: 'INSERT',
          fullRowMap: {'id': 'v_fail_1'},
        ),
        throwsA(isA<OutboxEnqueueException>()),
      );
      await errorDb.close();

      // (c) Unique constraint and idempotent payload update
      await enqueueMutation(
        db: db,
        table: 'vouchers',
        recordId: 'v_idemp_1',
        type: 'INSERT',
        fullRowMap: {'id': 'v_idemp_1', 'voucher_number': 'V-ORIG'},
      );
      await enqueueMutation(
        db: db,
        table: 'vouchers',
        recordId: 'v_idemp_1',
        type: 'UPDATE',
        fullRowMap: {'id': 'v_idemp_1', 'voucher_number': 'V-MODIFIED'},
      );

      final outboxRows = await (db.select(db.syncOutbox)
            ..where((t) => t.recordId.equals('v_idemp_1')))
          .get();
      expect(outboxRows.length, 1);
      final payload =
          jsonDecode(outboxRows.first.payload) as Map<String, dynamic>;
      expect(payload['voucher_number'], 'V-MODIFIED');
    });

    // 24. Workspace scoping: Workspace A push does not upload Workspace B mutations
    test('24. Workspace scoping: Workspace A push isolates Workspace B mutations', () async {
      const workspaceA = 'cmp_scope_a';
      const workspaceB = 'cmp_scope_b';

      // Seed vouchers for both workspaces in outbox
      await enqueueMutation(
        db: db,
        table: 'vouchers',
        recordId: 'v_ws_a',
        type: 'UPSERT',
        fullRowMap: {
          'id': 'v_ws_a',
          'company_id': workspaceA,
          'voucher_number': 'V-A',
        },
      );
      await enqueueMutation(
        db: db,
        table: 'vouchers',
        recordId: 'v_ws_b',
        type: 'UPSERT',
        fullRowMap: {
          'id': 'v_ws_b',
          'company_id': workspaceB,
          'voucher_number': 'V-B',
        },
      );

      // Push only workspace A
      final resultA = await syncEngine.pushQueue(companyId: workspaceA);
      expect(resultA.status, SyncEngineStatus.success);

      // Remote has workspace A voucher, but NOT workspace B
      expect(gateway.tables['vouchers']?['v_ws_a'], isNotNull);
      expect(gateway.tables['vouchers']?['v_ws_b'], isNull);

      // Outbox still holds workspace B voucher
      final remainingOutbox = await db.select(db.syncOutbox).get();
      expect(remainingOutbox.any((r) => r.recordId == 'v_ws_b'), isTrue);
      expect(remainingOutbox.any((r) => r.recordId == 'v_ws_a'), isFalse);

      // Now push workspace B
      final resultB = await syncEngine.pushQueue(companyId: workspaceB);
      expect(resultB.status, SyncEngineStatus.success);
      expect(gateway.tables['vouchers']?['v_ws_b'], isNotNull);

      // Outbox is now empty
      final emptyOutbox = await db.select(db.syncOutbox).get();
      expect(emptyOutbox.isEmpty, isTrue);
    });

    // 25. Conflict resolution cursor safety: skipped remote conflict is not permanently lost
    test('25. Conflict cursor safety: skipped remote conflict is retained and reconciled after local push', () async {
      final t1 = DateTime.utc(2026, 5, 1, 10, 0, 0);
      final t2 = DateTime.utc(2026, 5, 1, 10, 5, 0);

      // Remote has v_conflict at t1, and v_clean at t2
      gateway.tables.putIfAbsent('vouchers', () => {})['v_conflict'] = {
        'id': 'v_conflict',
        'company_id': testCompanyId,
        'voucher_number': 'REMOTE-V1',
        'type': 'expense',
        'date': encodeTime(t1),
        'updated_at': encodeTime(t1),
        'is_deleted': false,
        'revision': 1,
      };
      gateway.tables['vouchers']!['v_clean'] = {
        'id': 'v_clean',
        'company_id': testCompanyId,
        'voucher_number': 'REMOTE-CLEAN',
        'type': 'expense',
        'date': encodeTime(t2),
        'updated_at': encodeTime(t2),
        'is_deleted': false,
        'revision': 1,
      };

      // Local has v_conflict with pending unpushed edit
      await db.into(db.vouchers).insert(
        VouchersCompanion(
          id: const drift.Value('v_conflict'),
          companyId: const drift.Value(testCompanyId),
          voucherNumber: const drift.Value('LOCAL-EDIT'),
          type: const drift.Value('expense'),
          date: drift.Value(DateTime.now()),
          syncStatus: const drift.Value(SyncRecordStatus.pending),
          revision: const drift.Value(2),
        ),
      );

      // 1. Pull remote changes: v_conflict is skipped because local is pending
      final pull1 = await syncEngine.pullChanges(companyId: testCompanyId);
      expect(pull1.status, SyncEngineStatus.success);

      // Local v_conflict remains unchanged (local edit preserved)
      final localBeforePush = await (db.select(db.vouchers)
            ..where((t) => t.id.equals('v_conflict')))
          .getSingle();
      expect(localBeforePush.voucherNumber, 'LOCAL-EDIT');

      // Clean voucher was pulled
      final localClean = await (db.select(db.vouchers)
            ..where((t) => t.id.equals('v_clean')))
          .getSingleOrNull();
      expect(localClean, isNotNull);

      // Cursor must NOT have advanced past the skipped record's timestamp (t1)
      final syncStateRow = await (db.select(db.syncState)..where(
            (t) =>
                t.targetTable.equals('vouchers') &
                t.companyId.equals(testCompanyId),
          ))
          .getSingle();
      expect(syncStateRow.lastPulledAt!.isAfter(t1), isFalse);

      // 2. Local pushes its mutation
      await syncEngine.pushQueue(companyId: testCompanyId);

      // Local voucher is now synced
      final localAfterPush = await (db.select(db.vouchers)
            ..where((t) => t.id.equals('v_conflict')))
          .getSingle();
      expect(localAfterPush.syncStatus, SyncRecordStatus.synced);

      // 3. Remote receives an updated version at t3
      final t3 = DateTime.utc(2026, 5, 1, 10, 10, 0);
      gateway.tables['vouchers']!['v_conflict'] = {
        'id': 'v_conflict',
        'company_id': testCompanyId,
        'voucher_number': 'REMOTE-RECONCILED',
        'type': 'expense',
        'date': encodeTime(t3),
        'updated_at': encodeTime(t3),
        'is_deleted': false,
        'revision': 3,
      };

      // 4. Next pull re-pulls and reconciles v_conflict cleanly
      final pull2 = await syncEngine.pullChanges(companyId: testCompanyId);
      expect(pull2.status, SyncEngineStatus.success);

      final localReconciled = await (db.select(db.vouchers)
            ..where((t) => t.id.equals('v_conflict')))
          .getSingle();
      expect(localReconciled.voucherNumber, 'REMOTE-RECONCILED');
    });

    // 26. Incremental keyset pagination: identical timestamps across page boundary
    test('26. Keyset pagination: identical timestamps are not dropped across pages', () async {
      final sharedTime = DateTime.utc(2026, 5, 1, 12, 0, 0);
      final sharedTimeStr = encodeTime(sharedTime);

      // Insert 6 vouchers all having the exact same millisecond timestamp
      for (int i = 1; i <= 6; i++) {
        gateway.tables.putIfAbsent('vouchers', () => {})['v_same_ts_$i'] = {
          'id': 'v_same_ts_$i',
          'company_id': testCompanyId,
          'voucher_number': 'V-TS-$i',
          'type': 'expense',
          'date': sharedTimeStr,
          'updated_at': sharedTimeStr,
          'is_deleted': false,
          'revision': 1,
        };
      }

      final pullResult = await syncEngine.pullChanges(companyId: testCompanyId);
      expect(pullResult.status, SyncEngineStatus.success);

      final localVouchers = await (db.select(db.vouchers)..where(
            (t) =>
                t.companyId.equals(testCompanyId) &
                t.id.like('v_same_ts_%'),
          ))
          .get();
      expect(localVouchers.length, 6);
    });

    // 27. Keyset pagination: >500 records multi-page fetch
    test('27. Keyset pagination: >500 records correctly paginated without truncation', () async {
      final baseTime = DateTime.utc(2026, 5, 1, 8, 0, 0);
      for (int i = 0; i < 550; i++) {
        final t = baseTime.add(Duration(seconds: i));
        gateway.tables.putIfAbsent('accounts', () => {})['acc_bulk_$i'] = {
          'id': 'acc_bulk_$i',
          'company_id': testCompanyId,
          'code': 'BK${i.toString().padLeft(4, '0')}',
          'name': 'Bulk Account $i',
          'type': 'asset',
          'normal_balance': 'debit',
          'opening_balance_in_cents': 0,
          'current_balance_in_cents': 0,
          'is_system': false,
          'is_active': true,
          'updated_at': encodeTime(t),
          'is_deleted': false,
          'revision': 1,
        };
      }

      final result = await syncEngine.pullChanges(companyId: testCompanyId);
      expect(result.status, SyncEngineStatus.success);

      final count = await (db.select(db.accounts)..where(
            (t) =>
                t.companyId.equals(testCompanyId) &
                t.id.like('acc_bulk_%'),
          ))
          .get();
      expect(count.length, 550);
    });

    // 28. Partial pull failure does not advance cursor, subsequent pull completes
    test('28. Partial pull failure does not advance cursor; retry pulls all records', () async {
      final t1 = DateTime.utc(2026, 5, 1, 10, 0, 0);
      gateway.tables.putIfAbsent('parties', () => {})['p_partial_1'] = {
        'id': 'p_partial_1',
        'company_id': testCompanyId,
        'name': 'Party 1',
        'type': 'customer',
        'updated_at': encodeTime(t1),
        'is_deleted': false,
        'revision': 1,
      };

      // Simulate failure on table pull
      gateway.failedTables.add('parties');
      final failResult = await syncEngine.pullChanges(companyId: testCompanyId);
      expect(failResult.status, SyncEngineStatus.partial);
      expect(failResult.tableErrors.containsKey('parties'), isTrue);

      // Verify sync_state cursor was NOT saved/advanced
      final stateBefore = await (db.select(db.syncState)..where(
            (t) =>
                t.targetTable.equals('parties') &
                t.companyId.equals(testCompanyId),
          ))
          .getSingleOrNull();
      expect(stateBefore, isNull);

      // Remove failure and retry
      gateway.failedTables.clear();
      final retryResult = await syncEngine.pullChanges(companyId: testCompanyId);
      expect(retryResult.status, SyncEngineStatus.success);

      final localParty = await (db.select(db.parties)
            ..where((t) => t.id.equals('p_partial_1')))
          .getSingleOrNull();
      expect(localParty, isNotNull);

      final stateAfter = await (db.select(db.syncState)..where(
            (t) =>
                t.targetTable.equals('parties') &
                t.companyId.equals(testCompanyId),
          ))
          .getSingleOrNull();
      expect(stateAfter, isNotNull);
    });

    // 29. Repeated downloads are idempotent
    test('29. Repeated downloads are idempotent without duplicate local records', () async {
      final t1 = DateTime.utc(2026, 5, 1, 10, 0, 0);
      gateway.tables.putIfAbsent('accounts', () => {})['acc_idemp_1'] = {
        'id': 'acc_idemp_1',
        'company_id': testCompanyId,
        'code': 'ACC-IDEMP',
        'name': 'Idempotent Account',
        'type': 'asset',
        'normal_balance': 'debit',
        'opening_balance_in_cents': 0,
        'current_balance_in_cents': 0,
        'is_system': false,
        'is_active': true,
        'updated_at': encodeTime(t1),
        'is_deleted': false,
        'revision': 1,
      };

      // Pull first time
      await syncEngine.pullChanges(companyId: testCompanyId);
      // Pull second time
      await syncEngine.pullChanges(companyId: testCompanyId);

      final rows = await (db.select(db.accounts)
            ..where((t) => t.id.equals('acc_idemp_1')))
          .get();
      expect(rows.length, 1);
    });

    // 30. Permanent failure is not retried on multiple syncs
    test('30. Permanent failure is marked and NOT automatically retried on subsequent syncs', () async {
      int gatewayAttempts = 0;
      final permGateway =
          _CustomExceptionGateway(gateway, onUpsert: (table, row) {
        if (row['id'] == 'v_perm_fail') {
          gatewayAttempts++;
          throw const PostgrestException(
            message: 'violates foreign key constraint "vouchers_company_id_fkey"',
            code: '23503',
          );
        }
      });

      final engine = SyncEngine(
        db: db,
        gateway: permGateway,
        simulateSyncForTesting: true,
        activeUserId: testUserId,
      );

      await db.into(db.vouchers).insert(
        VouchersCompanion(
          id: const drift.Value('v_perm_fail'),
          companyId: const drift.Value(testCompanyId),
          voucherNumber: const drift.Value('V-PERM'),
          type: const drift.Value('expense'),
          date: drift.Value(DateTime.now()),
          syncStatus: const drift.Value(SyncRecordStatus.pending),
        ),
      );

      // Attempt 1: Fails with permanent error
      final res1 = await engine.pushQueue(companyId: testCompanyId);
      expect(res1.status, SyncEngineStatus.partial);
      expect(gatewayAttempts, 1);

      // Verify outbox entry: lastError set, nextAttemptAt is null
      final outbox1 = await (db.select(db.syncOutbox)
            ..where((t) => t.recordId.equals('v_perm_fail')))
          .getSingle();
      expect(outbox1.lastError, contains('Permanent failure'));
      expect(outbox1.nextAttemptAt, isNull);

      // Verify local row syncStatus is error
      final v1 = await (db.select(db.vouchers)
            ..where((t) => t.id.equals('v_perm_fail')))
          .getSingle();
      expect(v1.syncStatus, SyncRecordStatus.error);

      // Attempt 2 and Attempt 3: Outbox permanent error must NOT be retried
      await engine.pushQueue(companyId: testCompanyId);
      await engine.pushQueue(companyId: testCompanyId);

      expect(gatewayAttempts, 1); // Not called again!

      // Outbox payload is safely retained for manual recovery
      final outboxRetained = await (db.select(db.syncOutbox)
            ..where((t) => t.recordId.equals('v_perm_fail')))
          .getSingleOrNull();
      expect(outboxRetained, isNotNull);
      expect(outboxRetained!.payload, contains('v_perm_fail'));
    });

    // 31. Safe in-flight disposal (Delayed gateway test)
    test('31. Delayed gateway test: disposal while in-flight prevents stale writes and false success', () async {
      final holdCompleter = Completer<Map<String, dynamic>?>();

      final delayedGateway =
          _DelayHoldingGateway(gateway, holdCompleter: holdCompleter);
      final engine = SyncEngine(
        db: db,
        gateway: delayedGateway,
        simulateSyncForTesting: true,
        activeUserId: testUserId,
      );

      await db.into(db.vouchers).insert(
        VouchersCompanion(
          id: const drift.Value('v_inflight_1'),
          companyId: const drift.Value(testCompanyId),
          voucherNumber: const drift.Value('V-INFLIGHT'),
          type: const drift.Value('expense'),
          date: drift.Value(DateTime.now()),
          syncStatus: const drift.Value(SyncRecordStatus.pending),
          revision: const drift.Value(1),
        ),
      );

      // Start push in background
      final pushFuture = engine.pushQueue(companyId: testCompanyId);

      // Wait until remote request is in flight
      await delayedGateway.requestStarted.future;

      // Dispose engine while request is in flight
      engine.dispose();

      // Release remote response
      holdCompleter.complete({
        'id': 'v_inflight_1',
        'company_id': testCompanyId,
        'voucher_number': 'V-INFLIGHT',
        'updated_at': encodeTime(DateTime.now()),
      });

      final result = await pushFuture;

      // Must NOT report full success
      expect(result.status, isNot(SyncEngineStatus.success));

      // Local record must NOT have been marked synced
      final localVoucher = await (db.select(db.vouchers)
            ..where((t) => t.id.equals('v_inflight_1')))
          .getSingle();
      expect(localVoucher.syncStatus, SyncRecordStatus.pending);

      // Outbox entry must NOT have been deleted
      final outboxRows = await (db.select(db.syncOutbox)
            ..where((t) => t.recordId.equals('v_inflight_1')))
          .get();
      expect(outboxRows.length, 1);
    });

    // 32. Production SupabaseGateway query filter verification
    test('32. Production SupabaseGateway query filter verification via recording HTTP client', () async {
      final recordingClient = _RecordingHttpClient();
      final supabaseClient = SupabaseClient(
        'https://mock.supabase.co',
        'mock-anon-key',
        httpClient: recordingClient,
      );
      final prodGateway = SupabaseGateway(supabaseClient);

      // (a) Test vouchers query: must filter by company_id and order by updated_at + id
      await prodGateway.pullRows(
        table: 'vouchers',
        companyId: 'cmp_scope_test',
        cursor: DateTime.utc(2026, 5, 1, 10, 0, 0),
        pageSize: 50,
        offset: 0,
      );
      expect(recordingClient.lastRequest, isNotNull);
      final vouchersUrl = recordingClient.lastRequest!.url.toString();
      expect(vouchersUrl, contains('/rest/v1/vouchers'));
      expect(vouchersUrl, contains('company_id=eq.cmp_scope_test'));
      expect(vouchersUrl, contains('updated_at=gte.'));
      expect(vouchersUrl, contains('order=updated_at.asc'));
      expect(vouchersUrl, contains('id.asc'));

      // (b) Test companies query: must filter by id == companyId
      await prodGateway.pullRows(
        table: 'companies',
        companyId: 'cmp_company_test',
        pageSize: 50,
      );
      final companiesUrl = recordingClient.lastRequest!.url.toString();
      expect(companiesUrl, contains('/rest/v1/companies'));
      expect(companiesUrl, contains('id=eq.cmp_company_test'));

      // (c) Test user_profiles query: must filter by id == activeUserId
      await prodGateway.pullRows(
        table: 'user_profiles',
        companyId: 'cmp_scope_test',
        activeUserId: 'usr_authenticated_1',
        pageSize: 50,
      );
      final profilesUrl = recordingClient.lastRequest!.url.toString();
      expect(profilesUrl, contains('/rest/v1/user_profiles'));
      expect(profilesUrl, contains('id=eq.usr_authenticated_1'));

      // (d) Test expense wallets query: must filter by profile_id == companyId
      await prodGateway.pullRows(
        table: 'exp_wallets',
        companyId: 'cmp_expense_workspace',
        pageSize: 50,
      );
      final walletsUrl = recordingClient.lastRequest!.url.toString();
      expect(walletsUrl, contains('/rest/v1/exp_wallets'));
      expect(walletsUrl, contains('profile_id=eq.cmp_expense_workspace'));
    });
  });

  group('SyncEngine Reliability & Isolation Suite (Prompt 6.2)', () {
    // 33. Outbox enqueue failure is visible in the returned sync result
    test('33. Enqueue failure is visible in returned sync result', () async {
      await db.customStatement('''
        CREATE TRIGGER fail_voucher_enqueue BEFORE INSERT ON sync_outbox
        FOR EACH ROW WHEN NEW.record_id = 'v_enqueue_fail'
        BEGIN
          SELECT RAISE(FAIL, 'Simulated SQLite outbox failure for v_enqueue_fail');
        END;
      ''');

      await db.into(db.vouchers).insert(
        VouchersCompanion(
          id: const drift.Value('v_enqueue_fail'),
          companyId: const drift.Value(testCompanyId),
          voucherNumber: const drift.Value('V-FAIL'),
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
      expect(result.status, SyncEngineStatus.partial);
      expect(result.tableErrors.containsKey('vouchers:v_enqueue_fail'), isTrue);
      expect(result.tableErrors['vouchers:v_enqueue_fail'], contains('v_enqueue_fail'));

      await db.customStatement('DROP TRIGGER fail_voucher_enqueue;');
    });

    // 34. The affected record whose enqueue failed is not uploaded
    test('34. The affected record whose enqueue failed is not uploaded', () async {
      await db.customStatement('''
        CREATE TRIGGER fail_voucher_enqueue BEFORE INSERT ON sync_outbox
        FOR EACH ROW WHEN NEW.record_id = 'v_fail_no_upload'
        BEGIN
          SELECT RAISE(FAIL, 'Simulated outbox failure');
        END;
      ''');

      await db.into(db.vouchers).insert(
        VouchersCompanion(
          id: const drift.Value('v_fail_no_upload'),
          companyId: const drift.Value(testCompanyId),
          voucherNumber: const drift.Value('V-NO-UPLOAD'),
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

      await syncEngine.pushQueue(companyId: testCompanyId);

      // Verify remote has not received it
      expect(gateway.tables['vouchers']?['v_fail_no_upload'], isNull);

      // Verify local record is NOT marked synced
      final localRow = await (db.select(db.vouchers)..where((t) => t.id.equals('v_fail_no_upload'))).getSingle();
      expect(localRow.syncStatus, SyncRecordStatus.pending);

      await db.customStatement('DROP TRIGGER fail_voucher_enqueue;');
    });

    // 35. Other successfully enqueued records can still sync
    test('35. Other successfully enqueued records can still sync', () async {
      await db.customStatement('''
        CREATE TRIGGER fail_voucher_enqueue BEFORE INSERT ON sync_outbox
        FOR EACH ROW WHEN NEW.record_id = 'v_fail_isolate'
        BEGIN
          SELECT RAISE(FAIL, 'Simulated failure for v_fail_isolate');
        END;
      ''');

      await db.into(db.vouchers).insert(
        VouchersCompanion(
          id: const drift.Value('v_fail_isolate'),
          companyId: const drift.Value(testCompanyId),
          voucherNumber: const drift.Value('V-FAIL-ISO'),
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
      await db.into(db.vouchers).insert(
        VouchersCompanion(
          id: const drift.Value('v_ok_isolate'),
          companyId: const drift.Value(testCompanyId),
          voucherNumber: const drift.Value('V-OK-ISO'),
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
      expect(result.status, SyncEngineStatus.partial);

      // v_ok_isolate succeeded
      expect(gateway.tables['vouchers']?['v_ok_isolate'], isNotNull);
      final localOk = await (db.select(db.vouchers)..where((t) => t.id.equals('v_ok_isolate'))).getSingle();
      expect(localOk.syncStatus, SyncRecordStatus.synced);

      // v_fail_isolate was not uploaded
      expect(gateway.tables['vouchers']?['v_fail_isolate'], isNull);
      final localFail = await (db.select(db.vouchers)..where((t) => t.id.equals('v_fail_isolate'))).getSingle();
      expect(localFail.syncStatus, SyncRecordStatus.pending);

      await db.customStatement('DROP TRIGGER fail_voucher_enqueue;');
    });

    // 36. A later retry succeeds after the local database error is resolved
    test('36. A later retry succeeds after local database error is resolved', () async {
      await db.customStatement('''
        CREATE TRIGGER fail_voucher_enqueue BEFORE INSERT ON sync_outbox
        FOR EACH ROW WHEN NEW.record_id = 'v_retry_test'
        BEGIN
          SELECT RAISE(FAIL, 'Simulated failure for v_retry_test');
        END;
      ''');

      await db.into(db.vouchers).insert(
        VouchersCompanion(
          id: const drift.Value('v_retry_test'),
          companyId: const drift.Value(testCompanyId),
          voucherNumber: const drift.Value('V-RETRY'),
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

      final result1 = await syncEngine.pushQueue(companyId: testCompanyId);
      expect(result1.status, SyncEngineStatus.partial);
      expect(gateway.tables['vouchers']?['v_retry_test'], isNull);

      // Resolve error condition
      await db.customStatement('DROP TRIGGER fail_voucher_enqueue;');

      // Retry push
      final result2 = await syncEngine.pushQueue(companyId: testCompanyId);
      expect(result2.status, SyncEngineStatus.success);
      expect(gateway.tables['vouchers']?['v_retry_test'], isNotNull);

      final localRetry = await (db.select(db.vouchers)..where((t) => t.id.equals('v_retry_test'))).getSingle();
      expect(localRetry.syncStatus, SyncRecordStatus.synced);
    });

    // 37. Keyset pagination: More than 500 records
    test('37. Keyset pagination: More than 500 records', () async {
      final baseTime = DateTime.utc(2026, 5, 1, 10, 0, 0);
      for (int i = 1; i <= 550; i++) {
        final id = 'v_${i.toString().padLeft(4, '0')}';
        final t = baseTime.add(Duration(seconds: i));
        gateway.tables.putIfAbsent('vouchers', () => {})[id] = {
          'id': id,
          'company_id': testCompanyId,
          'voucher_number': 'V-$i',
          'date': encodeTime(t),
          'created_at': encodeTime(t),
          'updated_at': encodeTime(t),
          'is_deleted': false,
        };
      }

      final result = await syncEngine.pullChanges(companyId: testCompanyId);
      expect(result.status, SyncEngineStatus.success);

      final localVouchers = await db.select(db.vouchers).get();
      expect(localVouchers.length, 550);
    });

    // 38. Keyset pagination: Identical timestamps across page boundaries
    test('38. Keyset pagination: Identical timestamps across page boundaries', () async {
      final boundaryGateway = _PageSizeForcingGateway(gateway, forcedPageSize: 10);
      final customEngine = SyncEngine(db: db, gateway: boundaryGateway, pageSize: 10);

      final tShared = DateTime.utc(2026, 5, 1, 12, 0, 0);
      for (int i = 1; i <= 25; i++) {
        final id = 'v_dup_${i.toString().padLeft(3, '0')}';
        final t = (i >= 8 && i <= 15) ? tShared : DateTime.utc(2026, 5, 1, 10, i, 0);
        gateway.tables.putIfAbsent('vouchers', () => {})[id] = {
          'id': id,
          'company_id': testCompanyId,
          'voucher_number': 'V-DUP-$i',
          'date': encodeTime(t),
          'created_at': encodeTime(t),
          'updated_at': encodeTime(t),
          'is_deleted': false,
        };
      }

      final result = await customEngine.pullChanges(companyId: testCompanyId);
      expect(result.status, SyncEngineStatus.success);

      final localRows = await db.select(db.vouchers).get();
      expect(localRows.length, 25);
      final localIds = localRows.map((r) => r.id).toSet();
      expect(localIds.length, 25);
    });

    // 39. Keyset pagination: New records inserted while pagination is underway
    test('39. Keyset pagination: New records inserted while pagination is underway', () async {
      bool newRecordInserted = false;
      final interleavingGateway = _InterleavingGateway(
        gateway,
        forcedPageSize: 10,
        onPagePulled: (table, pageNumber) {
          if (table == 'vouchers' && pageNumber == 1 && !newRecordInserted) {
            newRecordInserted = true;
            final tNew = DateTime.utc(2026, 5, 1, 14, 0, 0);
            gateway.tables.putIfAbsent('vouchers', () => {})['v_interleaved_new'] = {
              'id': 'v_interleaved_new',
              'company_id': testCompanyId,
              'voucher_number': 'V-INTERLEAVED',
              'date': encodeTime(tNew),
              'created_at': encodeTime(tNew),
              'updated_at': encodeTime(tNew),
              'is_deleted': false,
            };
          }
        },
      );
      final customEngine = SyncEngine(db: db, gateway: interleavingGateway, pageSize: 10);

      for (int i = 1; i <= 20; i++) {
        final id = 'v_pg_${i.toString().padLeft(3, '0')}';
        final t = DateTime.utc(2026, 5, 1, 10, i, 0);
        gateway.tables.putIfAbsent('vouchers', () => {})[id] = {
          'id': id,
          'company_id': testCompanyId,
          'voucher_number': 'V-$i',
          'date': encodeTime(t),
          'created_at': encodeTime(t),
          'updated_at': encodeTime(t),
          'is_deleted': false,
        };
      }

      final result = await customEngine.pullChanges(companyId: testCompanyId);
      expect(result.status, SyncEngineStatus.success);

      final localRows = await db.select(db.vouchers).get();
      expect(localRows.length, 21);
      expect(localRows.any((r) => r.id == 'v_interleaved_new'), isTrue);
    });

    // 40. Keyset pagination: Records updated while pagination is underway
    test('40. Keyset pagination: Records updated while pagination is underway', () async {
      final interleavingGateway = _InterleavingGateway(
        gateway,
        forcedPageSize: 10,
        onPagePulled: (table, pageNumber) {
          if (table == 'vouchers' && pageNumber == 1) {
            final tUpdated = DateTime.utc(2026, 5, 1, 15, 0, 0);
            gateway.tables.putIfAbsent('vouchers', () => {})['v_upd_015'] = {
              'id': 'v_upd_015',
              'company_id': testCompanyId,
              'voucher_number': 'V-UPDATED-NOTE',
              'date': encodeTime(tUpdated),
              'created_at': encodeTime(tUpdated),
              'updated_at': encodeTime(tUpdated),
              'is_deleted': false,
            };
          }
        },
      );
      final customEngine = SyncEngine(db: db, gateway: interleavingGateway, pageSize: 10);

      for (int i = 1; i <= 20; i++) {
        final id = 'v_upd_${i.toString().padLeft(3, '0')}';
        final t = DateTime.utc(2026, 5, 1, 10, i, 0);
        gateway.tables.putIfAbsent('vouchers', () => {})[id] = {
          'id': id,
          'company_id': testCompanyId,
          'voucher_number': 'V-$i',
          'date': encodeTime(t),
          'created_at': encodeTime(t),
          'updated_at': encodeTime(t),
          'is_deleted': false,
        };
      }

      final result = await customEngine.pullChanges(companyId: testCompanyId);
      expect(result.status, SyncEngineStatus.success);

      final localRows = await db.select(db.vouchers).get();
      expect(localRows.length, 20);
      final updatedRow = localRows.firstWhere((r) => r.id == 'v_upd_015');
      expect(updatedRow.voucherNumber, 'V-UPDATED-NOTE');
    });

    // 41. Keyset pagination: Retry after later page fails preserves cursor
    test('41. Keyset pagination: Retry after a later page fails preserves cursor and succeeds on retry', () async {
      bool failPage2 = true;
      final failingGateway = _InterleavingGateway(
        gateway,
        forcedPageSize: 10,
        onPagePulled: (table, pageNum) {
          if (table == 'vouchers' && failPage2 && pageNum == 2) {
            throw SocketException('Simulated network failure on page 2');
          }
        },
      );
      final customEngine = SyncEngine(db: db, gateway: failingGateway, pageSize: 10);

      for (int i = 1; i <= 25; i++) {
        final id = 'v_fl_${i.toString().padLeft(3, '0')}';
        final t = DateTime.utc(2026, 5, 1, 10, i, 0);
        gateway.tables.putIfAbsent('vouchers', () => {})[id] = {
          'id': id,
          'company_id': testCompanyId,
          'voucher_number': 'V-$i',
          'date': encodeTime(t),
          'created_at': encodeTime(t),
          'updated_at': encodeTime(t),
          'is_deleted': false,
        };
      }

      // First pull fails on page 2
      final result1 = await customEngine.pullChanges(companyId: testCompanyId);
      expect(result1.tableErrors.containsKey('vouchers'), isTrue);

      // Verify sync_state cursor was NOT saved/advanced for vouchers
      final cursorState = await (db.select(db.syncState)
            ..where((t) => t.targetTable.equals('vouchers') & t.companyId.equals(testCompanyId)))
          .getSingleOrNull();
      expect(cursorState, isNull);

      // Fix failure condition and retry
      failPage2 = false;
      final result2 = await customEngine.pullChanges(companyId: testCompanyId);
      expect(result2.status, SyncEngineStatus.success);

      final localRows = await db.select(db.vouchers).get();
      expect(localRows.length, 25);

      final savedCursor = await (db.select(db.syncState)
            ..where((t) => t.targetTable.equals('vouchers') & t.companyId.equals(testCompanyId)))
          .getSingleOrNull();
      expect(savedCursor, isNotNull);
    });

    // 42. Keyset pagination: Workspace isolation across every page
    test('42. Keyset pagination: Workspace isolation across every page', () async {
      final boundaryGateway = _PageSizeForcingGateway(gateway, forcedPageSize: 5);
      final customEngine = SyncEngine(db: db, gateway: boundaryGateway, pageSize: 5);

      const wsA = 'cmp_keyset_ws_a';
      const wsB = 'cmp_keyset_ws_b';

      for (int i = 1; i <= 15; i++) {
        final idA = 'v_ws_a_$i';
        final idB = 'v_ws_b_$i';
        final tA = DateTime.utc(2026, 5, 1, 10, i, 0);
        final tB = DateTime.utc(2026, 5, 1, 10, i, 30);
        gateway.tables.putIfAbsent('vouchers', () => {})[idA] = {
          'id': idA,
          'company_id': wsA,
          'voucher_number': 'V-A-$i',
          'date': encodeTime(tA),
          'created_at': encodeTime(tA),
          'updated_at': encodeTime(tA),
          'is_deleted': false,
        };
        gateway.tables.putIfAbsent('vouchers', () => {})[idB] = {
          'id': idB,
          'company_id': wsB,
          'voucher_number': 'V-B-$i',
          'date': encodeTime(tB),
          'created_at': encodeTime(tB),
          'updated_at': encodeTime(tB),
          'is_deleted': false,
        };
      }

      final result = await customEngine.pullChanges(companyId: wsA);
      expect(result.status, SyncEngineStatus.success);

      final localRows = await db.select(db.vouchers).get();
      expect(localRows.length, 15);
      expect(localRows.every((r) => r.companyId == wsA), isTrue);
      expect(localRows.any((r) => r.companyId == wsB), isFalse);
    });

    // 43. Production SupabaseGateway keyset query construction verification
    test('43. Production SupabaseGateway keyset query construction verification', () async {
      final recordingClient = _RecordingHttpClient();
      final supabaseClient = SupabaseClient(
        'https://mock.supabase.co',
        'mock-anon-key',
        httpClient: recordingClient,
      );
      final prodGateway = SupabaseGateway(supabaseClient);

      final afterTime = DateTime.utc(2026, 5, 1, 12, 0, 0);
      await prodGateway.pullRows(
        table: 'vouchers',
        companyId: 'cmp_scope_test',
        pageSize: 50,
        afterUpdatedAt: afterTime,
        afterId: 'v_boundary_100',
      );

      expect(recordingClient.lastRequest, isNotNull);
      final url = recordingClient.lastRequest!.url.toString();
      expect(url, contains('/rest/v1/vouchers'));
      expect(url, contains('company_id=eq.cmp_scope_test'));
      expect(url, contains('or=%28updated_at.gt.2026-05-01T12%3A00%3A00'));
      expect(url, contains('id.gt.v_boundary_100'));
      expect(url, contains('order=updated_at.asc'));
      expect(url, contains('id.asc'));
      expect(url, contains('limit=50'));
      expect(url, isNot(contains('offset=')));
    });

    // 44. Session invalidation during remote upsert preserves pending outbox entry
    test('44. Session invalidation during remote upsert preserves pending outbox entry', () async {
      final holdCompleter = Completer<Map<String, dynamic>?>();
      final delayGateway = _DelayHoldingGateway(gateway, holdCompleter: holdCompleter);
      final delayEngine = SyncEngine(db: db, gateway: delayGateway);

      await db.into(db.vouchers).insert(
        VouchersCompanion(
          id: const drift.Value('v_async_upsert'),
          companyId: const drift.Value(testCompanyId),
          voucherNumber: const drift.Value('V-ASYNC-UP'),
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

      final pushFuture = delayEngine.pushQueue(companyId: testCompanyId);
      await delayGateway.requestStarted.future;

      delayEngine.invalidateSession();

      holdCompleter.complete({
        'id': 'v_async_upsert',
        'company_id': testCompanyId,
        'voucher_number': 'V-ASYNC-UP',
        'updated_at': encodeTime(DateTime.now()),
      });

      final result = await pushFuture;
      expect(result.status, SyncEngineStatus.idle);

      final local = await (db.select(db.vouchers)..where((t) => t.id.equals('v_async_upsert'))).getSingle();
      expect(local.syncStatus, SyncRecordStatus.pending);

      final outbox = await (db.select(db.syncOutbox)..where((t) => t.recordId.equals('v_async_upsert'))).getSingleOrNull();
      expect(outbox, isNotNull);
    });

    // 45. Session invalidation during local acknowledgement read/write sequence
    test('45. Session invalidation during local acknowledgement read/write sequence', () async {
      await db.into(db.vouchers).insert(
        VouchersCompanion(
          id: const drift.Value('v_ack_stale'),
          companyId: const drift.Value(testCompanyId),
          voucherNumber: const drift.Value('V-ACK-STALE'),
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

      syncEngine.onBeforeMarkSynced = () async {
        syncEngine.invalidateSession();
      };

      final result = await syncEngine.pushQueue(companyId: testCompanyId);
      expect(result.status, SyncEngineStatus.idle);

      final local = await (db.select(db.vouchers)..where((t) => t.id.equals('v_ack_stale'))).getSingle();
      expect(local.syncStatus, SyncRecordStatus.pending);

      final outbox = await (db.select(db.syncOutbox)..where((t) => t.recordId.equals('v_ack_stale'))).getSingleOrNull();
      expect(outbox, isNotNull);
    });

    // 46. Session invalidation during remote pull application
    test('46. Session invalidation during remote pull application prevents applying remote rows', () async {
      final t = DateTime.utc(2026, 5, 1, 10, 0, 0);
      gateway.tables.putIfAbsent('vouchers', () => {})['v_pull_stale'] = {
        'id': 'v_pull_stale',
        'company_id': testCompanyId,
        'voucher_number': 'V-PULL-STALE',
        'date': encodeTime(t),
        'created_at': encodeTime(t),
        'updated_at': encodeTime(t),
        'is_deleted': false,
      };

      syncEngine.onBeforeApplyRemoteRows = () async {
        syncEngine.invalidateSession();
      };

      final result = await syncEngine.pullChanges(companyId: testCompanyId);
      expect(result.status, SyncEngineStatus.idle);

      final local = await (db.select(db.vouchers)..where((t) => t.id.equals('v_pull_stale'))).getSingleOrNull();
      expect(local, isNull);

      final cursor = await (db.select(db.syncState)
            ..where((t) => t.targetTable.equals('vouchers') & t.companyId.equals(testCompanyId)))
          .getSingleOrNull();
      expect(cursor, isNull);
    });

    // 47. Session invalidation immediately before cursor persistence
    test('47. Session invalidation immediately before cursor persistence prevents cursor update', () async {
      final t = DateTime.utc(2026, 5, 1, 10, 0, 0);
      gateway.tables.putIfAbsent('vouchers', () => {})['v_cursor_stale'] = {
        'id': 'v_cursor_stale',
        'company_id': testCompanyId,
        'voucher_number': 'V-CURSOR-STALE',
        'date': encodeTime(t),
        'created_at': encodeTime(t),
        'updated_at': encodeTime(t),
        'is_deleted': false,
      };

      syncEngine.onBeforePersistCursor = () async {
        syncEngine.invalidateSession();
      };

      final result = await syncEngine.pullChanges(companyId: testCompanyId);
      expect(result.status, SyncEngineStatus.idle);

      final cursor = await (db.select(db.syncState)
            ..where((t) => t.targetTable.equals('vouchers') & t.companyId.equals(testCompanyId)))
          .getSingleOrNull();
      expect(cursor, isNull);
    });

    // 48. Authenticated session cannot bypass workspace isolation with cmp_default
    test('48. Authenticated session cannot bypass workspace isolation with cmp_default', () async {
      const otherWorkspace = 'cmp_other_secret_workspace';

      final authEngine = SyncEngine(
        db: db,
        gateway: gateway,
        activeUserId: 'usr_authenticated_bob',
      );

      await enqueueMutation(
        db: db,
        table: 'vouchers',
        recordId: 'v_secret_other',
        type: 'UPSERT',
        fullRowMap: {
          'id': 'v_secret_other',
          'company_id': otherWorkspace,
          'voucher_number': 'V-SECRET',
        },
      );

      final resultDefault = await authEngine.pushQueue(companyId: 'cmp_default');
      expect(resultDefault.status, SyncEngineStatus.success);

      // Verify v_secret_other was NOT pushed
      expect(gateway.tables['vouchers']?['v_secret_other'], isNull);

      final outboxRow = await (db.select(db.syncOutbox)..where((t) => t.recordId.equals('v_secret_other'))).getSingleOrNull();
      expect(outboxRow, isNotNull);

      // Guest session CAN sync cmp_default
      final guestEngine = SyncEngine(
        db: db,
        gateway: gateway,
        activeUserId: null,
      );

      await enqueueMutation(
        db: db,
        table: 'vouchers',
        recordId: 'v_guest_item',
        type: 'UPSERT',
        fullRowMap: {
          'id': 'v_guest_item',
          'company_id': 'cmp_default',
          'voucher_number': 'V-GUEST',
        },
      );

      final guestResult = await guestEngine.pushQueue(companyId: 'cmp_default');
      expect(guestResult.status, SyncEngineStatus.success);
      expect(gateway.tables['vouchers']?['v_guest_item'], isNotNull);
    });

    // =========================================================================
    // PROMPT 6.3 TESTS: STALE OUTBOX UPLOAD & IN-PROGRESS SESSION INVALIDATION
    // =========================================================================

    // 49. Stale outbox upload prevention: does not upload stale outbox row when latest mutation fails enqueue
    test('49. Stale outbox upload prevention: does not upload stale outbox row when latest mutation fails enqueue', () async {
      // 1. Existing outbox entry with old payload (revision 1, subtotal 1000)
      await enqueueMutation(
        db: db,
        table: 'vouchers',
        recordId: 'v_stale_prevent',
        type: 'UPSERT',
        fullRowMap: {
          'id': 'v_stale_prevent',
          'company_id': testCompanyId,
          'voucher_number': 'V-STALE-OLD',
          'subtotalInCents': 1000,
          'totalAmountInCents': 1000,
          'revision': 1,
        },
      );

      // 2. Local voucher is modified with latest mutation (revision 2, subtotal 2500) and syncStatus pending
      await db.into(db.vouchers).insert(
        VouchersCompanion(
          id: const drift.Value('v_stale_prevent'),
          companyId: const drift.Value(testCompanyId),
          voucherNumber: const drift.Value('V-STALE-NEW'),
          type: const drift.Value('expense'),
          date: drift.Value(DateTime.now()),
          status: const drift.Value('draft'),
          paymentMode: const drift.Value('cash'),
          subtotalInCents: const drift.Value(2500),
          taxInCents: const drift.Value(0),
          discountInCents: const drift.Value(0),
          totalAmountInCents: const drift.Value(2500),
          revision: const drift.Value(2),
          syncStatus: const drift.Value(SyncRecordStatus.pending),
        ),
      );

      // 3. Unrelated record that succeeds
      await db.into(db.parties).insert(
        PartiesCompanion(
          id: const drift.Value('p_unrelated_ok'),
          companyId: const drift.Value(testCompanyId),
          name: const drift.Value('Unrelated Party'),
          phoneNumber: const drift.Value('9876543210'),
          type: const drift.Value(PartyType.supplier),
          lastUpdated: drift.Value(DateTime.now()),
          syncStatus: const drift.Value(SyncRecordStatus.pending),
        ),
      );

      // 4. Hook simulates enqueue failure specifically for v_stale_prevent
      syncEngine.onEnqueueMutation = (table, recordId) async {
        if (recordId == 'v_stale_prevent') {
          throw Exception('Simulated outbox enqueue failure for v_stale_prevent');
        }
      };

      final result = await syncEngine.pushQueue(companyId: testCompanyId);

      // Partial status reported
      expect(result.status, SyncEngineStatus.partial);
      expect(result.tableErrors.containsKey('vouchers:v_stale_prevent'), isTrue);
      expect(result.tableErrors['vouchers:v_stale_prevent'], contains('Simulated outbox enqueue failure'));

      // Old outbox entry was NOT uploaded to gateway
      expect(gateway.tables['vouchers']?['v_stale_prevent'], isNull);

      // Local record was NOT marked synced
      final localVoucher = await (db.select(db.vouchers)..where((t) => t.id.equals('v_stale_prevent'))).getSingle();
      expect(localVoucher.syncStatus, SyncRecordStatus.pending);

      // Existing outbox entry was NOT deleted and payload was preserved
      final outboxVoucher = await (db.select(db.syncOutbox)..where((t) => t.recordId.equals('v_stale_prevent'))).getSingleOrNull();
      expect(outboxVoucher, isNotNull);
      final preservedPayload = jsonDecode(outboxVoucher!.payload) as Map<String, dynamic>;
      expect(preservedPayload['subtotalInCents'], 1000);
      expect(preservedPayload['revision'], 1);

      // Unrelated record DID sync successfully
      expect(gateway.tables['parties']?['p_unrelated_ok'], isNotNull);
      final localParty = await (db.select(db.parties)..where((t) => t.id.equals('p_unrelated_ok'))).getSingle();
      expect(localParty.syncStatus, SyncRecordStatus.synced);
      expect(result.pushedCount, 1);
    });

    // 50. Retry after enqueue failure resolved pushes latest mutation with latest payload
    test('50. Retry after enqueue failure resolved pushes latest mutation with latest payload', () async {
      await enqueueMutation(
        db: db,
        table: 'vouchers',
        recordId: 'v_stale_retry',
        type: 'UPSERT',
        fullRowMap: {
          'id': 'v_stale_retry',
          'company_id': testCompanyId,
          'voucher_number': 'V-STALE-OLD',
          'subtotalInCents': 1000,
          'totalAmountInCents': 1000,
          'revision': 1,
        },
      );

      await db.into(db.vouchers).insert(
        VouchersCompanion(
          id: const drift.Value('v_stale_retry'),
          companyId: const drift.Value(testCompanyId),
          voucherNumber: const drift.Value('V-STALE-LATEST'),
          type: const drift.Value('expense'),
          date: drift.Value(DateTime.now()),
          status: const drift.Value('draft'),
          paymentMode: const drift.Value('cash'),
          subtotalInCents: const drift.Value(3000),
          taxInCents: const drift.Value(0),
          discountInCents: const drift.Value(0),
          totalAmountInCents: const drift.Value(3000),
          revision: const drift.Value(2),
          syncStatus: const drift.Value(SyncRecordStatus.pending),
        ),
      );

      // First run: enqueue failure triggers
      syncEngine.onEnqueueMutation = (table, recordId) async {
        if (recordId == 'v_stale_retry') {
          throw Exception('Disk I/O error');
        }
      };

      final failResult = await syncEngine.pushQueue(companyId: testCompanyId);
      expect(failResult.status, SyncEngineStatus.partial);
      expect(gateway.tables['vouchers']?['v_stale_retry'], isNull);

      // Second run: enqueue issue resolved
      syncEngine.onEnqueueMutation = null;

      final successResult = await syncEngine.pushQueue(companyId: testCompanyId);
      expect(successResult.status, SyncEngineStatus.success);
      expect(successResult.tableErrors, isEmpty);
      expect(successResult.pushedCount, 1);

      // Remote gateway has the LATEST payload (subtotal 3000, revision 2)
      final remoteVoucher = gateway.tables['vouchers']?['v_stale_retry'];
      expect(remoteVoucher, isNotNull);
      expect(remoteVoucher!['subtotal_in_cents'], 3000);
      expect(remoteVoucher['revision'], 2);

      // Local record is marked synced
      final local = await (db.select(db.vouchers)..where((t) => t.id.equals('v_stale_retry'))).getSingle();
      expect(local.syncStatus, SyncRecordStatus.synced);

      // Outbox row is deleted
      final outbox = await (db.select(db.syncOutbox)..where((t) => t.recordId.equals('v_stale_retry'))).getSingleOrNull();
      expect(outbox, isNull);
    });

    // 51. Enqueue failure on a new record without prior outbox entry reports partial and leaves record pending
    test('51. Enqueue failure on a new record without prior outbox entry reports partial and leaves record pending', () async {
      await db.into(db.vouchers).insert(
        VouchersCompanion(
          id: const drift.Value('v_new_fail'),
          companyId: const drift.Value(testCompanyId),
          voucherNumber: const drift.Value('V-NEW-FAIL'),
          type: const drift.Value('expense'),
          date: drift.Value(DateTime.now()),
          status: const drift.Value('draft'),
          paymentMode: const drift.Value('cash'),
          subtotalInCents: const drift.Value(1500),
          taxInCents: const drift.Value(0),
          discountInCents: const drift.Value(0),
          totalAmountInCents: const drift.Value(1500),
          syncStatus: const drift.Value(SyncRecordStatus.pending),
        ),
      );

      syncEngine.onEnqueueMutation = (table, recordId) async {
        if (recordId == 'v_new_fail') {
          throw Exception('Database constraint on sync_outbox');
        }
      };

      final result = await syncEngine.pushQueue(companyId: testCompanyId);
      expect(result.status, SyncEngineStatus.partial);
      expect(result.tableErrors.containsKey('vouchers:v_new_fail'), isTrue);
      expect(gateway.tables['vouchers']?['v_new_fail'], isNull);

      final local = await (db.select(db.vouchers)..where((t) => t.id.equals('v_new_fail'))).getSingle();
      expect(local.syncStatus, SyncRecordStatus.pending);

      final outbox = await (db.select(db.syncOutbox)..where((t) => t.recordId.equals('v_new_fail'))).getSingleOrNull();
      expect(outbox, isNull);
    });

    // 52. In-progress session invalidation inside mark-synced transaction rolls back local update and retains outbox row
    test('52. In-progress session invalidation inside mark-synced transaction rolls back local update and retains outbox row', () async {
      await db.into(db.vouchers).insert(
        VouchersCompanion(
          id: const drift.Value('v_tx_rollback'),
          companyId: const drift.Value(testCompanyId),
          voucherNumber: const drift.Value('V-TX-ROLLBACK'),
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

      syncEngine.onInsideMarkSyncedTransaction = () async {
        syncEngine.invalidateSession();
      };

      final result = await syncEngine.pushQueue(companyId: testCompanyId);
      expect(result.status, SyncEngineStatus.idle);

      // Local record must NOT be synced — transaction rolled back to pending!
      final local = await (db.select(db.vouchers)..where((t) => t.id.equals('v_tx_rollback'))).getSingle();
      expect(local.syncStatus, SyncRecordStatus.pending);

      // Outbox row must NOT be deleted — transaction rolled back and retained it!
      final outbox = await (db.select(db.syncOutbox)..where((t) => t.recordId.equals('v_tx_rollback'))).getSingleOrNull();
      expect(outbox, isNotNull);
    });

    // 53. In-progress session invalidation inside permanent failure transaction rolls back error updates
    test('53. In-progress session invalidation inside permanent failure transaction rolls back error updates', () async {
      await db.into(db.vouchers).insert(
        VouchersCompanion(
          id: const drift.Value('v_err_rollback'),
          companyId: const drift.Value(testCompanyId),
          voucherNumber: const drift.Value('V-ERR-ROLLBACK'),
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

      final customGateway = _CustomExceptionGateway(
        gateway,
        onUpsert: (table, row) {
          if (row['id'] == 'v_err_rollback') {
            throw const PostgrestException(
              message: 'violates check constraint',
              code: '23514',
            );
          }
        },
      );

      final engine = SyncEngine(
        db: db,
        gateway: customGateway,
      );

      engine.onInsideMarkErrorTransaction = () async {
        engine.invalidateSession();
      };

      final result = await engine.pushQueue(companyId: testCompanyId);
      expect(result.status, SyncEngineStatus.idle);

      // Local record must NOT have syncStatus error — rolled back to pending!
      final local = await (db.select(db.vouchers)..where((t) => t.id.equals('v_err_rollback'))).getSingle();
      expect(local.syncStatus, SyncRecordStatus.pending);

      // Outbox entry must NOT have lastError or nextAttemptAt null — rolled back!
      final outbox = await (db.select(db.syncOutbox)..where((t) => t.recordId.equals('v_err_rollback'))).getSingleOrNull();
      expect(outbox, isNotNull);
      expect(outbox!.lastError, isNull);
    });

    // 54. In-progress session invalidation inside multi-row pull page rolls back all rows in the page
    test('54. In-progress session invalidation inside multi-row pull page rolls back all rows in the page', () async {
      final t = DateTime.utc(2026, 6, 1, 10, 0, 0);
      for (int i = 1; i <= 3; i++) {
        gateway.tables.putIfAbsent('vouchers', () => {})['v_batch_$i'] = {
          'id': 'v_batch_$i',
          'company_id': testCompanyId,
          'voucher_number': 'V-BATCH-$i',
          'date': encodeTime(t),
          'created_at': encodeTime(t),
          'updated_at': encodeTime(t.add(Duration(seconds: i))),
          'is_deleted': false,
        };
      }

      syncEngine.onInsidePullRow = (table, recordId, rowIndex) async {
        if (table == 'vouchers' && rowIndex == 1) {
          syncEngine.invalidateSession();
        }
      };

      final result = await syncEngine.pullChanges(companyId: testCompanyId);
      expect(result.status, SyncEngineStatus.idle);

      // NONE of the 3 vouchers should exist in local DB: transaction rolled back row 0 and 1!
      for (int i = 1; i <= 3; i++) {
        final local = await (db.select(db.vouchers)..where((t) => t.id.equals('v_batch_$i'))).getSingleOrNull();
        expect(local, isNull, reason: 'v_batch_$i should have rolled back');
      }

      // Cursor must NOT have advanced
      final cursor = await (db.select(db.syncState)
            ..where((t) => t.targetTable.equals('vouchers') & t.companyId.equals(testCompanyId)))
          .getSingleOrNull();
      expect(cursor, isNull);
    });

    // 55. In-progress session invalidation during remote soft delete rolls back soft delete
    test('55. In-progress session invalidation during remote soft delete rolls back soft delete', () async {
      await db.into(db.vouchers).insert(
        VouchersCompanion(
          id: const drift.Value('v_soft_del_rollback'),
          companyId: const drift.Value(testCompanyId),
          voucherNumber: const drift.Value('V-SOFT-DEL'),
          type: const drift.Value('expense'),
          date: drift.Value(DateTime.now()),
          status: const drift.Value('posted'),
          paymentMode: const drift.Value('cash'),
          subtotalInCents: const drift.Value(1000),
          taxInCents: const drift.Value(0),
          discountInCents: const drift.Value(0),
          totalAmountInCents: const drift.Value(1000),
          isDeleted: const drift.Value(false),
          syncStatus: const drift.Value(SyncRecordStatus.synced),
        ),
      );

      final t = DateTime.utc(2026, 6, 2, 10, 0, 0);
      gateway.tables.putIfAbsent('vouchers', () => {})['v_soft_del_rollback'] = {
        'id': 'v_soft_del_rollback',
        'company_id': testCompanyId,
        'voucher_number': 'V-SOFT-DEL',
        'date': encodeTime(t),
        'created_at': encodeTime(t),
        'updated_at': encodeTime(t),
        'is_deleted': true,
      };

      syncEngine.onInsidePullRow = (table, recordId, index) async {
        if (recordId == 'v_soft_del_rollback') {
          syncEngine.invalidateSession();
        }
      };

      final result = await syncEngine.pullChanges(companyId: testCompanyId);
      expect(result.status, SyncEngineStatus.idle);

      // Local record must NOT be soft deleted: transaction was rolled back!
      final local = await (db.select(db.vouchers)..where((t) => t.id.equals('v_soft_del_rollback'))).getSingle();
      expect(local.isDeleted, isFalse);
    });

    // 56. In-progress session invalidation inside cursor persistence transaction prevents cursor update
    test('56. In-progress session invalidation inside cursor persistence transaction prevents cursor update', () async {
      final t = DateTime.utc(2026, 6, 3, 10, 0, 0);
      gateway.tables.putIfAbsent('vouchers', () => {})['v_cursor_tx'] = {
        'id': 'v_cursor_tx',
        'company_id': testCompanyId,
        'voucher_number': 'V-CURSOR-TX',
        'date': encodeTime(t),
        'created_at': encodeTime(t),
        'updated_at': encodeTime(t),
        'is_deleted': false,
      };

      syncEngine.onInsideCursorTransaction = () async {
        syncEngine.invalidateSession();
      };

      final result = await syncEngine.pullChanges(companyId: testCompanyId);
      expect(result.status, SyncEngineStatus.idle);

      final cursor = await (db.select(db.syncState)
            ..where((t) => t.targetTable.equals('vouchers') & t.companyId.equals(testCompanyId)))
          .getSingleOrNull();
      expect(cursor, isNull);
    });

    // 57. Interrupted pull safely retries in subsequent valid session and reconciles completely
    test('57. Interrupted pull safely retries in subsequent valid session and reconciles completely', () async {
      final t = DateTime.utc(2026, 6, 4, 10, 0, 0);
      for (int i = 1; i <= 3; i++) {
        gateway.tables.putIfAbsent('vouchers', () => {})['v_recon_$i'] = {
          'id': 'v_recon_$i',
          'company_id': testCompanyId,
          'voucher_number': 'V-RECON-$i',
          'date': encodeTime(t),
          'created_at': encodeTime(t),
          'updated_at': encodeTime(t.add(Duration(seconds: i))),
          'is_deleted': false,
        };
      }

      // First run: interrupted midway
      syncEngine.onInsidePullRow = (table, recordId, index) async {
        if (table == 'vouchers' && index == 1) {
          syncEngine.invalidateSession();
        }
      };

      final firstResult = await syncEngine.pullChanges(companyId: testCompanyId);
      expect(firstResult.status, SyncEngineStatus.idle);

      for (int i = 1; i <= 3; i++) {
        final r = await (db.select(db.vouchers)..where((t) => t.id.equals('v_recon_$i'))).getSingleOrNull();
        expect(r, isNull);
      }

      // Second run: fresh valid session
      syncEngine.onInsidePullRow = null;
      final secondResult = await syncEngine.pullChanges(companyId: testCompanyId);
      expect(secondResult.status, SyncEngineStatus.success);
      expect(secondResult.pulledCount, 3);

      for (int i = 1; i <= 3; i++) {
        final r = await (db.select(db.vouchers)..where((t) => t.id.equals('v_recon_$i'))).getSingle();
        expect(r.syncStatus, SyncRecordStatus.synced);
      }

      final cursor = await (db.select(db.syncState)
            ..where((t) => t.targetTable.equals('vouchers') & t.companyId.equals(testCompanyId)))
          .getSingleOrNull();
      expect(cursor, isNotNull);
      expect(cursor!.lastPulledAt!.toUtc(), equals(t.add(const Duration(seconds: 3))));
    });

    // 58. Subsequent valid session safely retries push after interrupted acknowledgement
    test('58. Subsequent valid session safely retries push after interrupted acknowledgement', () async {
      await db.into(db.vouchers).insert(
        VouchersCompanion(
          id: const drift.Value('v_push_recon'),
          companyId: const drift.Value(testCompanyId),
          voucherNumber: const drift.Value('V-PUSH-RECON'),
          type: const drift.Value('expense'),
          date: drift.Value(DateTime.now()),
          status: const drift.Value('draft'),
          paymentMode: const drift.Value('cash'),
          subtotalInCents: const drift.Value(7500),
          taxInCents: const drift.Value(0),
          discountInCents: const drift.Value(0),
          totalAmountInCents: const drift.Value(7500),
          syncStatus: const drift.Value(SyncRecordStatus.pending),
        ),
      );

      // First run: interrupted inside markSynced transaction
      syncEngine.onInsideMarkSyncedTransaction = () async {
        syncEngine.invalidateSession();
      };

      final firstResult = await syncEngine.pushQueue(companyId: testCompanyId);
      expect(firstResult.status, SyncEngineStatus.idle);

      // Local record remains pending, outbox entry retained
      final localBefore = await (db.select(db.vouchers)..where((t) => t.id.equals('v_push_recon'))).getSingle();
      expect(localBefore.syncStatus, SyncRecordStatus.pending);
      final outboxBefore = await (db.select(db.syncOutbox)..where((t) => t.recordId.equals('v_push_recon'))).getSingleOrNull();
      expect(outboxBefore, isNotNull);

      // Second run: valid session retries push
      syncEngine.onInsideMarkSyncedTransaction = null;
      final secondResult = await syncEngine.pushQueue(companyId: testCompanyId);
      expect(secondResult.status, SyncEngineStatus.success);
      expect(secondResult.pushedCount, 1);

      // Local record is marked synced
      final localAfter = await (db.select(db.vouchers)..where((t) => t.id.equals('v_push_recon'))).getSingle();
      expect(localAfter.syncStatus, SyncRecordStatus.synced);

      // Outbox entry deleted
      final outboxAfter = await (db.select(db.syncOutbox)..where((t) => t.recordId.equals('v_push_recon'))).getSingleOrNull();
      expect(outboxAfter, isNull);
    });
  });
}

class _PageSizeForcingGateway implements RemoteGateway {
  final RemoteGateway delegate;
  final int forcedPageSize;

  _PageSizeForcingGateway(this.delegate, {required this.forcedPageSize});

  @override
  Future<Map<String, dynamic>?> upsertRow({
    required String table,
    required Map<String, dynamic> row,
  }) => delegate.upsertRow(table: table, row: row);

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
  }) {
    return delegate.pullRows(
      table: table,
      companyId: companyId,
      activeUserId: activeUserId,
      cursor: cursor,
      pageSize: forcedPageSize,
      offset: offset,
      afterUpdatedAt: afterUpdatedAt,
      afterId: afterId,
    );
  }
}

class _InterleavingGateway implements RemoteGateway {
  final RemoteGateway delegate;
  final int forcedPageSize;
  final void Function(String table, int pageNumber) onPagePulled;
  final Map<String, int> _tablePageCounts = {};

  _InterleavingGateway(
    this.delegate, {
    required this.forcedPageSize,
    required this.onPagePulled,
  });

  @override
  Future<Map<String, dynamic>?> upsertRow({
    required String table,
    required Map<String, dynamic> row,
  }) => delegate.upsertRow(table: table, row: row);

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
    final pageNum = (_tablePageCounts[table] ?? 0) + 1;
    _tablePageCounts[table] = pageNum;
    final rows = await delegate.pullRows(
      table: table,
      companyId: companyId,
      activeUserId: activeUserId,
      cursor: cursor,
      pageSize: forcedPageSize,
      offset: offset,
      afterUpdatedAt: afterUpdatedAt,
      afterId: afterId,
    );
    onPagePulled(table, pageNum);
    return rows;
  }
}


class _DelayHoldingGateway implements RemoteGateway {
  final RemoteGateway delegate;
  final Completer<Map<String, dynamic>?> holdCompleter;
  final Completer<void> requestStarted = Completer<void>();

  _DelayHoldingGateway(this.delegate, {required this.holdCompleter});

  @override
  Future<Map<String, dynamic>?> upsertRow({
    required String table,
    required Map<String, dynamic> row,
  }) async {
    if (!requestStarted.isCompleted) {
      requestStarted.complete();
    }
    return holdCompleter.future;
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
  }) {
    return delegate.pullRows(
      table: table,
      companyId: companyId,
      activeUserId: activeUserId,
      cursor: cursor,
      pageSize: pageSize,
      offset: offset,
      afterUpdatedAt: afterUpdatedAt,
      afterId: afterId,
    );
  }
}

class _RecordingHttpClient extends http.BaseClient {
  http.BaseRequest? lastRequest;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    lastRequest = request;
    const jsonResponse = '[]';
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonResponse)),
      200,
      request: request,
      headers: {
        'content-type': 'application/json',
        'content-range': '0-0/0',
      },
    );
  }
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
    String? activeUserId,
    DateTime? cursor,
    int pageSize = 500,
    int offset = 0,
    DateTime? afterUpdatedAt,
    String? afterId,
  }) {
    return delegate.pullRows(
      table: table,
      companyId: companyId,
      activeUserId: activeUserId,
      cursor: cursor,
      pageSize: pageSize,
      offset: offset,
      afterUpdatedAt: afterUpdatedAt,
      afterId: afterId,
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
    String? activeUserId,
    DateTime? cursor,
    int pageSize = 500,
    int offset = 0,
    DateTime? afterUpdatedAt,
    String? afterId,
  }) {
    return delegate.pullRows(
      table: table,
      companyId: companyId,
      activeUserId: activeUserId,
      cursor: cursor,
      pageSize: pageSize,
      offset: offset,
      afterUpdatedAt: afterUpdatedAt,
      afterId: afterId,
    );
  }
}
