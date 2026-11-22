import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value, Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ledger_pulse/core/network/drift_workspace_replica.dart';
import 'package:ledger_pulse/core/network/sync_engine.dart' show SyncEngine;
import 'package:ledger_pulse/core/network/workspace_sync_engine.dart';
import 'package:ledger_pulse/data/local/database.dart';
import 'package:ledger_pulse/data/local/outbox_helper.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show PostgrestException, SupabaseClient;
import 'package:uuid/uuid.dart';

import 'support/fake_remote_gateway.dart';

const actor = '10000000-0000-4000-8000-000000000001';
const otherActor = '10000000-0000-4000-8000-000000000002';
const workspace = '20000000-0000-4000-8000-000000000001';
const otherWorkspace = '20000000-0000-4000-8000-000000000002';
const recordId = '30000000-0000-4000-8000-000000000001';
const uuid = Uuid();

void main() {
  test(
    'app sync promotes a scoped Expense category into the command queue',
    () async {
      final server = _Server();
      final device = await _device(_Gateway(server));
      addTearDown(device.db.close);
      final sync = SyncEngine(
        db: device.db,
        activeUserId: actor,
        workspaceSync: device.engine,
      );
      addTearDown(sync.dispose);
      await device.db
          .into(device.db.profiles)
          .insert(
            ProfilesCompanion.insert(
              id: workspace,
              name: 'Expense',
              ownerId: const Value(actor),
            ),
          );
      await device.db
          .into(device.db.expenseCategories)
          .insert(
            ExpenseCategoriesCompanion.insert(
              id: recordId,
              profileId: workspace,
              name: 'Food',
            ),
          );
      await enqueueMutation(
        db: device.db,
        table: 'exp_categories',
        recordId: recordId,
        type: 'INSERT',
        fullRowMap: {
          'id': recordId,
          'profile_id': workspace,
          'name': 'Food',
          'category_type': 'expense',
        },
      );
      final pending = await device.db.select(device.db.syncOutbox).getSingle();
      expect((await sync.syncAll(companyId: workspace)).success, isTrue);
      expect(await device.db.select(device.db.syncOutbox).get(), isEmpty);
      expect(server.receipts[(workspace, pending.id)], isNotNull);
      expect((await sync.syncAll(companyId: workspace)).success, isTrue);
      expect(server.commits[workspace], hasLength(1));

      await enqueueMutation(
        db: device.db,
        table: 'exp_transactions',
        recordId: uuid.v4(),
        type: 'INSERT',
        fullRowMap: {
          'profile_id': workspace,
          'receipt_photo_url': '/local/receipt.jpg',
        },
      );
      expect((await sync.syncAll(companyId: workspace)).success, isFalse);
      expect(
        (await device.db.select(device.db.syncOutbox).getSingle()).payload,
        contains('/local/receipt.jpg'),
      );
      expect(server.commits[workspace], hasLength(1));
    },
  );

  test(
    'Drift expense projection reconciles an atomic transfer and tombstone',
    () async {
      final db = AppDatabase(NativeDatabase.memory(), actor);
      addTearDown(db.close);
      final replica = DriftWorkspaceReplica(db);
      const source = '30000000-0000-4000-8000-000000000002';
      const destination = '30000000-0000-4000-8000-000000000003';
      const timestamp = '2026-01-01T00:00:00Z';

      WorkspaceChange wallet(String id, String opening) => WorkspaceChange(
        'expense_wallets',
        {'id': id},
        {
          'id': id,
          'workspace_id': workspace,
          'name': id,
          'wallet_type': 'cash',
          'opening_balance_minor': opening,
          'created_at': timestamp,
          'updated_at': timestamp,
          'revision': '1',
        },
      );
      WorkspaceChange transfer({
        bool deleted = false,
        String scope = workspace,
      }) => WorkspaceChange(
        'expense_transactions',
        {'id': recordId},
        {
          'id': recordId,
          'workspace_id': scope,
          'transaction_type': 'transfer',
          'wallet_id': source,
          'to_wallet_id': destination,
          'amount_minor': '30',
          'occurred_at': timestamp,
          'created_at': timestamp,
          'updated_at': timestamp,
          'revision': deleted ? '2' : '1',
          'deleted_at': deleted ? timestamp : null,
        },
      );
      Future<Map<String, int>> balances() async => {
        for (final row in await db.select(db.expenseWallets).get())
          row.id: row.currentBalanceInCents,
      };

      await db.transaction(
        () => replica.replaceSnapshot(workspace, [
          const WorkspaceChange(
            'workspaces',
            {'id': workspace},
            {
              'id': workspace,
              'owner_user_id': actor,
              'workspace_type': 'expense',
              'lifecycle_state': 'active',
              'name': 'Expense',
              'currency_code': 'INR',
              'created_at': timestamp,
              'updated_at': timestamp,
              'revision': '1',
            },
          ),
          wallet(source, '100'),
          wallet(destination, '20'),
          WorkspaceChange('expense_recurring_rules', {'id': recordId}, {
            'id': recordId,
            'workspace_id': workspace,
            'transaction_type': 'expense',
            'wallet_id': source,
            'amount_minor': '30',
            'interval_unit': 'month',
            'interval_count': 1,
            'next_occurrence_on': '2026-02-01',
            'ends_on': '2026-12-31',
            'is_active': true,
            'created_at': timestamp,
            'updated_at': timestamp,
            'revision': '1',
          }),
          transfer(),
        ]),
      );
      expect(await balances(), {source: 70, destination: 50});
      final rule = await db.select(db.expenseRecurringRules).getSingle();
      expect(rule.nextRunDate, DateTime(2026, 2, 1));
      expect(rule.endDate, DateTime(2026, 12, 31));
      await expectLater(
        db.transaction(
          () => replica.applyBatch(workspace, [
            transfer(deleted: true),
            transfer(scope: otherWorkspace),
          ]),
        ),
        throwsFormatException,
      );
      expect(
        (await db.select(db.expenseTransactions).getSingle()).isDeleted,
        isFalse,
      );
      expect(await balances(), {source: 70, destination: 50});
      await db.transaction(
        () => replica.applyBatch(workspace, [transfer(deleted: true)]),
      );
      expect(await balances(), {source: 100, destination: 20});
    },
  );

  test('database serialization failures preserve the queued intent', () async {
    final server = _Server();
    final gateway = _Gateway(server);
    final device = await _device(gateway);
    addTearDown(device.db.close);
    final operation = await _enqueue(
      device,
      _transaction(0, fields: {'amount_minor': '80'}),
    );
    gateway.failNextSubmit = const PostgrestException(
      code: '40001',
      message: 'could not serialize access due to concurrent update',
    );
    await expectLater(
      device.engine.synchronize(),
      throwsA(isA<PostgrestException>()),
    );
    expect(await device.engine.rejectionFor(workspace, operation), isNull);
    expect(await device.engine.synchronize(), WorkspaceSyncOutcome.current);
    expect(server.commits[workspace], hasLength(1));
  });

  test('Supabase transport sends the normalized command contract', () async {
    final requests = <http.Request>[];
    final client = SupabaseClient(
      'https://ledgerpulse.example.invalid',
      'fixture-key',
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response(
          '{"sequence":"9007199254740993","replayed":false}',
          200,
          headers: {'Content-Type': 'application/json'},
          request: request,
        );
      }),
    );
    addTearDown(client.dispose);
    final gateway = SupabaseWorkspaceCommandGateway(client);
    final operation = uuid.v4();
    await gateway.submit(
      workspace,
      operation,
      'write_entity',
      _transaction(4, fields: {'amount_minor': '9007199254740993'}),
    );
    await gateway.pull(workspace, '9007199254740993');
    expect(requests[0].url.path, '/rest/v1/rpc/ledgerpulse_command');
    final body = jsonDecode(requests[0].body) as SyncJson;
    expect(body['p_workspace'], workspace);
    expect(body['p_operation'], operation);
    expect(body['p_protocol'], 1);
    expect((body['p_data'] as SyncJson)['expected_revision'], 4);
    expect(requests[1].url.path, '/rest/v1/rpc/ledgerpulse_pull');
    expect(
      (jsonDecode(requests[1].body) as SyncJson)['p_after'],
      '9007199254740993',
    );
  });

  test(
    'offline intent survives reopen and lost acknowledgement replays once',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'workspace_sync_',
      );
      final file = File('${directory.path}/user.sqlite');
      addTearDown(() => directory.delete(recursive: true));
      final server = _Server();
      final gateway = _Gateway(server)..session = null;
      final operation = uuid.v4();
      final first = await _device(gateway, executor: NativeDatabase(file));
      await first.engine.enqueue(
        workspace: workspace,
        operationId: operation,
        kind: 'write_entity',
        data: _transaction(0, fields: {'amount_minor': '500'}),
        applyLocal: () => first.replica.pending(operation),
      );
      expect(await first.engine.synchronize(), WorkspaceSyncOutcome.suspended);
      expect(server.commits[workspace], isNull);
      await first.db.close();

      gateway.session = (userId: actor, generation: 'reconnected');
      final restarted = await _device(gateway, executor: NativeDatabase(file));
      addTearDown(restarted.db.close);
      expect(await restarted.replica.pendingCount(), 1);
      gateway.loseNextResponse = true;
      await expectLater(
        restarted.engine.synchronize(),
        throwsA(isA<SocketException>()),
      );
      expect(server.commits[workspace], hasLength(1));
      expect(
        await restarted.engine.synchronize(),
        WorkspaceSyncOutcome.current,
      );
      expect(await restarted.engine.checkpoint(workspace), BigInt.one);
      expect(await restarted.replica.pendingCount(), 0);
      expect(
        (await restarted.replica.rows(
          workspace,
          'expense_transactions',
        )).single['amount_minor'],
        '500',
      );
      await restarted.engine.enqueue(
        workspace: workspace,
        operationId: operation,
        kind: 'write_entity',
        data: _transaction(0, fields: {'amount_minor': '500'}),
        applyLocal: () => fail('A completed intent must not apply again.'),
      );
      expect(
        await restarted.engine.synchronize(),
        WorkspaceSyncOutcome.current,
      );
      expect(server.commits[workspace], hasLength(1));
    },
  );

  test('devices reconcile revision conflicts and delayed tombstones', () async {
    final server = _Server();
    final a = await _device(_Gateway(server));
    final b = await _device(_Gateway(server));
    addTearDown(a.db.close);
    addTearDown(b.db.close);
    await _enqueue(a, _transaction(0, fields: {'amount_minor': '500'}));
    await a.engine.synchronize();
    await b.engine.synchronize();

    final stale = await _enqueue(
      b,
      _transaction(1, fields: {'amount_minor': '900'}),
    );
    await _enqueue(a, _transaction(1, fields: {'deleted_at': true}));
    await a.engine.synchronize();
    expect(await b.engine.synchronize(), WorkspaceSyncOutcome.conflicted);
    expect(await b.engine.rejectionFor(workspace, stale), '40001');
    final tombstone = (await b.replica.rows(
      workspace,
      'expense_transactions',
    )).single;
    expect(tombstone['deleted_at'], isNotNull);
    expect(tombstone['amount_minor'], '500');
    expect(server.commits[workspace], hasLength(2));

    await b.engine.discardRejected(
      workspace: workspace,
      operationId: stale,
      discardLocal: () => b.replica.removePending(stale),
    );
    await _enqueue(b, _transaction(2, fields: {'deleted_at': null}));
    expect(await b.engine.synchronize(), WorkspaceSyncOutcome.current);
    expect(await a.engine.synchronize(), WorkspaceSyncOutcome.current);
    expect(
      await a.replica.rows(workspace, 'expense_transactions'),
      await b.replica.rows(workspace, 'expense_transactions'),
    );
    expect(
      (await a.replica.rows(
        workspace,
        'expense_transactions',
      )).single['deleted_at'],
      isNull,
    );
  });

  test(
    'journal and correction batches roll back with their cursor on interruption',
    () async {
      final server = _Server();
      final a = await _device(_Gateway(server));
      final b = await _device(_Gateway(server));
      addTearDown(a.db.close);
      addTearDown(b.db.close);
      await b.engine.synchronize(); // Empty snapshot at sequence zero.
      await _enqueue(a, {'id': uuid.v4()}, kind: 'post_journal');
      await a.engine.synchronize();

      b.replica.failBatch = true;
      await expectLater(b.engine.synchronize(), throwsStateError);
      expect(await b.engine.checkpoint(workspace), BigInt.zero);
      expect(await b.replica.rows(workspace, 'ledger_journals'), isEmpty);
      expect(await b.replica.rows(workspace, 'ledger_journal_lines'), isEmpty);

      b.replica.failBatch = false;
      await b.engine.synchronize();
      expect(await b.replica.rows(workspace, 'ledger_journals'), hasLength(1));
      expect(
        await b.replica.rows(workspace, 'ledger_journal_lines'),
        hasLength(2),
      );
      await _enqueue(a, {'id': uuid.v4()}, kind: 'reverse_journal');
      await a.engine.synchronize();
      await b.engine.synchronize();
      final lines = await b.replica.rows(workspace, 'ledger_journal_lines');
      expect(lines, hasLength(4));
      expect(
        lines.fold<int>(
          0,
          (total, line) =>
              total +
              int.parse(line['debit_minor'] as String) -
              int.parse(line['credit_minor'] as String),
        ),
        0,
      );
      expect(await b.engine.checkpoint(workspace), BigInt.two);
    },
  );

  test(
    'workspace switch and account change suspend outstanding requests',
    () async {
      final server = _Server();
      final gateway = _Gateway(server);
      final device = await _device(gateway);
      addTearDown(device.db.close);
      await device.engine.synchronize();
      await _enqueue(device, _transaction(0, fields: {'amount_minor': '80'}));
      gateway.afterSubmit = () => device.engine.selectWorkspace(otherWorkspace);
      expect(await device.engine.synchronize(), WorkspaceSyncOutcome.suspended);
      expect(await device.engine.checkpoint(workspace), BigInt.zero);
      expect(await device.engine.synchronize(), WorkspaceSyncOutcome.current);
      expect(
        await device.replica.rows(otherWorkspace, 'expense_transactions'),
        isEmpty,
      );

      device.engine.selectWorkspace(workspace);
      gateway.afterSubmit = () =>
          gateway.session = (userId: otherActor, generation: 'switched');
      expect(await device.engine.synchronize(), WorkspaceSyncOutcome.suspended);
      expect(await device.engine.synchronize(), WorkspaceSyncOutcome.suspended);
      expect(
        await device.replica.rows(workspace, 'expense_transactions'),
        isEmpty,
      );
      expect(server.commits[workspace], hasLength(1));

      gateway.session = (userId: actor, generation: 'refreshed');
      expect(await device.engine.synchronize(), WorkspaceSyncOutcome.current);
      expect(
        await device.replica.rows(workspace, 'expense_transactions'),
        hasLength(1),
      );
    },
  );

  test(
    'foreign rows reject the full batch and resnapshot reconciles',
    () async {
      final server = _Server();
      final gateway = _Gateway(server);
      final device = await _device(gateway);
      addTearDown(device.db.close);
      await device.engine.synchronize();
      await _enqueue(device, _transaction(0, fields: {'amount_minor': '90'}));
      gateway.foreignRow = true;
      await expectLater(device.engine.synchronize(), throwsFormatException);
      expect(await device.engine.checkpoint(workspace), BigInt.zero);
      expect(
        await device.replica.rows(workspace, 'expense_transactions'),
        isEmpty,
      );
      expect(
        await device.replica.rows(otherWorkspace, 'expense_transactions'),
        isEmpty,
      );
      gateway.foreignRow = false;
      gateway.resnapshot = true;
      expect(await device.engine.synchronize(), WorkspaceSyncOutcome.current);
      expect(await device.engine.checkpoint(workspace), BigInt.one);
    },
  );

  test(
    'workspace deletion clears its confirmed copy and restore resnapshots',
    () async {
      final gateway = _Gateway(_Server());
      final device = await _device(gateway);
      addTearDown(device.db.close);
      await _enqueue(device, _transaction(0, fields: {'amount_minor': '300'}));
      await device.engine.synchronize();
      expect(
        await device.replica.rows(workspace, 'expense_transactions'),
        hasLength(1),
      );
      gateway.deleted = true;
      expect(await device.engine.synchronize(), WorkspaceSyncOutcome.deleted);
      expect(await device.engine.checkpoint(workspace), isNull);
      expect(
        await device.replica.rows(workspace, 'expense_transactions'),
        isEmpty,
      );
      gateway.deleted = false;
      expect(await device.engine.synchronize(), WorkspaceSyncOutcome.current);
      expect(
        await device.replica.rows(workspace, 'expense_transactions'),
        hasLength(1),
      );
    },
  );

  test('legacy sync rejects a remote row from another workspace', () async {
    final db = AppDatabase(NativeDatabase.memory(), actor);
    final engine = SyncEngine(
      db: db,
      activeUserId: actor,
      gateway: _ForeignLegacyGateway(),
    );
    addTearDown(db.close);
    addTearDown(engine.dispose);
    final result = await engine.pullChanges(companyId: workspace);
    expect(
      result.tableErrors['accounts'],
      contains('Foreign or missing scope'),
    );
    expect(await db.select(db.accounts).get(), isEmpty);
    expect(await db.select(db.syncState).get(), isEmpty);
  });
}

SyncJson _transaction(int revision, {required SyncJson fields}) => {
  'table': 'expense_transactions',
  'id': recordId,
  'expected_revision': revision,
  'fields': fields,
};

typedef _Device = ({
  AppDatabase db,
  _Replica replica,
  WorkspaceSyncEngine engine,
});

Future<_Device> _device(_Gateway gateway, {NativeDatabase? executor}) async {
  final db = AppDatabase(executor ?? NativeDatabase.memory(), actor);
  final replica = _Replica(db);
  await replica.initialize();
  final engine = WorkspaceSyncEngine(db: db, gateway: gateway, replica: replica)
    ..selectWorkspace(workspace);
  return (db: db, replica: replica, engine: engine);
}

Future<String> _enqueue(
  _Device device,
  SyncJson data, {
  String kind = 'write_entity',
}) async {
  final id = uuid.v4();
  await device.engine.enqueue(
    workspace: workspace,
    operationId: id,
    kind: kind,
    data: data,
    applyLocal: () => device.replica.pending(id),
  );
  return id;
}

class _Replica implements WorkspaceReplica {
  final AppDatabase db;
  bool failBatch = false;

  _Replica(this.db);

  Future<void> initialize() async {
    await db.customStatement('''
      CREATE TABLE IF NOT EXISTS test_replica(
        workspace TEXT, table_name TEXT, id TEXT, row TEXT,
        PRIMARY KEY(workspace,table_name,id)
      )
    ''');
    await db.customStatement(
      'CREATE TABLE IF NOT EXISTS test_pending(id TEXT PRIMARY KEY)',
    );
  }

  Future<void> pending(String id) =>
      db.customStatement('INSERT INTO test_pending VALUES (?)', [id]);

  Future<void> removePending(String id) =>
      db.customStatement('DELETE FROM test_pending WHERE id = ?', [id]);

  Future<int> pendingCount() async =>
      (await db
              .customSelect('SELECT count(*) AS count FROM test_pending')
              .getSingle())
          .read<int>('count');

  Future<List<SyncJson>> rows(String workspace, String table) async {
    final records = await db
        .customSelect(
          'SELECT row FROM test_replica WHERE workspace = ? AND table_name = ? ORDER BY id',
          variables: [Variable(workspace), Variable(table)],
        )
        .get();
    return records
        .map((row) => jsonDecode(row.read<String>('row')) as SyncJson)
        .toList();
  }

  @override
  Future<void> applyBatch(
    String workspaceId,
    List<WorkspaceChange> changes,
  ) async {
    for (final change in changes) {
      if (change.row == null) {
        await db.customStatement(
          'DELETE FROM test_replica WHERE workspace = ? AND table_name = ? AND id = ?',
          [workspaceId, change.table, change.key['id']],
        );
      } else {
        await db.customStatement(
          'INSERT OR REPLACE INTO test_replica VALUES (?, ?, ?, ?)',
          [
            workspaceId,
            change.table,
            change.key.values.join('/'),
            jsonEncode(change.row),
          ],
        );
      }
      if (failBatch) throw StateError('Interrupted projection');
    }
  }

  @override
  Future<void> replaceSnapshot(
    String workspaceId,
    List<WorkspaceChange> rows,
  ) async {
    await clear(workspaceId);
    await applyBatch(workspaceId, rows);
  }

  @override
  Future<void> confirmOperations(
    String workspaceId,
    List<String> operationIds,
  ) async {
    for (final id in operationIds) {
      await removePending(id);
    }
  }

  @override
  Future<void> clear(String workspaceId) => db.customStatement(
    'DELETE FROM test_replica WHERE workspace = ?',
    [workspaceId],
  );
}

class _Gateway implements WorkspaceCommandGateway {
  final _Server server;
  bool loseNextResponse = false;
  PostgrestException? failNextSubmit;
  bool foreignRow = false;
  bool resnapshot = false;
  bool deleted = false;
  void Function()? afterSubmit;

  _Gateway(this.server);

  @override
  WorkspaceSyncSession? session = (userId: actor, generation: 'first');

  @override
  Future<SyncJson> submit(
    String workspace,
    String id,
    String kind,
    SyncJson data,
  ) async {
    final failure = failNextSubmit;
    failNextSubmit = null;
    if (failure != null) throw failure;
    final receipt = server.submit(workspace, id, kind, data);
    final callback = afterSubmit;
    afterSubmit = null;
    callback?.call();
    if (loseNextResponse) {
      loseNextResponse = false;
      throw const SocketException(
        'Response lost after server accepted operation.',
      );
    }
    return receipt;
  }

  @override
  Future<SyncJson> pull(String workspace, String after) async {
    final all = server.commits[workspace] ?? [];
    if (deleted) return {'status': 'deleted', 'head': '${all.length}'};
    if (resnapshot) {
      resnapshot = false;
      return {'status': 'resnapshot', 'head': '${all.length}'};
    }
    final batches = all.skip(int.parse(after)).toList();
    if (foreignRow && batches.isNotEmpty) {
      final batch = Map<String, dynamic>.from(batches.first);
      final changes = List<SyncJson>.from(batch['changes'] as List);
      changes.add(
        _change('expense_transactions', uuid.v4(), otherWorkspace, {}),
      );
      batch['changes'] = changes;
      batches[0] = batch;
    }
    return {'status': 'ok', 'head': '${all.length}', 'batches': batches};
  }

  @override
  Future<SyncJson> snapshot(String workspace) async {
    final all = server.commits[workspace] ?? [];
    final tables = <String, Map<String, SyncJson>>{};
    for (final batch in all) {
      for (final change in batch['changes'] as List<SyncJson>) {
        tables.putIfAbsent(
              change['table'] as String,
              () => {},
            )[(change['key'] as SyncJson)['id'] as String] =
            change['row'] as SyncJson;
      }
    }
    return {
      'protocol': 1,
      'head': '${all.length}',
      'workspace': {
        'id': workspace,
        'owner_user_id': actor,
        'lifecycle_state': deleted ? 'deleted' : 'active',
      },
      'tables': deleted
          ? <String, dynamic>{}
          : tables.map(
              (table, entries) => MapEntry(table, entries.values.toList()),
            ),
    };
  }
}

class _ForeignLegacyGateway extends FakeGateway {
  @override
  Future<List<SyncJson>> pullRows({
    required String table,
    required String companyId,
    String? activeUserId,
    DateTime? cursor,
    int pageSize = 500,
    int offset = 0,
    DateTime? afterUpdatedAt,
    String? afterId,
  }) async {
    if (table != 'accounts') return [];
    return [
      {
        'id': recordId,
        'company_id': otherWorkspace,
        'name': 'Out of scope',
        'updated_at': '2026-07-01T00:00:00Z',
      },
    ];
  }
}

class _Server {
  final commits = <String, List<SyncJson>>{};
  final receipts = <(String, String), (String, String)>{};
  final transactions = <(String, String), SyncJson>{};

  SyncJson submit(
    String workspace,
    String operation,
    String kind,
    SyncJson data,
  ) {
    final hash = jsonEncode([kind, data]);
    final previous = receipts[(workspace, operation)];
    if (previous != null) {
      if (previous.$1 != hash) {
        throw const PostgrestException(message: 'conflict', code: '23505');
      }
      return {'sequence': previous.$2, 'replayed': true};
    }
    final id = data['id'] as String;
    final changes = <SyncJson>[];
    if (kind == 'write_entity') {
      final old = transactions[(workspace, id)] ?? {};
      final revision = int.parse(old['revision'] as String? ?? '0');
      if (data['expected_revision'] != revision) {
        throw const PostgrestException(
          message: 'entity revision conflict',
          code: '40001',
        );
      }
      final row = {
        ...old,
        ...data['fields'] as SyncJson,
        'revision': '${revision + 1}',
      };
      transactions[(workspace, id)] = row;
      changes.add(_change(data['table'] as String, id, workspace, row));
    } else {
      changes.add(
        _change('ledger_journals', id, workspace, {'source_kind': kind}),
      );
      final reversing = kind == 'reverse_journal';
      changes.add(
        _change('ledger_journal_lines', uuid.v4(), workspace, {
          'journal_id': id,
          'debit_minor': reversing ? '0' : '20',
          'credit_minor': reversing ? '20' : '0',
        }),
      );
      changes.add(
        _change('ledger_journal_lines', uuid.v4(), workspace, {
          'journal_id': id,
          'credit_minor': reversing ? '0' : '20',
          'debit_minor': reversing ? '20' : '0',
        }),
      );
    }
    final list = commits.putIfAbsent(workspace, () => []);
    final sequence = '${list.length + 1}';
    list.add({
      'sequence': sequence,
      'operation_id': operation,
      'changes': changes,
    });
    receipts[(workspace, operation)] = (hash, sequence);
    return {'sequence': sequence, 'replayed': false};
  }
}

SyncJson _change(String table, String id, String workspace, SyncJson fields) =>
    {
      'table': table,
      'key': {'id': id},
      'row': {...fields, 'id': id, 'workspace_id': workspace},
    };
