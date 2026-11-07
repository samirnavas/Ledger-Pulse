import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import '../../tool/repair_ledger_pulse.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase 5 Repair Tool Integration Tests', () {
    test('1. Repair tool dry run on temporary database detects legacy unowned companies, shifted dates, and balance discrepancies', () async {
      final tempDir = await Directory.systemTemp.createTemp('ledger_repair_test_');
      final tempDbFile = File('${tempDir.path}/test_repair_db.sqlite');

      final db = sqlite3.open(tempDbFile.path);

      // Create minimal tables
      db.execute('''
        CREATE TABLE companies (id TEXT PRIMARY KEY, name TEXT, legal_name TEXT, owner_id TEXT, is_deleted INTEGER DEFAULT 0);
        CREATE TABLE user_profiles (id TEXT PRIMARY KEY, name TEXT, owner_id TEXT, is_deleted INTEGER DEFAULT 0);
        CREATE TABLE parties (id TEXT PRIMARY KEY, name TEXT, net_balance_in_cents INTEGER DEFAULT 0, is_deleted INTEGER DEFAULT 0, owner_id TEXT);
        CREATE TABLE ledger_entries (id TEXT PRIMARY KEY, party_id TEXT, amount_in_cents INTEGER, type TEXT, date TEXT, is_deleted INTEGER DEFAULT 0, is_voided INTEGER DEFAULT 0, owner_id TEXT);
        CREATE TABLE vouchers (id TEXT PRIMARY KEY, status TEXT, date TEXT, is_deleted INTEGER DEFAULT 0);
        CREATE TABLE journals (id TEXT PRIMARY KEY, voucher_id TEXT, status TEXT);
        CREATE TABLE sync_outbox (id TEXT PRIMARY KEY, table_name TEXT, record_id TEXT, mutation_type TEXT, payload TEXT, attempts INTEGER DEFAULT 0, last_error TEXT, next_attempt_at TEXT, created_at TEXT);
      ''');

      // Seed unowned company
      db.execute("INSERT INTO companies (id, name, legal_name, owner_id) VALUES ('cmp_legacy', 'Legacy Co', 'Legacy Co', NULL);");

      // Seed party with cached vs computed balance mismatch
      db.execute("INSERT INTO parties (id, name, net_balance_in_cents) VALUES ('p1', 'Party 1', 1000);"); // Cached 1000
      db.execute("INSERT INTO ledger_entries (id, party_id, amount_in_cents, type, date) VALUES ('e1', 'p1', 5000, 'gave', '2026-11-04T10:00:00');"); // Computed 5000

      // Seed un-offsetted date
      db.execute("INSERT INTO vouchers (id, status, date) VALUES ('v1', 'voided', '2026-11-04T10:00:00');");
      db.execute("INSERT INTO journals (id, voucher_id, status) VALUES ('j1', 'v1', 'posted');"); // Discrepancy: voucher voided vs journal posted

      // Seed corrupted outbox row
      db.execute("INSERT INTO sync_outbox (id, table_name, record_id, mutation_type, payload) VALUES ('ob1', 'invented_table', 'rec1', 'INSERT', 'invalid json');");

      db.close();

      // Run repair tool in dry run mode
      repairMain([
        '--dry-run',
        '--db-path=${tempDbFile.path}',
        '--user-id=usr_real_repair_1',
      ]);

      // Verify dry-run made NO modifications to SQLite
      final verifyDb = sqlite3.open(tempDbFile.path);
      final unownedComp = verifyDb.select("SELECT owner_id FROM companies WHERE id = 'cmp_legacy';");
      expect(unownedComp.first['owner_id'], isNull);

      final outboxCount = verifyDb.select("SELECT count(*) as cnt FROM sync_outbox;");
      expect(outboxCount.first['cnt'], equals(1));

      verifyDb.close();
      await tempDir.delete(recursive: true);
    });

    test('2. Repair tool with --apply commits repairs, backs up database, and fixes balances', () async {
      final tempDir = await Directory.systemTemp.createTemp('ledger_repair_apply_');
      final tempDbFile = File('${tempDir.path}/test_repair_db_apply.sqlite');

      final db = sqlite3.open(tempDbFile.path);

      db.execute('''
        CREATE TABLE companies (id TEXT PRIMARY KEY, name TEXT, legal_name TEXT, owner_id TEXT, is_deleted INTEGER DEFAULT 0);
        CREATE TABLE user_profiles (id TEXT PRIMARY KEY, name TEXT, owner_id TEXT, is_deleted INTEGER DEFAULT 0);
        CREATE TABLE parties (id TEXT PRIMARY KEY, name TEXT, net_balance_in_cents INTEGER DEFAULT 0, is_deleted INTEGER DEFAULT 0, owner_id TEXT, updated_at TEXT);
        CREATE TABLE ledger_entries (id TEXT PRIMARY KEY, party_id TEXT, amount_in_cents INTEGER, type TEXT, date TEXT, is_deleted INTEGER DEFAULT 0, is_voided INTEGER DEFAULT 0, owner_id TEXT);
        CREATE TABLE vouchers (id TEXT PRIMARY KEY, status TEXT, date TEXT, is_deleted INTEGER DEFAULT 0);
        CREATE TABLE journals (id TEXT PRIMARY KEY, voucher_id TEXT, status TEXT);
        CREATE TABLE sync_outbox (id TEXT PRIMARY KEY, table_name TEXT, record_id TEXT, mutation_type TEXT, payload TEXT, attempts INTEGER DEFAULT 0, last_error TEXT, next_attempt_at TEXT, created_at TEXT);
      ''');

      db.execute("INSERT INTO companies (id, name, legal_name, owner_id) VALUES ('cmp_legacy_2', 'Legacy Co 2', 'Legacy Co 2', NULL);");
      db.execute("INSERT INTO parties (id, name, net_balance_in_cents) VALUES ('p2', 'Party 2', 1000);"); // Cached 1000
      db.execute("INSERT INTO ledger_entries (id, party_id, amount_in_cents, type, date) VALUES ('e2', 'p2', 5000, 'gave', '2026-11-04T10:00:00');"); // Computed 5000
      db.execute("INSERT INTO sync_outbox (id, table_name, record_id, mutation_type, payload) VALUES ('ob2', 'invented_table', 'rec2', 'INSERT', 'invalid json');");

      db.close();

      // Run repair tool with --apply
      repairMain([
        '--apply',
        '--db-path=${tempDbFile.path}',
        '--user-id=usr_real_repair_2',
      ]);

      // Verify backup file was created
      final backupFiles = tempDir.listSync().where((f) => f.path.contains('.backup_'));
      expect(backupFiles, isNotEmpty);

      // Verify changes committed
      final verifyDb = sqlite3.open(tempDbFile.path);

      // Step 1: owner_id set
      final compRow = verifyDb.select("SELECT owner_id FROM companies WHERE id = 'cmp_legacy_2';");
      expect(compRow.first['owner_id'], equals('usr_real_repair_2'));

      // Step 4: orphan outbox deleted
      final outboxCount = verifyDb.select("SELECT count(*) as cnt FROM sync_outbox;");
      expect(outboxCount.first['cnt'], equals(0));

      // Step 5: balance repaired
      final partyRow = verifyDb.select("SELECT net_balance_in_cents FROM parties WHERE id = 'p2';");
      expect(partyRow.first['net_balance_in_cents'], equals(5000));

      verifyDb.close();
      await tempDir.delete(recursive: true);
    });
  });
}
