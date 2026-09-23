import 'dart:async';
import '../local/database.dart';
import '../models/company_model.dart';
import '../models/sync_model.dart';
import 'dropbox_sync_provider.dart';
import 'supabase_sync_provider.dart';
import 'sync_engine.dart';

class SyncCoordinator {
  final AppDatabase db;
  final SupabaseSyncProvider supabaseProvider;
  final DropboxSyncProvider dropboxProvider;
  final StreamController<SyncStatus> _statusController = StreamController<SyncStatus>.broadcast();
  
  StreamSubscription? _supabaseSub;
  StreamSubscription? _dropboxSub;

  SyncCoordinator({
    required this.db,
    SupabaseSyncProvider? supabase,
    DropboxSyncProvider? dropbox,
  })  : supabaseProvider = supabase ?? SupabaseSyncProvider(db: db),
        dropboxProvider = dropbox ?? DropboxSyncProvider(db: db) {
    _supabaseSub = supabaseProvider.statusStream.listen(_onProviderStatus);
    _dropboxSub = dropboxProvider.statusStream.listen(_onProviderStatus);
  }

  void _onProviderStatus(SyncStatus status) {
    if (!_statusController.isClosed) {
      _statusController.add(status);
    }
  }

  Stream<SyncStatus> get statusStream => _statusController.stream;

  SyncEngine getEngineForCompany(Company company) {
    if (company.isCloudSyncEnabled) {
      return supabaseProvider;
    } else if (company.isDropboxSyncEnabled) {
      return dropboxProvider;
    }
    return supabaseProvider;
  }

  Future<SyncResult> triggerSync(Company company) async {
    final engine = getEngineForCompany(company);
    return await engine.syncCompany(company.id);
  }

  Future<int> getPendingOutboxCount(String companyId) async {
    final query = db.select(db.syncOutbox);
    final rows = await query.get();
    return rows.where((t) => t.companyId == companyId).length;
  }

  void dispose() {
    _supabaseSub?.cancel();
    _dropboxSub?.cancel();
    _statusController.close();
    supabaseProvider.dispose();
    dropboxProvider.dispose();
  }
}
