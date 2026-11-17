import 'dart:convert';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ledger_pulse/core/network/sync_engine.dart';
import 'package:ledger_pulse/data/local/database.dart';
import 'package:ledger_pulse/data/local/outbox_helper.dart';
import 'support/fake_remote_gateway.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const user = '00000000-0000-4000-8000-000000000001';
  const profile = 'profile_bootstrap_recovery';

  test(
    'Repairs profile schema and dependent failures without touching other workspaces',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final remote = _ProfileSchemaGateway();
      final engine = SyncEngine(
        db: db,
        activeUserId: user,
        fakeRemoteStore: remote,
        simulateSyncForTesting: true,
      );
      addTearDown(() async {
        engine.dispose();
        await db.close();
      });
      await db
          .into(db.profiles)
          .insert(
            ProfilesCompanion.insert(
              id: profile,
              name: 'Recovery',
              ownerId: const Value(user),
              profileType: const Value('ledger'),
              syncStatus: const Value(SyncRecordStatus.error),
            ),
          );
      await db
          .into(db.companies)
          .insert(
            CompaniesCompanion.insert(
              id: profile,
              profileId: const Value(profile),
              name: 'Recovery',
              legalName: 'Recovery',
              mode: const Value('ledger'),
              ownerId: const Value(user),
              syncStatus: const Value(SyncRecordStatus.error),
            ),
          );
      const member = '00000000-0000-4000-8000-000000000002';
      await db
          .into(db.sharedMemberships)
          .insert(
            SharedMembershipsCompanion.insert(
              id: member,
              profileId: profile,
              accountId: user,
              role: 'owner',
            ),
          );
      for (final table in ['profiles', 'companies', 'shared_memberships']) {
        final id = table == 'shared_memberships' ? member : profile;
        await enqueueMutation(
          db: db,
          table: table,
          recordId: id,
          type: 'UPSERT',
          fullRowMap: {
            'id': id,
            'companyId': profile,
            'profile_id': profile,
            'name': 'Recovery',
            'owner_id': user,
            'account_id': user,
            'role': 'owner',
            'profile_type': 'ledger',
          'settings_json': jsonEncode({'enabled_modules': ['vouchers']}),
          },
        );
        await (db.update(
          db.syncOutbox,
        )..where((t) => t.recordId.equals(id) & t.targetTable.equals(table))).write(
          SyncOutboxCompanion(
            attempts: const Value(1),
            lastError: Value(
              table == 'profiles'
                  ? 'Permanent failure: PGRST204 company_id column not found'
                  : table == 'companies'
                  ? 'Permanent failure: 23503 missing profiles parent'
                  : 'Permanent failure: 42703 record new has no field revision',
            ),
          ),
        );
      }
      await enqueueMutation(
        db: db,
        table: 'profiles',
        recordId: 'other_workspace',
        type: 'UPSERT',
        fullRowMap: {'id': 'other_workspace', 'owner_id': user},
      );
      await (db.update(
        db.syncOutbox,
      )..where((t) => t.recordId.equals('other_workspace'))).write(
        const SyncOutboxCompanion(
          attempts: Value(1),
          lastError: Value('Permanent failure: PGRST204 company_id'),
        ),
      );
      final result = await engine.pushQueue(companyId: profile);
      expect(result.success, isTrue, reason: result.tableErrors.toString());
      expect(remote.getRow('profiles', profile), isNotNull);
      expect(remote.getRow('profiles', profile)!['settings_json'], {'enabled_modules': ['vouchers']});
      expect(
        remote.getRow('profiles', profile)!.containsKey('company_id'),
        isFalse,
      );
      expect(remote.getRow('companies', profile), isNotNull);
      expect(remote.getRow('shared_memberships', member), isNotNull);
      final remaining = await db.select(db.syncOutbox).get();
      expect(remaining.single.recordId, 'other_workspace');
      expect(remaining.single.lastError, contains('PGRST204'));
    },
  );

  test(
    'Expense dependencies recover and parent categories upload before older child mutations',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final remote = _ProfileSchemaGateway();
      final engine = SyncEngine(
        db: db,
        activeUserId: user,
        fakeRemoteStore: remote,
        simulateSyncForTesting: true,
      );
      addTearDown(() async {
        engine.dispose();
        await db.close();
      });
      await db
          .into(db.profiles)
          .insert(
            ProfilesCompanion.insert(
              id: profile,
              name: 'Expense',
              syncStatus: const Value(SyncRecordStatus.synced),
            ),
          );
      await db
          .into(db.companies)
          .insert(
            CompaniesCompanion.insert(
              id: profile,
              name: 'Expense',
              legalName: 'Expense',
              mode: const Value('expense'),
              syncStatus: const Value(SyncRecordStatus.synced),
            ),
          );
      final now = DateTime.now();
      await db
          .into(db.expenseCategories)
          .insert(
            ExpenseCategoriesCompanion.insert(
              id: 'parent',
              profileId: profile,
              name: 'Parent',
              categoryType: const Value('expense'),
              createdAt: Value(now.add(const Duration(days: 1))),
            ),
          );
      await db
          .into(db.expenseCategories)
          .insert(
            ExpenseCategoriesCompanion.insert(
              id: 'child',
              profileId: profile,
              name: 'Child',
              categoryType: const Value('expense'),
              parentCategoryId: const Value('parent'),
              syncStatus: const Value(SyncRecordStatus.error),
            ),
          );
      await db
          .into(db.expenseWallets)
          .insert(
            ExpenseWalletsCompanion.insert(
              id: 'wallet',
              profileId: profile,
              name: 'Cash',
            ),
          );
      await db
          .into(db.expenseBudgets)
          .insert(
            ExpenseBudgetsCompanion.insert(
              id: 'overall',
              profileId: profile,
              amountInCents: 10000,
              startDate: now,
              syncStatus: const Value(SyncRecordStatus.error),
            ),
          );
      await db
          .into(db.expenseTransactions)
          .insert(
            ExpenseTransactionsCompanion.insert(
              id: 'expense',
              profileId: profile,
              transactionType: 'expense',
              amountInCents: 500,
              walletId: 'wallet',
              categoryId: const Value('child'),
              transactionDate: now,
              syncStatus: const Value(SyncRecordStatus.error),
            ),
          );
      for (final item in [
        ('exp_categories', 'child', '23503 parent_category_id'),
        ('exp_budgets', 'overall', '23502 category_id'),
        ('exp_transactions', 'expense', '23503 category_id'),
      ]) {
        await enqueueMutation(
          db: db,
          table: item.$1,
          recordId: item.$2,
          type: 'UPSERT',
          fullRowMap: {'id': item.$2, 'profile_id': profile},
        );
        await (db.update(
          db.syncOutbox,
        )..where((t) => t.recordId.equals(item.$2))).write(
          SyncOutboxCompanion(
            lastError: Value('Permanent failure: ${item.$3}'),
            attempts: const Value(1),
          ),
        );
      }
      final result = await engine.pushQueue(companyId: profile);
      expect(result.success, isTrue, reason: result.tableErrors.toString());
      expect(
        remote.getRow('exp_categories', 'child')!['parent_category_id'],
        'parent',
      );
      expect(remote.getRow('exp_budgets', 'overall')!['category_id'], isNull);
      expect(
        remote.getRow('exp_transactions', 'expense')!['category_id'],
        'child',
      );
      expect(await db.select(db.syncOutbox).get(), isEmpty);
    },
  );

  test('Profile JSONB settings decode into the local JSON text column', () {
    final descriptor = SyncEngine.syncTables.firstWhere((table) => table.name == 'profiles');
    final row = descriptor.fromRemote({'id': profile, 'name': 'Profile',
      'profile_type': 'expense', 'settings_json': {'enabled_modules': ['budgets']}}) as ProfilesCompanion;
    expect(jsonDecode(row.settingsJson.value!), {'enabled_modules': ['budgets']});
  });

  test(
    'Profile pulls filter by id rather than the nonexistent company_id',
    () async {
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-key',
        httpClient: MockClient((request) async {
          expect(request.url.path, '/rest/v1/profiles');
          expect(request.url.queryParameters['id'], 'eq.$profile');
          expect(
            request.url.queryParameters.containsKey('company_id'),
            isFalse,
          );
          return http.Response(
            '[]',
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      addTearDown(client.dispose);
      expect(
        await SupabaseGateway(
          client,
        ).pullRows(table: 'profiles', companyId: profile),
        isEmpty,
      );
    },
  );
}

class _ProfileSchemaGateway extends FakeGateway {
  @override
  Future<Map<String, dynamic>?> upsertRow({
    required String table,
    required Map<String, dynamic> row,
  }) {
    if (table == 'profiles') {
      const valid = {
        'id',
        'owner_id',
        'name',
        'profile_type',
        'mode',
        'currency_code',
        'settings_json',
        'is_active',
        'is_deleted',
        'revision',
        'created_at',
        'updated_at',
      };
      expect(
        row.keys.every(valid.contains),
        isTrue,
        reason: row.keys.toString(),
      );
    }
    if (table == 'companies' || table == 'shared_memberships') {
      expect(
        getRow('profiles', row['profile_id'] as String),
        isNotNull,
        reason: 'The parent profile must be uploaded first',
      );
    }
    if (table == 'exp_categories' && row['parent_category_id'] != null) {
      expect(
        getRow('exp_categories', row['parent_category_id'] as String),
        isNotNull,
      );
    }
    if (table == 'exp_transactions' && row['category_id'] != null) {
      expect(getRow('exp_categories', row['category_id'] as String), isNotNull);
    }
    return super.upsertRow(table: table, row: row);
  }
}
