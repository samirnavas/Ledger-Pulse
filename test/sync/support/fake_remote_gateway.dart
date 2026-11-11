import 'dart:io';
import 'package:ledger_pulse/core/network/sync_codec.dart';
import 'package:ledger_pulse/core/network/sync_engine.dart';

/// Test double implementing [RemoteGateway] to emulate PostgREST APIs in unit tests.
class FakeGateway implements RemoteGateway {
  final Map<String, Map<String, Map<String, dynamic>>> tables = {};
  bool simulateNetworkError = false;
  final Set<String> failedTables = {};

  void clear() => tables.clear();

  void upsertDirect(String table, String id, Map<String, dynamic> row) {
    tables.putIfAbsent(table, () => {})[id] = Map<String, dynamic>.from(row);
  }

  Map<String, dynamic>? getRow(String table, String id) {
    return tables[table]?[id];
  }

  @override
  Future<Map<String, dynamic>?> upsertRow({
    required String table,
    required Map<String, dynamic> row,
  }) async {
    if (simulateNetworkError) {
      throw SocketException('Simulated network error');
    }
    if (failedTables.contains(table)) {
      throw Exception('Simulated table failure on $table');
    }
    final id = (row['id'] ?? row['record_id'] ?? row['recordId'])?.toString();
    if (id == null) {
      throw Exception('Row missing primary key ID');
    }

    final copy = Map<String, dynamic>.from(row);
    final nowStr = encodeTime(DateTime.now());
    copy['updated_at'] ??= nowStr;
    copy['remote_updated_at'] = nowStr;

    tables.putIfAbsent(table, () => {})[id] = copy;
    return copy;
  }

  @override
  Future<List<Map<String, dynamic>>> pullRows({
    required String table,
    required String companyId,
    String? activeUserId,
    DateTime? cursor,
    int pageSize = 500,
    int offset = 0,
  }) async {
    if (simulateNetworkError) {
      throw SocketException('Simulated network error');
    }
    if (failedTables.contains(table)) {
      throw Exception('Simulated table failure on $table');
    }

    final tableMap = tables[table] ?? {};
    final matchingRows = <Map<String, dynamic>>[];

    for (final row in tableMap.values) {
      if (companyId != 'cmp_default') {
        if (table == 'companies') {
          final id = (row['id'] ?? row['record_id'])?.toString();
          if (id != null && id != companyId) continue;
        } else if (table == 'user_profiles') {
          final id = (row['id'] ?? row['record_id'])?.toString();
          if (activeUserId != null && id != null && id != activeUserId) {
            continue;
          }
        } else if (table == 'shared_memberships' || table.startsWith('exp_')) {
          final profileId =
              (row['profile_id'] ?? row['profileId'])?.toString();
          if (profileId != null && profileId != companyId) continue;
        } else {
          final rowCompanyId =
              (row['company_id'] ?? row['companyId'])?.toString();
          if (rowCompanyId != null && rowCompanyId != companyId) continue;
        }
      }

      if (cursor != null) {
        final updatedAtStr =
            row['updated_at'] ?? row['updatedAt'] ?? row['created_at'];
        if (updatedAtStr != null) {
          final rowDt = decodeTime(updatedAtStr);
          // Safe overlap gte: skip only if strictly before cursor
          if (rowDt.isBefore(cursor)) {
            continue;
          }
        }
      }

      matchingRows.add(row);
    }

    matchingRows.sort((a, b) {
      final aDt = decodeTime(a['updated_at'] ?? a['updatedAt'] ?? a['created_at']);
      final bDt = decodeTime(b['updated_at'] ?? b['updatedAt'] ?? b['created_at']);
      final cmp = aDt.compareTo(bDt);
      if (cmp != 0) return cmp;
      final aId = (a['id'] ?? a['record_id'] ?? '').toString();
      final bId = (b['id'] ?? b['record_id'] ?? '').toString();
      return aId.compareTo(bId);
    });

    if (offset >= matchingRows.length) return [];
    final end = (offset + pageSize < matchingRows.length)
        ? offset + pageSize
        : matchingRows.length;
    return matchingRows.sublist(offset, end);
  }
}
