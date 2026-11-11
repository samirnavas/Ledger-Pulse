import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'database.dart';

const realTableNames = <String>{
  'companies',
  'user_profiles',
  'accounts',
  'parties',
  'vouchers',
  'journals',
  'journal_lines',
  'ledger_entries',
  'budgets',
  'recurring_rules',
  'exp_wallets',
  'exp_categories',
  'exp_transactions',
  'exp_budgets',
  'exp_recurring_rules',
  'shared_memberships',
  'inventory_items',
  'stock_ledger',
  'audit_logs',
};

const _uuid = Uuid();

/// Routes all local outbox write operations through a single method that enforces:
/// 1. Valid targetTable (must be in [realTableNames])
/// 2. Valid JSON payload serialization using [jsonEncode]
/// 3. Unique outbox entry per (table_name, record_id) using ON CONFLICT DO UPDATE
Future<void> enqueueMutation({
  required AppDatabase db,
  required String table,
  required String recordId,
  required String type,
  required Map<String, dynamic> fullRowMap,
}) async {
  assert(
    realTableNames.contains(table),
    'Invalid outbox targetTable: "$table". Must be one of $realTableNames',
  );

  if (!realTableNames.contains(table)) {
    debugPrint(
      'Outbox schema error: Table "$table" is not in real table list. Refusing outbox insertion.',
    );
    return;
  }

  final payloadJson = jsonEncode(fullRowMap);
  final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;

  try {
    await db.customStatement('''
      INSERT INTO sync_outbox (id, table_name, record_id, mutation_type, payload, attempts, last_error, next_attempt_at, created_at)
      VALUES (?, ?, ?, ?, ?, 0, NULL, NULL, ?)
      ON CONFLICT (table_name, record_id) DO UPDATE SET
        payload = excluded.payload,
        mutation_type = excluded.mutation_type,
        attempts = 0,
        last_error = NULL,
        next_attempt_at = NULL,
        created_at = excluded.created_at;
    ''', [
      _uuid.v4(),
      table,
      recordId,
      type.toUpperCase(),
      payloadJson,
      nowSeconds,
    ]);
  } catch (e) {
    debugPrint('Failed to enqueue sync outbox mutation for table "$table" ($recordId): $e');
  }
}
