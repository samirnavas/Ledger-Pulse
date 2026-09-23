import 'dart:convert';
import 'package:drift/drift.dart';
import '../models/audit_log_model.dart';
import 'database.dart';

class AuditService {
  final AppDatabase _db;
  static int _sequence = 0;

  AuditService(this._db);

  /// Computes a structural JSON difference between two maps.
  static String? computeDiff(Map<String, dynamic>? oldMap, Map<String, dynamic>? newMap) {
    if (oldMap == null && newMap == null) return null;
    if (oldMap == null) {
      return jsonEncode({'added': newMap});
    }
    if (newMap == null) {
      return jsonEncode({'removed': oldMap});
    }

    final Map<String, dynamic> changes = {};
    final allKeys = {...oldMap.keys, ...newMap.keys};

    for (final key in allKeys) {
      final oldVal = oldMap[key];
      final newVal = newMap[key];

      if (oldVal != newVal) {
        changes[key] = {
          'old': oldVal,
          'new': newVal,
        };
      }
    }

    return changes.isEmpty ? null : jsonEncode(changes);
  }

  /// Records an append-only, tamper-evident statutory audit log entry.
  Future<AuditLog> recordLog({
    required String companyId,
    required String userId,
    required String entityType,
    required String entityId,
    required AuditAction action,
    Map<String, dynamic>? oldState,
    Map<String, dynamic>? newState,
  }) async {
    final now = DateTime.now();
    final timestamp = DateTime.fromMillisecondsSinceEpoch((now.millisecondsSinceEpoch ~/ 1000) * 1000);
    _sequence++;
    final logId = 'audit_${now.microsecondsSinceEpoch.toString().padLeft(20, '0')}_${_sequence.toString().padLeft(8, '0')}';

    // Retrieve latest log checksum for this company to maintain the cryptographic blockchain-like chain
    final existingLogs = await (_db.select(_db.auditLogs)
          ..where((t) => t.companyId.equals(companyId))
          ..orderBy([(t) => OrderingTerm.desc(t.id)])
          ..limit(1))
        .getSingleOrNull();

    final previousChecksum = existingLogs?.checksum ?? 'GENESIS_$companyId';
    final oldStateJson = oldState != null ? jsonEncode(oldState) : null;
    final newStateJson = newState != null ? jsonEncode(newState) : null;
    final diffJson = computeDiff(oldState, newState);

    final checksum = AuditLog.computeChecksum(
      id: logId,
      companyId: companyId,
      userId: userId,
      entityType: entityType,
      entityId: entityId,
      action: action,
      timestamp: timestamp,
      oldStateJson: oldStateJson,
      newStateJson: newStateJson,
      diffJson: diffJson,
      previousChecksum: previousChecksum,
    );

    final auditEntry = AuditLog(
      id: logId,
      companyId: companyId,
      userId: userId,
      entityType: entityType,
      entityId: entityId,
      action: action,
      timestamp: timestamp,
      oldStateJson: oldStateJson,
      newStateJson: newStateJson,
      diffJson: diffJson,
      checksum: checksum,
      previousChecksum: previousChecksum,
    );

    await _db.into(_db.auditLogs).insert(
          AuditLogsCompanion.insert(
            id: auditEntry.id,
            companyId: auditEntry.companyId,
            userId: auditEntry.userId,
            entityType: auditEntry.entityType,
            entityId: auditEntry.entityId,
            action: auditEntry.action.name,
            timestamp: auditEntry.timestamp,
            oldStateJson: Value(auditEntry.oldStateJson),
            newStateJson: Value(auditEntry.newStateJson),
            diffJson: Value(auditEntry.diffJson),
            checksum: auditEntry.checksum,
            previousChecksum: Value(auditEntry.previousChecksum),
          ),
        );

    return auditEntry;
  }

  /// Verifies the cryptographic tamper-evidence chain of audit logs for a company.
  Future<bool> verifyChainIntegrity(String companyId) async {
    final logs = await (_db.select(_db.auditLogs)
          ..where((t) => t.companyId.equals(companyId))
          ..orderBy([(t) => OrderingTerm.asc(t.id)]))
        .get();

    if (logs.isEmpty) return true;

    String? expectedPrev = 'GENESIS_$companyId';

    for (final row in logs) {
      if (row.previousChecksum != expectedPrev) {
        return false;
      }

      final computed = AuditLog.computeChecksum(
        id: row.id,
        companyId: row.companyId,
        userId: row.userId,
        entityType: row.entityType,
        entityId: row.entityId,
        action: AuditAction.values.byName(row.action),
        timestamp: row.timestamp,
        oldStateJson: row.oldStateJson,
        newStateJson: row.newStateJson,
        diffJson: row.diffJson,
        previousChecksum: row.previousChecksum,
      );

      if (computed != row.checksum) {
        return false;
      }

      expectedPrev = row.checksum;
    }

    return true;
  }

  /// Gets audit logs for a company with optional filters.
  Future<List<AuditLog>> getAuditLogs({
    required String companyId,
    String? entityType,
    String? entityId,
    int limit = 100,
  }) async {
    final query = _db.select(_db.auditLogs)
      ..where((t) => t.companyId.equals(companyId))
      ..orderBy([(t) => OrderingTerm.desc(t.id)])
      ..limit(limit);

    if (entityType != null) {
      query.where((t) => t.entityType.equals(entityType));
    }
    if (entityId != null) {
      query.where((t) => t.entityId.equals(entityId));
    }

    final rows = await query.get();
    return rows.map((r) => AuditLog(
      id: r.id,
      companyId: r.companyId,
      userId: r.userId,
      entityType: r.entityType,
      entityId: r.entityId,
      action: AuditAction.values.byName(r.action),
      timestamp: r.timestamp,
      oldStateJson: r.oldStateJson,
      newStateJson: r.newStateJson,
      diffJson: r.diffJson,
      checksum: r.checksum,
      previousChecksum: r.previousChecksum,
    )).toList();
  }
}
