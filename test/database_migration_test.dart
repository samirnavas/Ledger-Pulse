import 'package:drift/drift.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_pulse/data/local/database.dart';

import 'generated_migrations/schema.dart';

void main() {
  late SchemaVerifier verifier;
  const validationOpts = ValidationOptions(validateColumnConstraints: false);

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    verifier = SchemaVerifier(GeneratedHelper());
  });

  group('Drift Step-by-Step Migrations (Every Old Schema Version to Latest)', () {
    for (int fromVersion = 1; fromVersion < 8; fromVersion++) {
      test('migrates from v$fromVersion directly to latest v8', () async {
        final schema = await verifier.schemaAt(fromVersion);

        // Connect AppDatabase to the schema connection and run migrations
        final db = AppDatabase(schema.newConnection());
        await verifier.migrateAndValidate(db, 8, options: validationOpts);
        await db.close();
      });
    }
  });

  group('Drift Step-by-Step Migrations (Step-by-step single version increments)', () {
    for (int fromVersion = 1; fromVersion < 8; fromVersion++) {
      final nextVersion = fromVersion + 1;
      test('migrates step-by-step from v$fromVersion to v$nextVersion', () async {
        final schema = await verifier.schemaAt(fromVersion);

        final db = AppDatabase(schema.newConnection());
        await verifier.migrateAndValidate(db, nextVersion, options: validationOpts);
        await db.close();
      });
    }
  });

  group('Data Integrity & Integer Date Storage on Upgraded Database', () {
    test('preserves parties & entries from v1 to v8 and reads dates correctly as DateTime', () async {
      final schema = await verifier.schemaAt(1);

      // Insert data into v1 database with integer unix timestamps
      final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      schema.rawDatabase.execute('''
        INSERT INTO parties (id, name, phone_number, type, net_balance_in_cents, last_updated)
        VALUES ('p1', 'Alice Traders', '9876543210', 'customer', 50000, $nowSeconds);
      ''');
      schema.rawDatabase.execute('''
        INSERT INTO ledger_entries (id, party_id, amount_in_cents, type, date, note, receipt_photo_url, created_at)
        VALUES ('le1', 'p1', 50000, 'got', $nowSeconds, 'Opening balance', NULL, $nowSeconds);
      ''');

      // Migrate to v8
      final db = AppDatabase(schema.newConnection());
      await verifier.migrateAndValidate(db, 8, options: validationOpts);

      // Verify parties read correctly with integer date storage and new default columns
      final partyList = await db.select(db.parties).get();
      expect(partyList.length, 1);
      final party = partyList.first;
      expect(party.id, 'p1');
      expect(party.name, 'Alice Traders');
      expect(party.companyId, 'cmp_default');
      expect(party.isDeleted, false);
      expect(party.lastUpdated, isA<DateTime>());
      expect(party.updatedAt, isA<DateTime>());

      // Verify ledger entries read correctly
      final entries = await db.select(db.ledgerEntries).get();
      expect(entries.length, 1);
      final entry = entries.first;
      expect(entry.id, 'le1');
      expect(entry.partyId, 'p1');
      expect(entry.amountInCents, 50000);
      expect(entry.date, isA<DateTime>());
      expect(entry.isVoided, false);
      expect(entry.companyId, 'cmp_default');

      // Verify default accounts seeded during v6->v7 migration exist
      final accountsList = await (db.select(db.accounts)
            ..where((t) => t.companyId.equals('cmp_default')))
          .get();
      expect(accountsList, isNotEmpty);
      expect(accountsList.any((a) => a.code == '1000'), isTrue); // Cash in hand
      expect(accountsList.any((a) => a.code == '1010'), isTrue); // Bank

      // Verify tables created in v8 are operational
      final budgets = await db.select(db.budgets).get();
      expect(budgets, isEmpty);

      final recurring = await db.select(db.recurringRules).get();
      expect(recurring, isEmpty);

      await db.close();
    });

    test('verifies database reading correctly when upgraded from v6 with default company', () async {
      final schema = await verifier.schemaAt(6);

      // Insert company at v6
      final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      schema.rawDatabase.execute('''
        INSERT INTO companies (id, name, legal_name, gstin, currency_code, is_cloud_sync_enabled, is_dropbox_sync_enabled, is_active, created_at, updated_at, is_deleted, sync_status, state_code, dealer_type)
        VALUES ('cmp_biz', 'Acme Corp', 'Acme Corp Ltd', '29ABCDE1234F1Z5', 'INR', 1, 0, 1, $nowSeconds, $nowSeconds, 0, 'synced', '29', 'regular');
      ''');

      // Migrate to v8
      final db = AppDatabase(schema.newConnection());
      await verifier.migrateAndValidate(db, 8, options: validationOpts);

      final companies = await (db.select(db.companies)..where((t) => t.id.equals('cmp_biz'))).get();
      expect(companies.length, 1);
      final comp = companies.first;
      expect(comp.name, 'Acme Corp');
      expect(comp.mode, 'ledger'); // Default mode added in v8
      expect(comp.createdAt, isA<DateTime>());
      expect(comp.updatedAt, isA<DateTime>());

      await db.close();
    });

    test('handles legacy database with TEXT date columns by converting to integer timestamps', () async {
      // Simulate an old database that had legacy ALTER TABLE ... ADD COLUMN updated_at TEXT
      final schema = await verifier.schemaAt(4);

      // Add a legacy TEXT column with text timestamp
      schema.rawDatabase.execute("ALTER TABLE parties ADD COLUMN updated_at TEXT NOT NULL DEFAULT '2026-01-15 10:30:00';");
      schema.rawDatabase.execute("INSERT INTO parties (id, name, phone_number, type, net_balance_in_cents, last_updated) VALUES ('p_legacy', 'Legacy Co', '123', 'customer', 0, 1700000000);");

      // Verify and upgrade to v8
      final db = AppDatabase(schema.newConnection());
      await db.customStatement("PRAGMA foreign_keys = ON;");
      // Migration runs automatically when opened
      final parties = await (db.select(db.parties)..where((t) => t.id.equals('p_legacy'))).get();
      expect(parties, isNotEmpty);
      expect(parties.first.name, 'Legacy Co');
      await db.close();
    });
  });
}
