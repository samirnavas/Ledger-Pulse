import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

QueryExecutor openConnection([String uid = 'usr_default']) {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final sanitizedUid = uid.isEmpty ? 'usr_default' : uid.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final targetPath = p.join(dbFolder.path, 'ledger_pulse_$sanitizedUid.sqlite');
    final targetFile = File(targetPath);

    if (!await targetFile.exists()) {
      final legacyFile = File(p.join(dbFolder.path, 'ledger_pulse.sqlite'));
      if (await legacyFile.exists()) {
        try {
          final executor = NativeDatabase(legacyFile);
          await executor.ensureOpen(const _DummyUser());
          final result = await executor.runSelect('SELECT COUNT(DISTINCT id) as cnt FROM user_profiles WHERE is_deleted = 0;', []);
          await executor.close();

          int count = 0;
          if (result.isNotEmpty) {
            count = (result.first['cnt'] as num?)?.toInt() ?? 0;
          }

          if (count <= 1) {
            debugPrint('Migrating single-user legacy database ledger_pulse.sqlite -> $targetPath');
            await legacyFile.rename(targetPath);
          }
        } catch (e) {
          debugPrint('Legacy DB check failed, copying legacy file to user DB: $e');
          try {
            await legacyFile.copy(targetPath);
          } catch (_) {}
        }
      }
    }

    return NativeDatabase(targetFile);
  });
}

class _DummyUser implements QueryExecutorUser {
  const _DummyUser();
  @override
  Future<void> beforeOpen(QueryExecutor executor, OpeningDetails details) async {}
  @override
  int get schemaVersion => 9;
}
