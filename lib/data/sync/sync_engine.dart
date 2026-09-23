import 'dart:async';
import 'package:drift/drift.dart';
import '../local/database.dart';
import '../models/sync_model.dart';

abstract class SyncEngine {
  final AppDatabase db;
  final StreamController<SyncStatus> _statusController = StreamController<SyncStatus>.broadcast();
  SyncStatus _currentStatus = SyncStatus.idle;

  SyncEngine(this.db);

  SyncStatus get currentStatus => _currentStatus;
  Stream<SyncStatus> get statusStream => _statusController.stream;

  void setStatus(SyncStatus status) {
    _currentStatus = status;
    if (!_statusController.isClosed) {
      _statusController.add(status);
    }
  }

  /// Triggers full synchronization (Push outbox + Pull remote updates) for a company.
  Future<SyncResult> syncCompany(String companyId);

  /// Pushes un-synced transactions / mutations from local outbox.
  Future<SyncResult> pushPendingOutbox(String companyId);

  /// Pulls remote delta updates.
  Future<SyncResult> pullRemoteChanges(String companyId);

  /// Retrieves all pending outbox records for a given company.
  Future<List<SyncItem>> getPendingOutboxItems(String companyId) async {
    final query = db.select(db.syncOutbox)
      ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]);

    final rows = await query.get();
    return rows
        .where((r) => r.companyId == companyId)
        .map((r) => SyncItem(
              id: r.id,
              companyId: r.companyId,
              entityType: r.tableName,
              entityId: r.recordId,
              action: r.mutationType,
              payload: r.payload,
              createdAt: r.createdAt,
              status: 'pending',
              retryCount: 0,
              lastError: null,
            ))
        .toList();
  }

  /// Marks an outbox item as processed/synced by removing it (Directive 4).
  Future<void> markItemSuccess(String id) async {
    await (db.delete(db.syncOutbox)..where((t) => t.id.equals(id))).go();
  }

  /// Marks an outbox item as failed with error details.
  Future<void> markItemFailed(String id, String error) async {
    // Left in outbox queue for future retry
  }

  void dispose() {
    _statusController.close();
  }
}
