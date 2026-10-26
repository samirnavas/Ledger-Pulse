import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/company_model.dart';
import '../../data/models/sync_model.dart';
import '../../data/sync/sync_coordinator.dart';
import 'company_providers.dart';
import 'ledger_providers.dart';
import 'profile_provider.dart';

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
  DateTime? _lastSyncTime;
  bool _isSyncing = false;

  @override
  SyncStatus build() {
    return SyncStatus.idle;
  }

  DateTime? get lastSyncTime => _lastSyncTime;
  bool get isSyncing => _isSyncing;

  Future<SyncResult> triggerSync({bool isAutoSync = false}) async {
    if (_isSyncing) {
      return SyncResult(
        success: true,
        itemsPushed: 0,
        itemsPulled: 0,
        timestamp: DateTime.now(),
      );
    }

    _isSyncing = true;
    state = SyncStatus.syncing;

    try {
      final engine = ref.read(syncEngineProvider);
      final activeCompany = ref.read(activeCompanyProvider);

      final result = await engine.syncAll(companyId: activeCompany.id);
      state = result.success ? SyncStatus.success : SyncStatus.error;
      _lastSyncTime = DateTime.now();

      // Reload persistent profile and companies from database so newly pulled companies appear immediately
      try {
        await ref.read(userProfileProvider.notifier).reloadFromDatabase();
      } catch (err) {
        debugPrint('Error reloading profile after sync: $err');
      }
      ref.invalidate(userCompaniesProvider);
      ref.invalidate(activeCompanyProvider);

      // Refresh pending count and ledger updates so UI immediately reflects synced changes
      ref.invalidate(pendingSyncCountProvider);
      ref.invalidate(businessSummaryProvider);
      ref.invalidate(ledgerUpdatesStreamProvider);

      return result;
    } catch (e) {
      debugPrint('SyncNotifier error during sync: $e');
      state = SyncStatus.idle;
      return SyncResult(
        success: false,
        errorMessage: e.toString(),
        timestamp: DateTime.now(),
      );
    } finally {
      _isSyncing = false;
    }
  }

  /// Automatically triggers background synchronization each time the app opens
  /// (cold start, app resume from background, or active company change).
  Future<void> autoSyncOnAppOpen() async {
    final now = DateTime.now();
    // Debounce to prevent multiple immediate sync triggers (e.g. rapid resume or widget rebuilds)
    if (_lastSyncTime != null && now.difference(_lastSyncTime!).inSeconds < 5) {
      return;
    }
    await triggerSync(isAutoSync: true);
  }
}

final syncControllerProvider =
    NotifierProvider<SyncNotifier, SyncStatus>(SyncNotifier.new);

/// Provider that listens to app startup, active company changes, and lifecycle events
/// to ensure automatic synchronization is triggered whenever the app opens.
final autoSyncProvider = Provider<void>((ref) {
  // Trigger auto-sync when active company changes
  ref.listen<Company>(activeCompanyProvider, (previous, next) {
    if (previous != null && previous.id != next.id) {
      ref.read(syncControllerProvider.notifier).autoSyncOnAppOpen();
    }
  });

  // Automatically trigger sync on provider initialization
  Future.microtask(() {
    ref.read(syncControllerProvider.notifier).autoSyncOnAppOpen();
  });
});

