import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/party_model.dart';
import '../models/transaction_model.dart';

part 'database.g.dart';

@DataClassName('PartyTableData')
class Parties extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get phoneNumber => text()();
  TextColumn get type => textEnum<PartyType>()();
  IntColumn get netBalanceInCents => integer().withDefault(const Constant(0))();
  DateTimeColumn get lastUpdated => dateTime()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('LedgerEntryTableData')
class LedgerEntries extends Table {
  TextColumn get id => text()();
  TextColumn get partyId => text().references(Parties, #id)();
  IntColumn get amountInCents => integer()();
  TextColumn get type => textEnum<EntryType>()();
  DateTimeColumn get date => dateTime()();
  TextColumn get note => text().nullable()();
  TextColumn get receiptPhotoUrl => text().nullable()();
  BoolColumn get isVoided => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('SyncOutboxTableData')
class SyncOutbox extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  TextColumn get action => text()();
  TextColumn get payload => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  TextColumn get status => text().withDefault(const Constant('pending'))();
  IntColumn get retryCount => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();
}

@DriftDatabase(tables: [Parties, LedgerEntries, SyncOutbox])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? e]) : super(e ?? _openConnection());

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator m) async {
          await m.createAll();
        },
        onUpgrade: (Migrator m, int from, int to) async {
          if (from < 2) {
            try {
              await m.addColumn(parties, parties.isDeleted);
            } catch (_) {}
            try {
              await m.addColumn(ledgerEntries, ledgerEntries.isVoided);
            } catch (_) {}
          }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
          try {
            await customStatement(
                'ALTER TABLE parties ADD COLUMN is_deleted INTEGER NOT NULL DEFAULT 0;');
          } catch (_) {}
          try {
            await customStatement(
                'ALTER TABLE ledger_entries ADD COLUMN is_voided INTEGER NOT NULL DEFAULT 0;');
          } catch (_) {}
        },
      );
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'ledger_pulse.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
