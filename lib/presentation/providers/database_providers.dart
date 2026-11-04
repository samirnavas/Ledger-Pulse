import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/sync_engine.dart';
import '../../data/local/database.dart';
import 'auth_providers.dart';

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final authRepo = ref.watch(authRepositoryProvider);
  final uid = authRepo.currentUserId ?? 'usr_default';
  final db = AppDatabase(null, uid);
  ref.onDispose(() {
    db.close();
  });
  return db;
});

final syncEngineProvider = Provider<SyncEngine>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final engine = SyncEngine(db: db);
  ref.onDispose(() {
    engine.dispose();
  });
  return engine;
});
