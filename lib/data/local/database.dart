import 'dart:convert';
import 'package:drift/drift.dart';
import 'connection/connection.dart' as impl;
import 'schema_steps.dart' as steps;

import '../models/account_model.dart';
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
  TextColumn get mode => text().withDefault(const Constant('ledger'))();
  TextColumn get enabledModulesJson => text().nullable()();
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
    } catch (_) {
      // Payload might not be JSON or may not contain companyId; fallback to default
    }
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
  TextColumn get categoryAccountId => text().nullable()();
  TextColumn get walletAccountId => text().nullable()();
  TextColumn get toWalletAccountId => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  TextColumn get syncStatus => textEnum<SyncRecordStatus>().withDefault(const Constant('pending'))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('AccountTableData')
class Accounts extends Table {
  TextColumn get id => text()();
  TextColumn get companyId => text().withDefault(const Constant('cmp_default'))();
  TextColumn get code => text()();
  TextColumn get name => text()();
  TextColumn get type => text()(); // asset, liability, equity, income, expense
  TextColumn get parentAccountId => text().nullable()();
  BoolColumn get isSystem => boolean().withDefault(const Constant(false))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get description => text().nullable()();
  IntColumn get currentBalanceInCents => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  TextColumn get syncStatus => textEnum<SyncRecordStatus>().withDefault(const Constant('pending'))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('JournalTableData')
class Journals extends Table {
  TextColumn get id => text()();
  TextColumn get companyId => text().withDefault(const Constant('cmp_default'))();
  TextColumn get journalNumber => text()();
  TextColumn get voucherId => text().nullable()();
  DateTimeColumn get date => dateTime()();
  TextColumn get narration => text().nullable()();
  IntColumn get totalAmountInCents => integer().withDefault(const Constant(0))();
  TextColumn get status => text().withDefault(const Constant('posted'))(); // posted, voided
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  TextColumn get syncStatus => textEnum<SyncRecordStatus>().withDefault(const Constant('pending'))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('JournalLineTableData')
class JournalLines extends Table {
  TextColumn get id => text()();
  TextColumn get companyId => text().withDefault(const Constant('cmp_default'))();
  TextColumn get journalId => text().references(Journals, #id)();
  TextColumn get accountId => text().references(Accounts, #id)();
  TextColumn get partyId => text().nullable()();
  IntColumn get debitInCents => integer().withDefault(const Constant(0))();
  IntColumn get creditInCents => integer().withDefault(const Constant(0))();
  TextColumn get narration => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  TextColumn get syncStatus => textEnum<SyncRecordStatus>().withDefault(const Constant('pending'))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('BudgetTableData')
class Budgets extends Table {
  TextColumn get id => text()();
  TextColumn get companyId => text().withDefault(const Constant('cmp_default'))();
  TextColumn get categoryAccountId => text()();
  TextColumn get periodType => text()(); // monthly, quarterly, yearly
  IntColumn get amountInCents => integer()();
  DateTimeColumn get startDate => dateTime()();
  BoolColumn get rolloverEnabled => boolean().withDefault(const Constant(false))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  TextColumn get syncStatus => textEnum<SyncRecordStatus>().withDefault(const Constant('pending'))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('RecurringRuleTableData')
class RecurringRules extends Table {
  TextColumn get id => text()();
  TextColumn get companyId => text().withDefault(const Constant('cmp_default'))();
  TextColumn get templateJson => text()();
  TextColumn get intervalType => text()(); // daily, weekly, monthly, yearly
  IntColumn get intervalCount => integer().withDefault(const Constant(1))();
  DateTimeColumn get nextRunDate => dateTime()();
  DateTimeColumn get endDate => dateTime().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
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
  Accounts,
  Journals,
  JournalLines,
  Budgets,
  RecurringRules,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? e]) : super(e ?? _openConnection());

  @override
  int get schemaVersion => 8;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator m) async {
          await m.createAll();
        },
        onUpgrade: steps.stepByStep(
          from1To2: (m, schema) async {
            await m.addColumn(schema.parties, schema.parties.isDeleted);
            await m.addColumn(schema.ledgerEntries, schema.ledgerEntries.isVoided);
          },
          from2To3: (m, schema) async {
            await m.createTable(schema.companies);
            await m.addColumn(schema.parties, schema.parties.companyId);
            await m.addColumn(schema.ledgerEntries, schema.ledgerEntries.companyId);
            await m.createTable(schema.auditLogs);
          },
          from3To4: (m, schema) async {
            await m.createTable(schema.inventoryItems);
            await m.createTable(schema.stockLedger);
            await m.createTable(schema.vouchers);
          },
          from4To5: (m, schema) async {
            try {
              await m.addColumn(schema.companies, schema.companies.isDeleted);
              await m.addColumn(schema.companies, schema.companies.syncStatus);
            } catch (e) {
              // Ignored if column already exists
            }
            try {
              await customStatement(
                  'ALTER TABLE parties ADD COLUMN updated_at INTEGER NOT NULL DEFAULT 0;');
            } catch (e) {
              // Ignored if column already exists
            }
            try {
              await customStatement(
                  "UPDATE parties SET updated_at = CAST(strftime('%s', updated_at) AS INTEGER) WHERE typeof(updated_at) = 'text';");
              await customStatement(
                  "UPDATE parties SET updated_at = CAST(strftime('%s', 'now') AS INTEGER) WHERE updated_at = 0;");
            } catch (e) {
              // Ignored if table lacks updated_at
            }
            try {
              await m.addColumn(schema.parties, schema.parties.syncStatus);
            } catch (e) {
              // Ignored if column already exists
            }
            try {
              await customStatement(
                  'ALTER TABLE ledger_entries ADD COLUMN updated_at INTEGER NOT NULL DEFAULT 0;');
            } catch (e) {
              // Ignored if column already exists
            }
            try {
              await customStatement(
                  "UPDATE ledger_entries SET updated_at = CAST(strftime('%s', updated_at) AS INTEGER) WHERE typeof(updated_at) = 'text';");
              await customStatement(
                  "UPDATE ledger_entries SET updated_at = CAST(strftime('%s', 'now') AS INTEGER) WHERE updated_at = 0;");
            } catch (e) {
              // Ignored if table lacks updated_at
            }
            try {
              await m.addColumn(schema.ledgerEntries, schema.ledgerEntries.isDeleted);
              await m.addColumn(schema.ledgerEntries, schema.ledgerEntries.syncStatus);
            } catch (e) {
              // Ignored if column already exists
            }
            try {
              await customStatement(
                  'ALTER TABLE audit_logs ADD COLUMN updated_at INTEGER NOT NULL DEFAULT 0;');
            } catch (e) {
              // Ignored if column already exists
            }
            try {
              await customStatement(
                  "UPDATE audit_logs SET updated_at = CAST(strftime('%s', updated_at) AS INTEGER) WHERE typeof(updated_at) = 'text';");
              await customStatement(
                  "UPDATE audit_logs SET updated_at = CAST(strftime('%s', 'now') AS INTEGER) WHERE updated_at = 0;");
            } catch (e) {
              // Ignored if table lacks updated_at
            }
            try {
              await m.addColumn(schema.auditLogs, schema.auditLogs.isDeleted);
              await m.addColumn(schema.auditLogs, schema.auditLogs.syncStatus);
            } catch (e) {
              // Ignored if column already exists
            }
            try {
              await m.addColumn(schema.inventoryItems, schema.inventoryItems.isDeleted);
              await m.addColumn(schema.inventoryItems, schema.inventoryItems.syncStatus);
            } catch (e) {
              // Ignored if column already exists
            }
            try {
              await customStatement(
                  'ALTER TABLE stock_ledger ADD COLUMN updated_at INTEGER NOT NULL DEFAULT 0;');
            } catch (e) {
              // Ignored if column already exists
            }
            try {
              await customStatement(
                  "UPDATE stock_ledger SET updated_at = CAST(strftime('%s', updated_at) AS INTEGER) WHERE typeof(updated_at) = 'text';");
              await customStatement(
                  "UPDATE stock_ledger SET updated_at = CAST(strftime('%s', 'now') AS INTEGER) WHERE updated_at = 0;");
            } catch (e) {
              // Ignored if table lacks updated_at
            }
            try {
              await m.addColumn(schema.stockLedger, schema.stockLedger.isDeleted);
              await m.addColumn(schema.stockLedger, schema.stockLedger.syncStatus);
            } catch (e) {
              // Ignored if column already exists
            }
            try {
              await m.addColumn(schema.vouchers, schema.vouchers.isDeleted);
              await m.addColumn(schema.vouchers, schema.vouchers.syncStatus);
            } catch (e) {
              // Ignored if column already exists
            }
            try {
              await m.deleteTable('sync_outbox');
            } catch (e) {
              // Ignored if table does not exist
            }
            try {
              await m.createTable(schema.syncOutbox);
            } catch (e) {
              // Ignored if table already exists
            }
          },
          from5To6: (m, schema) async {
            await m.createTable(schema.userProfiles);
            await m.addColumn(schema.companies, schema.companies.stateCode);
            await m.addColumn(schema.companies, schema.companies.dealerType);
            await m.addColumn(schema.companies, schema.companies.logoUrl);
            await m.addColumn(schema.companies, schema.companies.signatureUrl);
            await m.addColumn(schema.companies, schema.companies.signatoryName);
            await m.addColumn(schema.companies, schema.companies.bankName);
            await m.addColumn(schema.companies, schema.companies.bankAccountNumber);
            await m.addColumn(schema.companies, schema.companies.bankIfsc);
            await m.addColumn(schema.companies, schema.companies.upiId);
          },
          from6To7: (m, schema) async {
            await m.createTable(schema.accounts);
            final defaultAccounts = DefaultAccounts.getDefaultAccounts('cmp_default');
            for (final acc in defaultAccounts) {
              await into(accounts).insertOnConflictUpdate(
                AccountsCompanion.insert(
                  id: acc.id,
                  companyId: Value(acc.companyId),
                  code: acc.code,
                  name: acc.name,
                  type: acc.type.name,
                  parentAccountId: Value(acc.parentAccountId),
                  isSystem: Value(acc.isSystem),
                  isActive: Value(acc.isActive),
                  description: Value(acc.description),
                  currentBalanceInCents: Value(acc.currentBalanceInCents),
                  createdAt: Value(acc.createdAt),
                  updatedAt: Value(acc.updatedAt),
                  isDeleted: const Value(false),
                  syncStatus: const Value(SyncRecordStatus.synced),
                ),
              );
            }
            await m.createTable(schema.journals);
            await m.createTable(schema.journalLines);
          },
          from7To8: (m, schema) async {
            await m.addColumn(schema.companies, schema.companies.mode);
            await m.addColumn(schema.companies, schema.companies.enabledModulesJson);
            await m.addColumn(schema.vouchers, schema.vouchers.categoryAccountId);
            await m.addColumn(schema.vouchers, schema.vouchers.walletAccountId);
            await m.addColumn(schema.vouchers, schema.vouchers.toWalletAccountId);
            await m.createTable(schema.budgets);
            await m.createTable(schema.recurringRules);
          },
        ),
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
}

QueryExecutor _openConnection() {
  return impl.openConnection();
}
