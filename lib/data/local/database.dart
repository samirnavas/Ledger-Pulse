import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/party_model.dart';
import '../models/transaction_model.dart';

part 'database.g.dart';

@DataClassName('CompanyTableData')
class Companies extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get legalName => text()();
  TextColumn get gstin => text().nullable()();
  TextColumn get currencyCode => text().withDefault(const Constant('INR'))();
  TextColumn get address => text().nullable()();
  TextColumn get email => text().nullable()();
  TextColumn get phoneNumber => text().nullable()();
  BoolColumn get isCloudSyncEnabled => boolean().withDefault(const Constant(true))();
  BoolColumn get isDropboxSyncEnabled => boolean().withDefault(const Constant(false))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('PartyTableData')
class Parties extends Table {
  TextColumn get id => text()();
  TextColumn get companyId => text().withDefault(const Constant('cmp_default'))();
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
  TextColumn get companyId => text().withDefault(const Constant('cmp_default'))();
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

@DataClassName('AuditLogTableData')
class AuditLogs extends Table {
  TextColumn get id => text()();
  TextColumn get companyId => text()();
  TextColumn get userId => text()();
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  TextColumn get action => text()();
  DateTimeColumn get timestamp => dateTime()();
  TextColumn get oldStateJson => text().nullable()();
  TextColumn get newStateJson => text().nullable()();
  TextColumn get diffJson => text().nullable()();
  TextColumn get checksum => text()();
  TextColumn get previousChecksum => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('SyncOutboxTableData')
class SyncOutbox extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get companyId => text().withDefault(const Constant('cmp_default'))();
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  TextColumn get action => text()();
  TextColumn get payload => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  TextColumn get status => text().withDefault(const Constant('pending'))();
  IntColumn get retryCount => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();
}

@DataClassName('InventoryItemTableData')
class InventoryItems extends Table {
  TextColumn get id => text()();
  TextColumn get companyId => text().withDefault(const Constant('cmp_default'))();
  TextColumn get sku => text()();
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();
  TextColumn get unit => text().withDefault(const Constant('PCS'))();
  IntColumn get purchasePriceInCents => integer().withDefault(const Constant(0))();
  IntColumn get sellingPriceInCents => integer().withDefault(const Constant(0))();
  RealColumn get currentStockQuantity => real().withDefault(const Constant(0.0))();
  RealColumn get minimumStockAlert => real().withDefault(const Constant(5.0))();
  TextColumn get hsnCode => text().nullable()();
  RealColumn get taxRatePercent => real().withDefault(const Constant(0.0))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('StockLedgerTableData')
class StockLedger extends Table {
  TextColumn get id => text()();
  TextColumn get companyId => text().withDefault(const Constant('cmp_default'))();
  TextColumn get itemId => text().references(InventoryItems, #id)();
  TextColumn get voucherId => text().nullable()();
  TextColumn get transactionType => text()(); // inward, outward, adjustment, wastage
  RealColumn get quantity => real()();
  IntColumn get unitCostInCents => integer().withDefault(const Constant(0))();
  IntColumn get totalCostInCents => integer().withDefault(const Constant(0))();
  RealColumn get runningStockQuantity => real().withDefault(const Constant(0.0))();
  DateTimeColumn get date => dateTime()();
  TextColumn get note => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('VoucherTableData')
class Vouchers extends Table {
  TextColumn get id => text()();
  TextColumn get companyId => text().withDefault(const Constant('cmp_default'))();
  TextColumn get voucherNumber => text()();
  TextColumn get type => text()(); // sales, purchase, receipt, payment, contra, journal, salesOrder, purchaseOrder, estimate
  DateTimeColumn get date => dateTime()();
  DateTimeColumn get dueDate => dateTime().nullable()();
  TextColumn get partyId => text().nullable()();
  TextColumn get partyName => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('posted'))();
  TextColumn get paymentMode => text().withDefault(const Constant('cash'))();
  IntColumn get subtotalInCents => integer().withDefault(const Constant(0))();
  IntColumn get taxInCents => integer().withDefault(const Constant(0))();
  IntColumn get discountInCents => integer().withDefault(const Constant(0))();
  IntColumn get totalAmountInCents => integer().withDefault(const Constant(0))();
  TextColumn get narration => text().nullable()();
  TextColumn get referenceNumber => text().nullable()();
  TextColumn get sourceVoucherId => text().nullable()();
  TextColumn get receiptPhotoUrl => text().nullable()();
  TextColumn get itemsJson => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [
  Companies,
  Parties,
  LedgerEntries,
  AuditLogs,
  SyncOutbox,
  InventoryItems,
  StockLedger,
  Vouchers,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? e]) : super(e ?? _openConnection());

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator m) async {
          await m.createAll();
          // Seed initial default company if created freshly
          await into(companies).insert(
            CompaniesCompanion.insert(
              id: 'cmp_default',
              name: 'Ledger Pulse Enterprise',
              legalName: 'Ledger Pulse Enterprise Pvt Ltd',
              gstin: const Value('29ABCDE1234F1ZH'),
              currencyCode: const Value('INR'),
              address: const Value('Suite 402, Trade Tower, Bangalore, India'),
              isCloudSyncEnabled: const Value(true),
              isDropboxSyncEnabled: const Value(false),
              isActive: const Value(true),
            ),
          );
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
          if (from < 3) {
            try {
              await m.createTable(companies);
              await into(companies).insert(
                CompaniesCompanion.insert(
                  id: 'cmp_default',
                  name: 'Ledger Pulse Enterprise',
                  legalName: 'Ledger Pulse Enterprise Pvt Ltd',
                  gstin: const Value('29ABCDE1234F1ZH'),
                  currencyCode: const Value('INR'),
                  address: const Value('Suite 402, Trade Tower, Bangalore, India'),
                  isCloudSyncEnabled: const Value(true),
                  isDropboxSyncEnabled: const Value(false),
                  isActive: const Value(true),
                ),
              );
            } catch (_) {}
            try {
              await m.addColumn(parties, parties.companyId);
            } catch (_) {}
            try {
              await m.addColumn(ledgerEntries, ledgerEntries.companyId);
            } catch (_) {}
            try {
              await m.addColumn(syncOutbox, syncOutbox.companyId);
            } catch (_) {}
            try {
              await m.createTable(auditLogs);
            } catch (_) {}
          }
          if (from < 4) {
            try {
              await m.createTable(inventoryItems);
            } catch (_) {}
            try {
              await m.createTable(stockLedger);
            } catch (_) {}
            try {
              await m.createTable(vouchers);
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
          try {
            await customStatement(
                "ALTER TABLE parties ADD COLUMN company_id TEXT NOT NULL DEFAULT 'cmp_default';");
          } catch (_) {}
          try {
            await customStatement(
                "ALTER TABLE ledger_entries ADD COLUMN company_id TEXT NOT NULL DEFAULT 'cmp_default';");
          } catch (_) {}
          try {
            await customStatement(
                "ALTER TABLE sync_outbox ADD COLUMN company_id TEXT NOT NULL DEFAULT 'cmp_default';");
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
