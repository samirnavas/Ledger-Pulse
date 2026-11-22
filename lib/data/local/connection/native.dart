import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'connection.dart';

QueryExecutor openConnection([String uid = 'usr_default']) {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final sanitizedUid = sanitizeDatabaseIdentifier(uid);
    final developmentNamespace = developmentDatabaseNamespace();
    if (developmentNamespace != null) {
      return NativeDatabase.createInBackground(File(p.join(
        dbFolder.path,
        'ledger_pulse.dev.$developmentNamespace.$sanitizedUid.sqlite',
      )));
    }
    final targetPath = p.join(
      dbFolder.path,
      'ledger_pulse_$sanitizedUid.sqlite',
    );
    final targetFile = File(targetPath);

    if (!await targetFile.exists()) {
      // Check if an un-prefixed file exists for this user (e.g. ledger_pulse_<uuid>.sqlite)
      if (sanitizedUid.startsWith('usr_')) {
        final legacyUnprefixed = sanitizedUid.substring(4);
        if (legacyUnprefixed.isNotEmpty && legacyUnprefixed != 'default') {
          final legacyUserFile = File(
            p.join(dbFolder.path, 'ledger_pulse_$legacyUnprefixed.sqlite'),
          );
          if (await legacyUserFile.exists()) {
            try {
              debugPrint(
                'Adopting legacy un-prefixed user database: ${legacyUserFile.path} -> $targetPath',
              );
              await legacyUserFile.rename(targetPath);
            } catch (e) {
              debugPrint('Could not rename legacy user file, copying: $e');
              try {
                await legacyUserFile.copy(targetPath);
              } catch (_) {}
            }
          }
        }
      }

      // The oldest unscoped file has no reliable account binding. Leave it
      // available for a separately verified recovery instead of adopting it.
    }

    return NativeDatabase.createInBackground(targetFile);
  });
}
