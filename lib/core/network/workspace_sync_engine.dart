import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/local/database.dart';

typedef WorkspaceSyncSession = ({String userId, String generation});
typedef SyncJson = Map<String, dynamic>;

/// Projection methods run inside the supplied Drift database transaction.
/// Implementations must scope every key lookup and write to workspaceId.
abstract interface class WorkspaceReplica {
  Future<void> applyBatch(String workspaceId, List<WorkspaceChange> changes);
  Future<void> replaceSnapshot(String workspaceId, List<WorkspaceChange> rows);
  Future<void> confirmOperations(String workspaceId, List<String> operationIds);
  Future<void> clear(String workspaceId);
}

final class WorkspaceChange {
  final String table;
  final SyncJson key;
  final SyncJson? row;

  const WorkspaceChange(this.table, this.key, this.row);
}

abstract interface class WorkspaceCommandGateway {
  WorkspaceSyncSession? get session;

  Future<SyncJson> submit(
    String workspace,
    String id,
    String kind,
    SyncJson data,
  );
  Future<SyncJson> pull(String workspace, String after);
  Future<SyncJson> snapshot(String workspace);
}

final class SupabaseWorkspaceCommandGateway implements WorkspaceCommandGateway {
  final SupabaseClient client;
  final Duration timeout;

  const SupabaseWorkspaceCommandGateway(
    this.client, {
    this.timeout = const Duration(seconds: 20),
  });

  @override
  WorkspaceSyncSession? get session {
    final current = client.auth.currentSession;
    if (current == null || current.isExpired) return null;
    // The token is compared in memory only. Never persist or log it here.
    return (userId: current.user.id, generation: current.accessToken);
  }

  Future<SyncJson> _rpc(String name, SyncJson arguments) async {
    final result = await client.rpc(name, params: arguments).timeout(timeout);
    return _object(result);
  }

  @override
  Future<SyncJson> submit(
    String workspace,
    String id,
    String kind,
    SyncJson data,
  ) {
    if (kind == 'create_workspace') {
      return _rpc('ledgerpulse_create_workspace', {
        'p_workspace': workspace,
        'p_operation': id,
        'p_type': data['workspace_type'],
        'p_name': data['name'],
        'p_currency': data['currency_code'],
        'p_time_zone': data['time_zone'],
        'p_legal_name': data['legal_name'],
      });
    }
    return _rpc('ledgerpulse_command', {
      'p_workspace': workspace,
      'p_operation': id,
      'p_command': kind,
      'p_data': data,
      'p_protocol': 1,
    });
  }

  @override
  Future<SyncJson> pull(String workspace, String after) =>
      _rpc('ledgerpulse_pull', {
        'p_workspace': workspace,
        'p_after': after,
        'p_limit': 50,
        'p_protocol': 1,
      });

  @override
  Future<SyncJson> snapshot(String workspace) =>
      _rpc('ledgerpulse_snapshot', {'p_workspace': workspace});
}

enum WorkspaceSyncOutcome {
  current,
  suspended,
  conflicted,
  unavailable,
  deleted,
}

/// Durable command and checkpoint driver for the normalized Supabase baseline.
/// Select a workspace before running it. Legacy row-upsert queues are separate.
final class WorkspaceSyncEngine {
  final AppDatabase db;
  final WorkspaceCommandGateway gateway;
  final WorkspaceReplica replica;

  String? _workspace;
  int _generation = 0;
  Future<void>? _ready;
  Future<WorkspaceSyncOutcome>? _running;

  WorkspaceSyncEngine({
    required this.db,
    required this.gateway,
    required this.replica,
  });

  void selectWorkspace(String? workspace) {
    if (workspace != null) _requireUuid(workspace);
    if (workspace == _workspace) return;
    _workspace = workspace;
    _generation++;
  }

  /// Invalidates in-flight work when signing out, switching accounts, or closing.
  void suspend() {
    _workspace = null;
    _generation++;
  }

  Future<void> _initialize() => _ready ??= _createStorage();

  Future<void> _createStorage() => db.transaction(() async {
    await db.customStatement('''
      CREATE TABLE IF NOT EXISTS workspace_command_outbox (
        ordinal INTEGER PRIMARY KEY AUTOINCREMENT,
        workspace_id TEXT NOT NULL,
        operation_id TEXT NOT NULL,
        kind TEXT NOT NULL,
        payload TEXT NOT NULL,
        accepted_sequence TEXT,
        rejection_code TEXT,
        reconciled INTEGER NOT NULL DEFAULT 0,
        discarded INTEGER NOT NULL DEFAULT 0,
        UNIQUE (workspace_id, operation_id)
      )
    ''');
    await db.customStatement('''
      CREATE TABLE IF NOT EXISTS workspace_command_checkpoint (
        workspace_id TEXT PRIMARY KEY,
        sequence TEXT NOT NULL
      )
    ''');
    await db.customStatement('''
      CREATE INDEX IF NOT EXISTS workspace_command_outbox_order
      ON workspace_command_outbox (workspace_id, ordinal)
    ''');
  });

  /// Persist the optimistic edit and immutable command together. Reusing an ID
  /// for identical pending work is a no-op. Use a fresh UUID for each new intent.
  Future<void> enqueue({
    required String workspace,
    required String operationId,
    required String kind,
    required SyncJson data,
    required Future<void> Function() applyLocal,
  }) async {
    _requireUuid(db.userId);
    _requireUuid(workspace);
    _requireUuid(operationId);
    if (!_commands.contains(kind)) throw ArgumentError.value(kind, 'kind');
    final payload = jsonEncode(_canonicalJson(data));
    if (utf8.encode(payload).length > 120000) {
      throw ArgumentError('Workspace command is too large.');
    }
    await _initialize();
    await db.transaction(() async {
      final previous = await _operation(workspace, operationId);
      if (previous != null) {
        if (previous.read<String>('kind') != kind ||
            previous.read<String>('payload') != payload) {
          throw StateError('Operation ID is already in use.');
        }
        return;
      }
      await db.customStatement(
        '''
        INSERT INTO workspace_command_outbox
          (workspace_id, operation_id, kind, payload) VALUES (?, ?, ?, ?)
      ''',
        [workspace, operationId, kind, payload],
      );
      await applyLocal();
    });
  }

  /// Conflict resolution must explicitly discard the rejected optimistic edit.
  /// A replacement is a separate command with current revisions and a fresh ID.
  Future<void> discardRejected({
    required String workspace,
    required String operationId,
    required Future<void> Function() discardLocal,
  }) async {
    await _initialize();
    await db.transaction(() async {
      final row = await _operation(workspace, operationId);
      if (row == null ||
          row.readNullable<String>('rejection_code') == null ||
          row.read<int>('discarded') != 0) {
        throw StateError('No rejected command to discard.');
      }
      await discardLocal();
      await db.customStatement(
        '''
        UPDATE workspace_command_outbox SET discarded = 1
        WHERE workspace_id = ? AND operation_id = ?
      ''',
        [workspace, operationId],
      );
    });
  }

  Future<QueryRow?> _operation(String workspace, String operationId) => db
      .customSelect(
        '''
        SELECT * FROM workspace_command_outbox
        WHERE workspace_id = ? AND operation_id = ?
      ''',
        variables: [Variable(workspace), Variable(operationId)],
      )
      .getSingleOrNull();

  Future<String?> rejectionFor(String workspace, String operationId) async {
    await _initialize();
    final row = await _operation(workspace, operationId);
    return row?.read<int>('discarded') == 0
        ? row?.readNullable<String>('rejection_code')
        : null;
  }

  Future<BigInt?> checkpoint(String workspace) async {
    await _initialize();
    final row = await db
        .customSelect(
          '''
      SELECT sequence FROM workspace_command_checkpoint WHERE workspace_id = ?
    ''',
          variables: [Variable(workspace)],
        )
        .getSingleOrNull();
    return row == null ? null : _sequence(row.read<String>('sequence'));
  }

  Future<bool> hasPendingCreation(String workspace) async {
    await _initialize();
    final operation = await db.customSelect(
      '''SELECT operation_id FROM workspace_command_outbox
         WHERE workspace_id = ? AND kind = 'create_workspace'
           AND reconciled = 0 AND discarded = 0 LIMIT 1''',
      variables: [Variable(workspace)],
    ).getSingleOrNull();
    return operation != null;
  }

  Future<WorkspaceSyncOutcome> synchronize() async {
    // Concurrent callers may request another workspace while a previous RPC is
    // outstanding. Wait for that run, then capture the currently selected scope.
    while (_running != null) {
      final running = _running!;
      try {
        await running;
      } catch (_) {
        // The original caller receives this failure.
      }
    }
    final workspace = _workspace;
    final session = gateway.session;
    if (workspace == null || session == null || session.userId != db.userId) {
      return WorkspaceSyncOutcome.suspended;
    }
    final generation = _generation;
    void ensureScope() {
      if (generation != _generation || session != gateway.session) {
        throw const _ScopeChanged();
      }
    }

    final run = _synchronize(workspace, session.userId, ensureScope);
    _running = run;
    try {
      return await run;
    } finally {
      if (identical(_running, run)) _running = null;
    }
  }

  Future<WorkspaceSyncOutcome> _synchronize(
    String workspace,
    String actor,
    void Function() ensureScope,
  ) async {
    try {
      await _initialize();
      ensureScope();
      final blocked = await _push(workspace, ensureScope);
      final outcome = await _pull(workspace, actor, ensureScope);
      return blocked && outcome == WorkspaceSyncOutcome.current
          ? WorkspaceSyncOutcome.conflicted
          : outcome;
    } on _ScopeChanged {
      return WorkspaceSyncOutcome.suspended;
    } catch (_) {
      try {
        ensureScope();
      } on _ScopeChanged {
        return WorkspaceSyncOutcome.suspended;
      }
      rethrow;
    }
  }

  Future<bool> _push(String workspace, void Function() ensureScope) async {
    final pending = await db
        .customSelect(
          '''
      SELECT * FROM workspace_command_outbox
      WHERE workspace_id = ? AND accepted_sequence IS NULL AND discarded = 0
      ORDER BY ordinal
    ''',
          variables: [Variable(workspace)],
        )
        .get();
    for (final row in pending) {
      ensureScope();
      if (row.readNullable<String>('rejection_code') != null) return true;
      final id = row.read<String>('operation_id');
      try {
        final response = await gateway.submit(
          workspace,
          id,
          row.read<String>('kind'),
          _object(jsonDecode(row.read<String>('payload'))),
        );
        ensureScope();
        final sequence = _sequence(response['sequence']);
        if (sequence == BigInt.zero) {
          throw const FormatException('Invalid receipt');
        }
        await db.transaction(() async {
          ensureScope();
          await db.customStatement(
            '''
            UPDATE workspace_command_outbox SET accepted_sequence = ?
            WHERE workspace_id = ? AND operation_id = ?
          ''',
            [sequence.toString(), workspace, id],
          );
          ensureScope();
        });
      } on PostgrestException catch (error) {
        ensureScope();
        final code = error.code;
        if (_isAuthenticationError(code)) throw const _ScopeChanged();
        // The command RPC also uses 40001 for expected revision conflicts.
        // A database serialization failure must leave the command retryable.
        if (code == '40001' && !_revisionConflicts.contains(error.message)) {
          rethrow;
        }
        final readOnlyWorkspace =
            code == '42501' && error.message == 'workspace is read-only';
        if (code == '42501' && !readOnlyWorkspace) return true;
        if (!readOnlyWorkspace &&
            !const {
              '40001',
              '23505',
              '23503',
              '23514',
              '22023',
              '0A000',
            }.contains(code)) {
          rethrow;
        }
        await db.transaction(() async {
          ensureScope();
          await db.customStatement(
            '''
            UPDATE workspace_command_outbox SET rejection_code = ?
            WHERE workspace_id = ? AND operation_id = ?
          ''',
            [code, workspace, id],
          );
          ensureScope();
        });
        return true;
      }
    }
    return false;
  }

  Future<WorkspaceSyncOutcome> _pull(
    String workspace,
    String actor,
    void Function() ensureScope,
  ) async {
    try {
      final confirmed =
          await checkpoint(workspace) ??
          await _snapshot(workspace, actor, ensureScope);
      if (confirmed == null) return WorkspaceSyncOutcome.deleted;
      var cursor = confirmed;
      while (true) {
        ensureScope();
        final page = await gateway.pull(workspace, cursor.toString());
        ensureScope();
        switch (page['status']) {
          case 'deleted':
            await db.transaction(() async {
              ensureScope();
              await replica.clear(workspace);
              final head = _sequence(page['head']);
              // Keep a snapshot requirement through a later workspace restore.
              await _recordCheckpoint(workspace, head, retainCursor: false);
              ensureScope();
            });
            return WorkspaceSyncOutcome.deleted;
          case 'resnapshot':
            return await _snapshot(workspace, actor, ensureScope) == null
                ? WorkspaceSyncOutcome.deleted
                : WorkspaceSyncOutcome.current;
          case 'ok':
            break;
          default:
            throw const FormatException('Unknown workspace feed status');
        }
        final head = _sequence(page['head']);
        final batches = page['batches'] as List;
        if (head < cursor || (batches.isEmpty && head != cursor)) {
          throw const FormatException('Workspace feed is incomplete');
        }
        if (batches.isEmpty) {
          await db.transaction(() async {
            ensureScope();
            await _recordCheckpoint(workspace, head);
            ensureScope();
          });
        }
        for (final item in batches) {
          final batch = _object(item);
          final next = _sequence(batch['sequence']);
          if (next != cursor + BigInt.one || next > head) {
            throw const FormatException('Workspace feed sequence has a gap');
          }
          final changes = (batch['changes'] as List)
              .map((item) => _checkedChange(_object(item), workspace, actor))
              .toList(growable: false);
          await db.transaction(() async {
            ensureScope();
            await replica.applyBatch(workspace, changes);
            await _recordCheckpoint(workspace, next);
            ensureScope();
          });
          cursor = next;
        }
        if (cursor == head) return WorkspaceSyncOutcome.current;
      }
    } on PostgrestException catch (error) {
      ensureScope();
      if (_isAuthenticationError(error.code)) throw const _ScopeChanged();
      if (error.code != '42501') rethrow;
      await db.transaction(() async {
        ensureScope();
        await replica.clear(workspace);
        await db.customStatement(
          'DELETE FROM workspace_command_checkpoint WHERE workspace_id = ?',
          [workspace],
        );
        ensureScope();
      });
      return WorkspaceSyncOutcome.unavailable;
    }
  }

  Future<BigInt?> _snapshot(
    String workspace,
    String actor,
    void Function() ensureScope,
  ) async {
    ensureScope();
    final snapshot = await gateway.snapshot(workspace);
    ensureScope();
    if (snapshot['protocol'] != 1) {
      throw const FormatException('Unknown snapshot protocol');
    }
    final root = _object(snapshot['workspace']);
    final head = _sequence(snapshot['head']);
    final rows = [
      _checkedChange(
        {
          'table': 'workspaces',
          'key': {'id': root['id']},
          'row': root,
        },
        workspace,
        actor,
      ),
    ];
    final deleted = root['lifecycle_state'] == 'deleted';
    final tables = _object(snapshot['tables']);
    if (deleted && tables.isNotEmpty) {
      throw const FormatException('Deleted workspace contains financial data');
    }
    for (final entry in tables.entries) {
      if (!_tables.contains(entry.key) || entry.key == 'workspaces') {
        throw const FormatException('Unknown snapshot table');
      }
      for (final value in entry.value as List) {
        final row = _object(value);
        rows.add(
          _checkedChange(
            {'table': entry.key, 'key': _rowKey(entry.key, row), 'row': row},
            workspace,
            actor,
          ),
        );
      }
    }
    // JSON object order from PostgreSQL is not a foreign-key ordering contract.
    rows.sort(
      (a, b) => _tables.indexOf(a.table).compareTo(_tables.indexOf(b.table)),
    );
    await db.transaction(() async {
      ensureScope();
      if (deleted) {
        await replica.clear(workspace);
      } else {
        await replica.replaceSnapshot(workspace, rows);
      }
      await _recordCheckpoint(workspace, head, retainCursor: !deleted);
      ensureScope();
    });
    return deleted ? null : head;
  }

  Future<void> _recordCheckpoint(
    String workspace,
    BigInt sequence, {
    bool retainCursor = true,
  }) async {
    if (retainCursor) {
      await db.customStatement(
        '''
        INSERT INTO workspace_command_checkpoint (workspace_id, sequence)
        VALUES (?, ?) ON CONFLICT (workspace_id) DO UPDATE SET sequence = excluded.sequence
      ''',
        [workspace, sequence.toString()],
      );
    } else {
      await db.customStatement(
        'DELETE FROM workspace_command_checkpoint WHERE workspace_id = ?',
        [workspace],
      );
    }
    // Retain the accepted operation locally so a later retry of a completed
    // intent cannot re-apply its optimistic effect. No client-side TTL yet.
    final eligible = await db
        .customSelect(
          '''
      SELECT operation_id, accepted_sequence FROM workspace_command_outbox
      WHERE workspace_id = ? AND accepted_sequence IS NOT NULL AND reconciled = 0
    ''',
          variables: [Variable(workspace)],
        )
        .get();
    final confirmed = [
      for (final row in eligible)
        if (_sequence(row.read<String>('accepted_sequence')) <= sequence)
          row.read<String>('operation_id'),
    ];
    if (confirmed.isNotEmpty) {
      await replica.confirmOperations(workspace, confirmed);
      for (final id in confirmed) {
        await db.customStatement(
          '''
          UPDATE workspace_command_outbox SET reconciled = 1
          WHERE workspace_id = ? AND operation_id = ?
        ''',
          [workspace, id],
        );
      }
    }
  }
}

class _ScopeChanged implements Exception {
  const _ScopeChanged();
}

bool _isAuthenticationError(String? code) =>
    const {'PGRST301', 'PGRST303', '28000'}.contains(code);

const _revisionConflicts = {
  'entity revision conflict',
  'occurrence revision conflict',
  'voucher revision conflict',
  'workspace revision conflict',
};

const _commands = {
  'create_workspace',
  'rename_workspace',
  'workspace_state',
  'set_workspace_currency',
  'write_entity',
  'generate_occurrence',
  'issue_document',
  'remove_draft_line',
  'post_journal',
  'reverse_journal',
  'replace_journal',
  'stock_movement',
};

const _tables = [
  'workspaces',
  'expense_profiles',
  'ledger_profiles',
  'workspace_memberships',
  'expense_wallets',
  'expense_categories',
  'expense_budgets',
  'expense_recurring_rules',
  'expense_transactions',
  'ledger_parties',
  'ledger_accounts',
  'ledger_inventory_items',
  'ledger_vouchers',
  'ledger_voucher_lines',
  'ledger_journals',
  'ledger_journal_lines',
  'ledger_stock_movements',
  'ledger_audit_events',
];

SyncJson _object(Object? value) {
  if (value is! Map<String, dynamic>) {
    throw const FormatException('Expected JSON object');
  }
  return value;
}

Object? _canonicalJson(Object? value) {
  if (value is Map<String, dynamic>) {
    return {
      for (final k in value.keys.toList()..sort()) k: _canonicalJson(value[k]),
    };
  }
  if (value is List) return value.map(_canonicalJson).toList();
  return value;
}

BigInt _sequence(Object? value) {
  if (value is! String || !RegExp(r'^(0|[1-9][0-9]*)$').hasMatch(value)) {
    throw const FormatException('Expected nonnegative decimal sequence');
  }
  return BigInt.parse(value);
}

void _requireUuid(Object? value) {
  if (value is! String ||
      !RegExp(r'^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$').hasMatch(value)) {
    throw const FormatException('Expected UUID');
  }
}

SyncJson _rowKey(String table, SyncJson row) => switch (table) {
  'workspace_memberships' => {
    'workspace_id': row['workspace_id'],
    'user_id': row['user_id'],
  },
  'expense_profiles' ||
  'ledger_profiles' => {'workspace_id': row['workspace_id']},
  _ => {'id': row['id']},
};

WorkspaceChange _checkedChange(SyncJson entry, String workspace, String actor) {
  final table = entry['table'];
  if (table is! String || !_tables.contains(table)) {
    throw const FormatException('Unknown workspace table');
  }
  final key = _object(entry['key']);
  final row = entry['row'] == null ? null : _object(entry['row']);
  if (row == null && table != 'ledger_voucher_lines') {
    throw const FormatException('Unexpected hard deletion');
  }
  final expectedKey = _rowKey(table, row ?? key);
  if (key.length != expectedKey.length ||
      expectedKey.entries.any((part) => key[part.key] != part.value)) {
    throw const FormatException('Workspace row key does not match');
  }
  for (final value in expectedKey.values) {
    _requireUuid(value);
  }
  if (row != null) {
    if (table == 'workspaces') {
      if (row['id'] != workspace || row['owner_user_id'] != actor) {
        throw const FormatException(
          'Workspace owner or identity does not match',
        );
      }
    } else if (row['workspace_id'] != workspace) {
      throw const FormatException('Foreign workspace row in change batch');
    }
  }
  return WorkspaceChange(table, key, row);
}
