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
      ..where((t) => t.companyId.equals(companyId) & t.status.equals('pending'))
      ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]);

    final rows = await query.get();
    return rows.map((r) => SyncItem(
      id: r.id,
      companyId: r.companyId,
      entityType: r.entityType,
      entityId: r.entityId,
      action: r.action,
      payload: r.payload,
      createdAt: r.createdAt,
      status: r.status,
      retryCount: r.retryCount,
      lastError: r.lastError,
    )).toList();
  }

  /// Marks an outbox item as processed/synced.
  Future<void> markItemSuccess(int id) async {
    await (db.update(db.syncOutbox)..where((t) => t.id.equals(id))).write(
      const SyncOutboxCompanion(
        status: Value('synced'),
      ),
    );
  }

  /// Marks an outbox item as failed with error details and increments retry count.
  Future<void> markItemFailed(int id, String error) async {
    final item = await (db.select(db.syncOutbox)..where((t) => t.id.equals(id))).getSingleOrNull();
    if (item == null) return;

    await (db.update(db.syncOutbox)..where((t) => t.id.equals(id))).write(
      SyncOutboxCompanion(
        status: Value(item.retryCount + 1 >= 5 ? 'dead_letter' : 'pending'),
        retryCount: Value(item.retryCount + 1),
        lastError: Value(error),
      ),
    );
  }

  void dispose() {
    _statusController.close();
  }
}
