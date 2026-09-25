import 'dart:convert';
import 'package:drift/drift.dart';
import 'connection/connection.dart' as impl;

import '../models/party_model.dart';
import '../models/transaction_model.dart';

part 'database.g.dart';

enum SyncRecordStatus {
  pending,
  synced,
  error;
}

@DataClassName('CompanyTableData')
class Companies extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get legalName => text()();
  TextColumn get gstin => text().nullable()();
  TextColumn get stateCode => text().nullable()();
  TextColumn get dealerType => text().withDefault(const Constant('regular'))();
  TextColumn get currencyCode => text().withDefault(const Constant('INR'))();
  TextColumn get address => text().nullable()();
  TextColumn get email => text().nullable()();
  TextColumn get phoneNumber => text().nullable()();
  TextColumn get logoUrl => text().nullable()();
  TextColumn get signatureUrl => text().nullable()();
  TextColumn get signatoryName => text().nullable()();
  TextColumn get bankName => text().nullable()();
  TextColumn get bankAccountNumber => text().nullable()();
  TextColumn get bankIfsc => text().nullable()();
  TextColumn get upiId => text().nullable()();
  BoolColumn get isCloudSyncEnabled => boolean().withDefault(const Constant(true))();
  BoolColumn get isDropboxSyncEnabled => boolean().withDefault(const Constant(false))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  TextColumn get syncStatus => textEnum<SyncRecordStatus>().withDefault(const Constant('synced'))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('UserProfileTableData')
class UserProfiles extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get phoneNumber => text()();
  TextColumn get email => text()();
  TextColumn get businessName => text().nullable()();
  TextColumn get address => text().nullable()();
  TextColumn get gstin => text().nullable()();
  TextColumn get businessType => text().nullable()();
  TextColumn get bankName => text().nullable()();
  TextColumn get bankAccountNumber => text().nullable()();
  TextColumn get bankIfsc => text().nullable()();
  TextColumn get upiId => text().nullable()();
  TextColumn get activeCompanyId => text().withDefault(const Constant('cmp_default'))();
  TextColumn get role => text().withDefault(const Constant('admin'))();
  TextColumn get companiesJson => text().nullable()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  TextColumn get syncStatus => textEnum<SyncRecordStatus>().withDefault(const Constant('synced'))();

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
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  TextColumn get syncStatus => textEnum<SyncRecordStatus>().withDefault(const Constant('pending'))();

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
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  TextColumn get syncStatus => textEnum<SyncRecordStatus>().withDefault(const Constant('pending'))();

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
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  TextColumn get syncStatus => textEnum<SyncRecordStatus>().withDefault(const Constant('pending'))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('SyncOutboxTableData')
class SyncOutbox extends Table {
  TextColumn get id => text()();
  TextColumn get targetTable => text().named('table_name')();
  TextColumn get recordId => text().named('record_id')();
  TextColumn get mutationType => text().named('mutation_type')(); // INSERT, UPDATE, DELETE
  TextColumn get payload => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

extension SyncOutboxTableDataCompat on SyncOutboxTableData {
  String get tableName => targetTable;
  String get companyId {
    try {
      final map = jsonDecode(payload);
      if (map is Map && map['companyId'] != null) {
        return map['companyId'].toString();
      }
      if (map is Map && map['company_id'] != null) {
        return map['company_id'].toString();
      }
    } catch (_) {}
    return 'cmp_default';
  }

  String get entityType => tableName;
  String get entityId => recordId;
  String get action => mutationType.toLowerCase();
  String get status => 'pending';
  int get retryCount => 0;
  String? get lastError => null;
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
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  TextColumn get syncStatus => textEnum<SyncRecordStatus>().withDefault(const Constant('pending'))();

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
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  TextColumn get syncStatus => textEnum<SyncRecordStatus>().withDefault(const Constant('pending'))();

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
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  TextColumn get syncStatus => textEnum<SyncRecordStatus>().withDefault(const Constant('pending'))();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [
  Companies,
  UserProfiles,
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
  int get schemaVersion => 6;

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
              isDeleted: const Value(false),
              syncStatus: const Value(SyncRecordStatus.synced),
            ),
          );
          // Seed initial default user profile if created freshly
          await into(userProfiles).insert(
            UserProfilesCompanion.insert(
              id: 'usr_default',
              name: 'Samir Navas',
              phoneNumber: '+91 98765 43210',
              email: 'samir.navas@example.com',
              businessName: const Value('Ledger Pulse Enterprise'),
              address: const Value('Suite 402, Trade Tower, Bangalore, India'),
              gstin: const Value('29ABCDE1234F1ZH'),
              businessType: const Value('Retail & Wholesale'),
              activeCompanyId: const Value('cmp_default'),
              role: const Value('admin'),
              isDeleted: const Value(false),
              syncStatus: const Value(SyncRecordStatus.synced),
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
                  isDeleted: const Value(false),
                  syncStatus: const Value(SyncRecordStatus.synced),
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
          if (from < 5) {
            try {
              await m.addColumn(companies, companies.isDeleted);
              await m.addColumn(companies, companies.syncStatus);
            } catch (_) {}
            try {
              await m.addColumn(parties, parties.updatedAt);
              await m.addColumn(parties, parties.syncStatus);
            } catch (_) {}
            try {
              await m.addColumn(ledgerEntries, ledgerEntries.updatedAt);
              await m.addColumn(ledgerEntries, ledgerEntries.isDeleted);
              await m.addColumn(ledgerEntries, ledgerEntries.syncStatus);
            } catch (_) {}
            try {
              await m.addColumn(auditLogs, auditLogs.updatedAt);
              await m.addColumn(auditLogs, auditLogs.isDeleted);
              await m.addColumn(auditLogs, auditLogs.syncStatus);
            } catch (_) {}
            try {
              await m.addColumn(inventoryItems, inventoryItems.isDeleted);
              await m.addColumn(inventoryItems, inventoryItems.syncStatus);
            } catch (_) {}
            try {
              await m.addColumn(stockLedger, stockLedger.updatedAt);
              await m.addColumn(stockLedger, stockLedger.isDeleted);
              await m.addColumn(stockLedger, stockLedger.syncStatus);
            } catch (_) {}
            try {
              await m.addColumn(vouchers, vouchers.isDeleted);
              await m.addColumn(vouchers, vouchers.syncStatus);
            } catch (_) {}
            try {
              await m.deleteTable('sync_outbox');
              await m.createTable(syncOutbox);
            } catch (_) {}
          }
          if (from < 6) {
            try {
              await m.createTable(userProfiles);
              await into(userProfiles).insert(
                UserProfilesCompanion.insert(
                  id: 'usr_default',
                  name: 'Samir Navas',
                  phoneNumber: '+91 98765 43210',
                  email: 'samir.navas@example.com',
                  businessName: const Value('Ledger Pulse Enterprise'),
                  address: const Value('Suite 402, Trade Tower, Bangalore, India'),
                  gstin: const Value('29ABCDE1234F1ZH'),
                  businessType: const Value('Retail & Wholesale'),
                  activeCompanyId: const Value('cmp_default'),
                  role: const Value('admin'),
                  isDeleted: const Value(false),
                  syncStatus: const Value(SyncRecordStatus.synced),
                ),
              );
            } catch (_) {}
            try {
              await m.addColumn(companies, companies.stateCode);
              await m.addColumn(companies, companies.dealerType);
              await m.addColumn(companies, companies.logoUrl);
              await m.addColumn(companies, companies.signatureUrl);
              await m.addColumn(companies, companies.signatoryName);
              await m.addColumn(companies, companies.bankName);
              await m.addColumn(companies, companies.bankAccountNumber);
              await m.addColumn(companies, companies.bankIfsc);
              await m.addColumn(companies, companies.upiId);
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
                'ALTER TABLE companies ADD COLUMN is_deleted INTEGER NOT NULL DEFAULT 0;');
          } catch (_) {}
          try {
            await customStatement(
                "ALTER TABLE companies ADD COLUMN sync_status TEXT NOT NULL DEFAULT 'synced';");
          } catch (_) {}
          try {
            await customStatement(
                'ALTER TABLE companies ADD COLUMN state_code TEXT;');
          } catch (_) {}
          try {
            await customStatement(
                "ALTER TABLE companies ADD COLUMN dealer_type TEXT NOT NULL DEFAULT 'regular';");
          } catch (_) {}
          try {
            await customStatement(
                'ALTER TABLE companies ADD COLUMN logo_url TEXT;');
          } catch (_) {}
          try {
            await customStatement(
                'ALTER TABLE companies ADD COLUMN signature_url TEXT;');
          } catch (_) {}
          try {
            await customStatement(
                'ALTER TABLE companies ADD COLUMN signatory_name TEXT;');
          } catch (_) {}
          try {
            await customStatement(
                'ALTER TABLE companies ADD COLUMN bank_name TEXT;');
          } catch (_) {}
          try {
            await customStatement(
                'ALTER TABLE companies ADD COLUMN bank_account_number TEXT;');
          } catch (_) {}
          try {
            await customStatement(
                'ALTER TABLE companies ADD COLUMN bank_ifsc TEXT;');
          } catch (_) {}
          try {
            await customStatement(
                'ALTER TABLE companies ADD COLUMN upi_id TEXT;');
          } catch (_) {}
          try {
            await customStatement(
                "ALTER TABLE parties ADD COLUMN updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP;");
          } catch (_) {}
          try {
            await customStatement(
                "ALTER TABLE parties ADD COLUMN sync_status TEXT NOT NULL DEFAULT 'pending';");
          } catch (_) {}
          try {
            await customStatement(
                "ALTER TABLE ledger_entries ADD COLUMN updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP;");
          } catch (_) {}
          try {
            await customStatement(
                'ALTER TABLE ledger_entries ADD COLUMN is_deleted INTEGER NOT NULL DEFAULT 0;');
          } catch (_) {}
          try {
            await customStatement(
                "ALTER TABLE ledger_entries ADD COLUMN sync_status TEXT NOT NULL DEFAULT 'pending';");
          } catch (_) {}
          try {
            await customStatement(
                "ALTER TABLE audit_logs ADD COLUMN updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP;");
          } catch (_) {}
          try {
            await customStatement(
                'ALTER TABLE audit_logs ADD COLUMN is_deleted INTEGER NOT NULL DEFAULT 0;');
          } catch (_) {}
          try {
            await customStatement(
                "ALTER TABLE audit_logs ADD COLUMN sync_status TEXT NOT NULL DEFAULT 'pending';");
          } catch (_) {}
          try {
            await customStatement(
                'ALTER TABLE inventory_items ADD COLUMN is_deleted INTEGER NOT NULL DEFAULT 0;');
          } catch (_) {}
          try {
            await customStatement(
                "ALTER TABLE inventory_items ADD COLUMN sync_status TEXT NOT NULL DEFAULT 'pending';");
          } catch (_) {}
          try {
            await customStatement(
                "ALTER TABLE stock_ledger ADD COLUMN updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP;");
          } catch (_) {}
          try {
            await customStatement(
                'ALTER TABLE stock_ledger ADD COLUMN is_deleted INTEGER NOT NULL DEFAULT 0;');
          } catch (_) {}
          try {
            await customStatement(
                "ALTER TABLE stock_ledger ADD COLUMN sync_status TEXT NOT NULL DEFAULT 'pending';");
          } catch (_) {}
          try {
            await customStatement(
                'ALTER TABLE vouchers ADD COLUMN is_deleted INTEGER NOT NULL DEFAULT 0;');
          } catch (_) {}
          try {
            await customStatement(
                "ALTER TABLE vouchers ADD COLUMN sync_status TEXT NOT NULL DEFAULT 'pending';");
          } catch (_) {}
          try {
            await customStatement(
                '''CREATE TABLE IF NOT EXISTS user_profiles (
                  id TEXT NOT NULL PRIMARY KEY,
                  name TEXT NOT NULL,
                  phone_number TEXT NOT NULL,
                  email TEXT NOT NULL,
                  business_name TEXT,
                  address TEXT,
                  gstin TEXT,
                  business_type TEXT,
                  bank_name TEXT,
                  bank_account_number TEXT,
                  bank_ifsc TEXT,
                  upi_id TEXT,
                  active_company_id TEXT NOT NULL DEFAULT 'cmp_default',
                  role TEXT NOT NULL DEFAULT 'admin',
                  companies_json TEXT,
                  is_deleted INTEGER NOT NULL DEFAULT 0,
                  created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
                  updated_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
                  sync_status TEXT NOT NULL DEFAULT 'synced'
                );''');
          } catch (_) {}
        },
      );
}

QueryExecutor _openConnection() {
  return impl.openConnection();
}
