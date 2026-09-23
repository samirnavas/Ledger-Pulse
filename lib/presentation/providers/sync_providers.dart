import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/sync_model.dart';
import '../../data/sync/sync_coordinator.dart';
import 'company_providers.dart';
import 'ledger_providers.dart';

final syncCoordinatorProvider = Provider<SyncCoordinator>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final coordinator = SyncCoordinator(db: db);
  ref.onDispose(() {
    coordinator.dispose();
  });
  return coordinator;
});

final syncStatusStreamProvider = StreamProvider<SyncStatus>((ref) {
  final coordinator = ref.watch(syncCoordinatorProvider);
  return coordinator.statusStream;
});

final pendingSyncCountProvider = FutureProvider<int>((ref) async {
  final coordinator = ref.watch(syncCoordinatorProvider);
  final activeCompany = ref.watch(activeCompanyProvider);
  return await coordinator.getPendingOutboxCount(activeCompany.id);
});

class SyncNotifier extends Notifier<SyncStatus> {
  @override
  SyncStatus build() {
    return SyncStatus.idle;
  }

  Future<SyncResult> triggerSync() async {
    state = SyncStatus.syncing;
    final engine = ref.read(syncEngineProvider);
    final activeCompany = ref.read(activeCompanyProvider);
    
    final result = await engine.syncAll(companyId: activeCompany.id);
    state = result.success ? SyncStatus.success : SyncStatus.error;
    
    // Refresh pending count and ledger updates
    ref.invalidate(pendingSyncCountProvider);
    return result;
  }
}

final syncControllerProvider =
    NotifierProvider<SyncNotifier, SyncStatus>(SyncNotifier.new);
