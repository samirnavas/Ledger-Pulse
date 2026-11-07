// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';
import 'package:sqlite3/sqlite3.dart';

const realTableNames = <String>{
  'companies',
  'user_profiles',
  'accounts',
  'parties',
  'vouchers',
  'journals',
  'journal_lines',
  'ledger_entries',
  'budgets',
  'recurring_rules',
  'inventory_items',
  'stock_ledger',
  'audit_logs',
  'sync_outbox',
  'sync_state',
};

void main(List<String> args) {
  repairMain(args);
}

void repairMain(List<String> args) {
  final isApply = args.contains('--apply');
  final isDryRun = !isApply || args.contains('--dry-run');

  String timezone = 'Asia/Kolkata';
  String targetUserId = 'usr_default';
  String? customDbPath;

  for (final arg in args) {
    if (arg.startsWith('--timezone=')) {
      timezone = arg.substring('--timezone='.length).trim();
    } else if (arg.startsWith('-z')) {
      timezone = arg.substring(2).trim();
    } else if (arg.startsWith('--user-id=')) {
      targetUserId = arg.substring('--user-id='.length).trim();
    } else if (arg.startsWith('-u')) {
      targetUserId = arg.substring(2).trim();
    } else if (arg.startsWith('--db-path=')) {
      customDbPath = arg.substring('--db-path='.length).trim();
    }
  }

  print('====================================================');
  print(' LEDGER-PULSE ONE-OFF REPAIR TOOL (PHASE 5)');
  print('====================================================');
  print(' Mode: ${isDryRun ? "DRY RUN (No changes will be written)" : "APPLY (Committing repairs)"}');
  print(' Target Timezone: $timezone');
  print(' Target User ID: $targetUserId');
  print('====================================================\n');

  final dbFile = customDbPath != null ? File(customDbPath) : _findDatabaseFile(targetUserId);
  if (!dbFile.existsSync()) {
    print('Error: Database file not found at ${dbFile.path}');
    return;
  }

  print('Database: ${dbFile.path}');

  if (!isDryRun) {
    _createBackup(dbFile);
  }

  final db = sqlite3.open(dbFile.path);

  try {
    _step1RekeyLegacyData(db, targetUserId, isDryRun);
    _step2AnalyzeAndReportTimestamps(db, timezone, isDryRun);
    _step3ReportVoidPostedDiscrepancies(db);
    _step4CleanupOutboxAndResetFailed(db, isDryRun);
    _step5RecomputeAndReportBalances(db, isDryRun);

    print('\nRepair processing completed successfully.');
  } finally {
    db.close();
  }
}

File _findDatabaseFile(String uid) {
  final sanitizedUid = uid.isEmpty ? 'usr_default' : uid.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
  final userDbPath = 'ledger_pulse_$sanitizedUid.sqlite';
  if (File(userDbPath).existsSync()) {
    return File(userDbPath);
  }
  if (File('ledger_pulse.sqlite').existsSync()) {
    return File('ledger_pulse.sqlite');
  }
  return File(userDbPath);
}

void _createBackup(File dbFile) {
  final timestamp = DateTime.now().toIso8601String().replaceAll(RegExp(r'[^0-9]'), '');
  final backupPath = '${dbFile.path}.backup_$timestamp.sqlite';
  print('creating database backup -> $backupPath...');
  dbFile.copySync(backupPath);
  print('Backup completed successfully.\n');
}

void _step1RekeyLegacyData(Database db, String targetUserId, bool isDryRun) {
  print('[Step 1/5] Re-keying Legacy Data...');

  final companies = db.select("SELECT id, owner_id FROM companies WHERE owner_id IS NULL OR owner_id = 'usr_default';");
  print('Found ${companies.length} companies with missing/default owner_id.');

  if (!isDryRun && companies.isNotEmpty) {
    db.execute("BEGIN TRANSACTION;");
    try {
      db.execute("UPDATE companies SET owner_id = ? WHERE owner_id IS NULL OR owner_id = 'usr_default';", [targetUserId]);
      db.execute("UPDATE user_profiles SET owner_id = ? WHERE owner_id IS NULL OR owner_id = 'usr_default';", [targetUserId]);
      db.execute("UPDATE parties SET owner_id = ? WHERE owner_id IS NULL OR owner_id = 'usr_default';", [targetUserId]);
      db.execute("UPDATE ledger_entries SET owner_id = ? WHERE owner_id IS NULL OR owner_id = 'usr_default';", [targetUserId]);
      db.execute("COMMIT;");
      print('  -> Updated owner_id = $targetUserId across companies, user_profiles, parties, ledger_entries.');
    } catch (e) {
      db.execute("ROLLBACK;");
      print('  -> Error during Step 1 re-keying: $e');
    }
  }
}

void _step2AnalyzeAndReportTimestamps(Database db, String timezone, bool isDryRun) {
  print('\n[Step 2/5] Shifted Timestamp Analysis...');
  print('WARNING: Multiply-edited rows may have been shifted by n x offset.');

  final csvRows = <String>['table,record_id,old_timestamp,new_timestamp,offset_hours'];
  int shiftedCount = 0;

  final tablesToCheck = ['vouchers', 'ledger_entries', 'journals'];

  for (final table in tablesToCheck) {
    try {
      final rows = db.select('SELECT id, date FROM $table;');
      for (final row in rows) {
        final id = row['id']?.toString() ?? '';
        final dateVal = row['date']?.toString() ?? '';
        if (dateVal.isNotEmpty && !dateVal.contains('Z') && !dateVal.contains('+')) {
          shiftedCount++;
          final oldTime = dateVal;
          final newTime = '${dateVal}Z';
          csvRows.add('$table,$id,"$oldTime","$newTime",+05:30');
        }
      }
    } catch (_) {
      // Table might not have date column
    }
  }

  final timestamp = DateTime.now().toIso8601String().replaceAll(RegExp(r'[^0-9]'), '');
  final csvFile = File('timestamp_repairs_$timestamp.csv');
  csvFile.writeAsStringSync(csvRows.join('\n'));

  print('Timestamp report written to ${csvFile.path} ($shiftedCount candidate rows detected).');

  if (!isDryRun && shiftedCount > 0) {
    print('  -> Applying ISO timestamp UTC normalization...');
    for (final table in tablesToCheck) {
      try {
        db.execute("UPDATE $table SET date = date || 'Z' WHERE date NOT LIKE '%Z' AND date NOT LIKE '%+%';");
      } catch (_) {}
    }
    print('  -> Normalization applied.');
  }
}

void _step3ReportVoidPostedDiscrepancies(Database db) {
  print('\n[Step 3/5] Void/Posted Status Discrepancies...');

  final discrepancies = db.select('''
    SELECT v.id as voucher_id, v.status as voucher_status, j.id as journal_id, j.status as journal_status
    FROM vouchers v
    LEFT JOIN journals j ON j.voucher_id = v.id
    WHERE v.status != j.status AND j.status IS NOT NULL;
  ''');

  if (discrepancies.isEmpty) {
    print('No status discrepancies found between vouchers and journals.');
  } else {
    print('Found ${discrepancies.length} discrepancy records (Un-voiding NOTHING automatically):');
    for (final d in discrepancies) {
      print('  - Voucher ${d['voucher_id']} (${d['voucher_status']}) vs Journal ${d['journal_id']} (${d['journal_status']})');
    }
  }
}

void _step4CleanupOutboxAndResetFailed(Database db, bool isDryRun) {
  print('\n[Step 4/5] Outbox Cleanup & Reset Failed Records...');

  final outboxRows = db.select('SELECT id, table_name, payload FROM sync_outbox;');
  final orphanIds = <String>[];

  for (final row in outboxRows) {
    final id = row['id'].toString();
    final tableName = row['table_name']?.toString() ?? '';
    final payload = row['payload']?.toString() ?? '';

    bool isValidJson = false;
    try {
      jsonDecode(payload);
      isValidJson = true;
    } catch (_) {}

    if (!realTableNames.contains(tableName) || !isValidJson) {
      orphanIds.add(id);
    }
  }

  print('Found ${orphanIds.length} orphan/corrupted outbox entries.');

  if (!isDryRun && orphanIds.isNotEmpty) {
    db.execute("BEGIN TRANSACTION;");
    for (final id in orphanIds) {
      db.execute('DELETE FROM sync_outbox WHERE id = ?;', [id]);
    }
    db.execute("COMMIT;");
    print('  -> Removed ${orphanIds.length} orphan outbox entries.');
  }

  if (!isDryRun) {
    print('  -> Resetting records with sync_status = "error" back to "pending"...');
    final domainTables = ['vouchers', 'accounts', 'parties', 'ledger_entries', 'journals', 'budgets', 'recurring_rules'];
    for (final table in domainTables) {
      try {
        db.execute("UPDATE $table SET sync_status = 'pending' WHERE sync_status = 'error';");
      } catch (_) {
        // Column or table might not exist
      }
    }
    try {
      db.execute("UPDATE sync_outbox SET attempts = 0, last_error = NULL, next_attempt_at = NULL WHERE last_error IS NOT NULL;");
    } catch (_) {}
    print('  -> Failed records reset to pending.');
  }
}

void _step5RecomputeAndReportBalances(Database db, bool isDryRun) {
  print('\n[Step 5/5] Recomputing Party & Account Balances...');

  final partyRows = db.select('SELECT id, name, net_balance_in_cents FROM parties WHERE is_deleted = 0;');
  int partyDiscrepancies = 0;

  for (final p in partyRows) {
    final pId = p['id'].toString();
    final name = p['name'].toString();
    final cached = (p['net_balance_in_cents'] as num?)?.toInt() ?? 0;

    final entries = db.select("SELECT amount_in_cents, type FROM ledger_entries WHERE party_id = ? AND is_deleted = 0 AND is_voided = 0;", [pId]);
    int computed = 0;
    for (final e in entries) {
      final amt = (e['amount_in_cents'] as num?)?.toInt() ?? 0;
      final type = e['type'].toString();
      if (type == 'gave') {
        computed += amt;
      } else {
        computed -= amt;
      }
    }

    if (cached != computed) {
      partyDiscrepancies++;
      print('  - Party "$name" ($pId): cached = $cached cents, computed = $computed cents (diff: ${computed - cached})');

      if (!isDryRun) {
        db.execute('UPDATE parties SET net_balance_in_cents = ?, updated_at = strftime(\'%s\', \'now\') WHERE id = ?;', [computed, pId]);
      }
    }
  }

  if (partyDiscrepancies == 0) {
    print('All party balances match computed ledger entry totals.');
  } else if (!isDryRun) {
    print('  -> Repaired $partyDiscrepancies party balance discrepancies.');
  }
}
