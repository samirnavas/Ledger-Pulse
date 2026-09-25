import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/sync_engine.dart';
import '../../data/local/database.dart';

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
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
