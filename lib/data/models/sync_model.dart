import '../../core/network/sync_engine.dart';

export '../../core/network/sync_engine.dart' show SyncEngineStatus, SyncResult, SyncStatus;

extension SyncEngineStatusExt on SyncEngineStatus {
  String get label {
    switch (this) {
      case SyncEngineStatus.idle:
      case SyncEngineStatus.success:
        return 'Up to date';
      case SyncEngineStatus.syncing:
        return 'Syncing...';
      case SyncEngineStatus.partial:
        return 'Partially synced';
      case SyncEngineStatus.error:
        return 'Sync failed';
    }
  }
}

enum SyncProviderType {
  supabase,
  dropbox;

  String get displayName {
    switch (this) {
      case SyncProviderType.supabase:
        return 'Supabase Cloud (PostgreSQL)';
      case SyncProviderType.dropbox:
        return 'Dropbox Storage (Encrypted Backup)';
    }
  }
}

class SyncItem {
  final String id;
  final String companyId;
  final String entityType;
  final String entityId;
  final String action;
  final String payload;
  final DateTime createdAt;
  final String status;
  final int retryCount;
  final String? lastError;

  const SyncItem({
    required this.id,
    required this.companyId,
    required this.entityType,
    required this.entityId,
    required this.action,
    required this.payload,
    required this.createdAt,
    this.status = 'pending',
    this.retryCount = 0,
    this.lastError,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'companyId': companyId,
      'entityType': entityType,
      'entityId': entityId,
      'action': action,
      'payload': payload,
      'createdAt': createdAt.toIso8601String(),
      'status': status,
      'retryCount': retryCount,
      'lastError': lastError,
    };
  }

  factory SyncItem.fromMap(Map<String, dynamic> map) {
    return SyncItem(
      id: map['id'].toString(),
      companyId: (map['companyId'] as String?) ?? 'cmp_default',
      entityType: map['entityType'] as String,
      entityId: map['entityId'] as String,
      action: map['action'] as String,
      payload: map['payload'] as String,
      createdAt: DateTime.parse(map['createdAt'] as String),
      status: (map['status'] as String?) ?? 'pending',
      retryCount: (map['retryCount'] as int?) ?? 0,
      lastError: map['lastError'] as String?,
    );
  }
}
