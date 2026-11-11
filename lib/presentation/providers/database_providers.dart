import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/sync_engine.dart';
import '../../data/local/database.dart';
import 'auth_providers.dart';

/// Reactively resolves the active user ID for database partitioning.
/// Emits the authenticated Supabase user UUID if authenticated,
/// or 'usr_default' for unauthenticated/guest sessions.
final activeUserIdProvider = Provider<String>((ref) {
  final authState = ref.watch(authControllerProvider);
  if (authState.isAuthenticated && authState.userId != null && authState.userId!.isNotEmpty) {
    return authState.userId!;
  }
  // Secondary fallback: inspect authRepositoryProvider (e.g. for mocked unit tests or initial sync)
  final authRepo = ref.watch(authRepositoryProvider);
  if (authRepo.isAuthenticated && authRepo.currentUserId != null && authRepo.currentUserId!.isNotEmpty) {
    return authRepo.currentUserId!;
  }
  return 'usr_default';
});

/// Reactive Drift database provider scoped to the active user session.
/// Automatically closes the database on user logout or account switch,
/// and rebinds all dependent repositories and sync engines.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final uid = ref.watch(activeUserIdProvider);
  final db = AppDatabase(null, uid);
  ref.onDispose(() {
    try {
      db.close();
    } catch (e) {
      debugPrint('AppDatabase: Error closing database for $uid: $e');
    }
  });
  return db;
});

/// Reactive SyncEngine provider scoped to the active user's Drift database.
final syncEngineProvider = Provider<SyncEngine>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final uid = ref.watch(activeUserIdProvider);
  final engine = SyncEngine(db: db, activeUserId: uid);
  ref.onDispose(() {
    try {
      engine.dispose();
    } catch (e) {
      debugPrint('SyncEngine: Error disposing sync engine: $e');
    }
  });
  return engine;
});
