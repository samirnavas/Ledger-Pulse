import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_pulse/data/local/database.dart';
import 'package:ledger_pulse/data/models/party_model.dart';
import 'package:ledger_pulse/data/models/transaction_model.dart';
import 'package:ledger_pulse/data/local/outbox_helper.dart';

void main() {
  test(
    'Ledger repair moves all related records and queue payloads while preserving amounts',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final now = DateTime.now();
      for (final id in ['expense_source', 'ledger_destination']) {
        await db
            .into(db.profiles)
            .insert(ProfilesCompanion.insert(id: id, name: id));
        await db
            .into(db.companies)
            .insert(
              CompaniesCompanion.insert(
                id: id,
                name: id,
                legalName: id,
                mode: Value(id == 'expense_source' ? 'expense' : 'ledger'),
              ),
            );
      }
      for (var i = 0; i < 5; i++) {
        final id = 'party_$i';
        await db
            .into(db.parties)
            .insert(
              PartiesCompanion.insert(
                id: id,
                companyId: const Value('expense_source'),
                name: id,
                phoneNumber: '$i',
                type: PartyType.customer,
                lastUpdated: now,
              ),
            );
        await enqueueMutation(
          db: db,
          table: 'parties',
          recordId: id,
          type: 'UPSERT',
          fullRowMap: {'id': id, 'companyId': 'expense_source'},
        );
      }
      for (var i = 0; i < 14; i++) {
        final id = 'entry_$i';
        await db
            .into(db.ledgerEntries)
            .insert(
              LedgerEntriesCompanion.insert(
                id: id,
                companyId: const Value('expense_source'),
                partyId: 'party_${i % 5}',
                amountInCents: 1000 + i,
                type: EntryType.gave,
                date: now,
              ),
            );
        await enqueueMutation(
          db: db,
          table: 'ledger_entries',
          recordId: id,
          type: 'UPSERT',
          fullRowMap: {'id': id, 'companyId': 'expense_source'},
        );
      }
      final original = (await db.select(db.ledgerEntries).get())
          .map((e) => e.amountInCents)
          .reduce((a, b) => a + b);
      final sql = File('scripts/repair_misplaced_ledger_records.sql')
          .readAsStringSync()
          .replaceAll(RegExp(r'--[^\n]*'), '')
          .replaceAll(':source', "'expense_source'")
          .replaceAll(':destination', "'ledger_destination'")
          .replaceAll(':party_count', '5')
          .replaceAll(':entry_count', '14');
      for (final statement
          in sql.split(';').map((s) => s.trim()).where((s) => s.isNotEmpty)) {
        if (statement.startsWith('SELECT ')) continue;
        await db.customStatement(statement);
      }
      final entries = await db.select(db.ledgerEntries).get();
      expect(entries.length, 14);
      expect(entries.every((e) => e.companyId == 'ledger_destination'), isTrue);
      expect(
        entries.map((e) => e.amountInCents).reduce((a, b) => a + b),
        original,
      );
      final parties = await db.select(db.parties).get();
      expect(parties.length, 5);
      expect(parties.every((p) => p.companyId == 'ledger_destination'), isTrue);
      final queued = await db.select(db.syncOutbox).get();
      expect(queued.length, 19);
      for (final row in queued) {
        final payload = jsonDecode(row.payload) as Map<String, dynamic>;
        expect(payload['company_id'], 'ledger_destination');
        expect(payload['companyId'], 'ledger_destination');
        expect(payload['revision'], 1);
        expect(row.lastError, isNull);
      }
    },
  );
}
