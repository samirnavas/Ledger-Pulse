import 'dart:convert';
import 'package:crypto/crypto.dart';

enum AuditAction {
  insert,
  update,
  delete,
  voided;

  String get displayName {
    switch (this) {
      case AuditAction.insert:
        return 'INSERT';
      case AuditAction.update:
        return 'UPDATE';
      case AuditAction.delete:
        return 'DELETE';
      case AuditAction.voided:
        return 'VOID';
    }
  }
}

class AuditLog {
  final String id;
  final String companyId;
  final String userId;
  final String entityType; // 'party', 'ledger_entry', 'company'
  final String entityId;
  final AuditAction action;
  final DateTime timestamp;
  final String? oldStateJson;
  final String? newStateJson;
  final String? diffJson;
  final String checksum;
  final String? previousChecksum;

  const AuditLog({
    required this.id,
    required this.companyId,
    required this.userId,
    required this.entityType,
    required this.entityId,
    required this.action,
    required this.timestamp,
    this.oldStateJson,
    this.newStateJson,
    this.diffJson,
    required this.checksum,
    this.previousChecksum,
  });

  static String computeChecksum({
    required String id,
    required String companyId,
    required String userId,
    required String entityType,
    required String entityId,
    required AuditAction action,
    required DateTime timestamp,
    String? oldStateJson,
    String? newStateJson,
    String? diffJson,
    String? previousChecksum,
  }) {
    final payload = [
      id,
      companyId,
      userId,
      entityType,
      entityId,
      action.name,
      timestamp.millisecondsSinceEpoch.toString(),
      oldStateJson ?? '',
      newStateJson ?? '',
      diffJson ?? '',
      previousChecksum ?? 'GENESIS',
    ].join('|');

    return sha256.convert(utf8.encode(payload)).toString();
  }

  bool verifyIntegrity() {
    final computed = computeChecksum(
      id: id,
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
    return computed == checksum;
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'companyId': companyId,
      'userId': userId,
      'entityType': entityType,
      'entityId': entityId,
      'action': action.name,
      'timestamp': timestamp.toIso8601String(),
      'oldStateJson': oldStateJson,
      'newStateJson': newStateJson,
      'diffJson': diffJson,
      'checksum': checksum,
      'previousChecksum': previousChecksum,
    };
  }

  factory AuditLog.fromMap(Map<String, dynamic> map) {
    return AuditLog(
      id: map['id'] as String,
      companyId: map['companyId'] as String,
      userId: map['userId'] as String,
      entityType: map['entityType'] as String,
      entityId: map['entityId'] as String,
      action: AuditAction.values.byName(map['action'] as String),
      timestamp: DateTime.parse(map['timestamp'] as String),
      oldStateJson: map['oldStateJson'] as String?,
      newStateJson: map['newStateJson'] as String?,
      diffJson: map['diffJson'] as String?,
      checksum: map['checksum'] as String,
      previousChecksum: map['previousChecksum'] as String?,
    );
  }
}
