import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../../core/network/sync_codec.dart';
import 'database.dart';

const realTableNames = <String>{
  'profiles',
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

/// Exception thrown when enqueuing a mutation into [sync_outbox] fails.
class OutboxEnqueueException implements Exception {
  final String table;
  final String recordId;
  final Object cause;
  final StackTrace? stackTrace;

  const OutboxEnqueueException({
    required this.table,
    required this.recordId,
    required this.cause,
    this.stackTrace,
  });

  @override
  String toString() =>
      'OutboxEnqueueException(table: $table, recordId: $recordId, cause: $cause)';
}

/// Routes all local outbox write operations through a single method that enforces:
/// 1. Valid targetTable (must be in [realTableNames])
/// 2. Valid JSON payload serialization using [jsonEncode]
/// 3. Unique outbox entry per (table_name, record_id) using ON CONFLICT DO UPDATE
/// 4. Observable failure propagation (throws [ArgumentError] or [OutboxEnqueueException])
Future<void> enqueueMutation({
  required AppDatabase db,
  required String table,
  required String recordId,
  required String type,
  required Map<String, dynamic> fullRowMap,
}) async {
  if (!realTableNames.contains(table)) {
    throw ArgumentError.value(
      table,
      'table',
      'Invalid outbox targetTable: "$table". Must be one of $realTableNames',
    );
  }

  final payloadJson = jsonEncode(
    fullRowMap,
    toEncodable: (nonEncodable) {
      if (nonEncodable is DateTime) {
        return encodeTime(nonEncodable);
      }
      return nonEncodable.toString();
    },
  );
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
  } catch (e, stackTrace) {
    debugPrint('Failed to enqueue sync outbox mutation for table "$table" ($recordId): $e');
    throw OutboxEnqueueException(
      table: table,
      recordId: recordId,
      cause: e,
      stackTrace: stackTrace,
    );
  }
}
