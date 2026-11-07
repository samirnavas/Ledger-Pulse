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
  IntColumn get revision => integer().withDefault(const Constant(0))();
  DateTimeColumn get remoteUpdatedAt => dateTime().named('remote_updated_at').nullable()();
  TextColumn get ownerId => text().named('owner_id').nullable()();

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
  IntColumn get revision => integer().withDefault(const Constant(0))();
  DateTimeColumn get remoteUpdatedAt => dateTime().named('remote_updated_at').nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('PartyTableData')
@TableIndex(name: 'parties_company_idx', columns: {#companyId})
class Parties extends Table {
  TextColumn get id => text()();
  TextColumn get companyId => text().references(Companies, #id).withDefault(const Constant('cmp_default'))();
  TextColumn get name => text()();
  TextColumn get phoneNumber => text()();
  TextColumn get type => textEnum<PartyType>()();
  IntColumn get netBalanceInCents => integer().withDefault(const Constant(0))();
  DateTimeColumn get lastUpdated => dateTime()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  TextColumn get syncStatus => textEnum<SyncRecordStatus>().withDefault(const Constant('pending'))();
  IntColumn get revision => integer().withDefault(const Constant(0))();
  DateTimeColumn get remoteUpdatedAt => dateTime().named('remote_updated_at').nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('LedgerEntryTableData')
@TableIndex(name: 'ledger_entries_company_party_date_idx', columns: {#companyId, #partyId, #date})
class LedgerEntries extends Table {
  TextColumn get id => text()();
  TextColumn get companyId => text().references(Companies, #id).withDefault(const Constant('cmp_default'))();
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
  IntColumn get revision => integer().withDefault(const Constant(0))();
  DateTimeColumn get remoteUpdatedAt => dateTime().named('remote_updated_at').nullable()();

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
  IntColumn get revision => integer().withDefault(const Constant(0))();
  DateTimeColumn get remoteUpdatedAt => dateTime().named('remote_updated_at').nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('SyncOutboxTableData')
@TableIndex(name: 'sync_outbox_table_record_idx', columns: {#targetTable, #recordId}, unique: true)
class SyncOutbox extends Table {
  TextColumn get id => text()();
  TextColumn get targetTable => text().named('table_name')();
  TextColumn get recordId => text().named('record_id')();
  TextColumn get mutationType => text().named('mutation_type')(); // INSERT, UPDATE, DELETE
  TextColumn get payload => text()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().named('last_error').nullable()();
  DateTimeColumn get nextAttemptAt => dateTime().named('next_attempt_at').nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
        {targetTable, recordId}
      ];
}

@DataClassName('SyncStateTableData')
class SyncState extends Table {
  TextColumn get targetTable => text().named('table_name')();
  TextColumn get companyId => text().named('company_id')();
  DateTimeColumn get lastPulledAt => dateTime().named('last_pulled_at').nullable()();

  @override
  Set<Column> get primaryKey => {targetTable, companyId};
}

extension SyncOutboxTableDataCompat on SyncOutboxTableData {
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

  String get entityType => targetTable;
  String get entityId => recordId;
  String get action => mutationType.toLowerCase();
  String get status => lastError != null ? 'error' : 'pending';
  int get retryCount => attempts;
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
  IntColumn get revision => integer().withDefault(const Constant(0))();
  DateTimeColumn get remoteUpdatedAt => dateTime().named('remote_updated_at').nullable()();

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
  IntColumn get revision => integer().withDefault(const Constant(0))();
  DateTimeColumn get remoteUpdatedAt => dateTime().named('remote_updated_at').nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('AccountTableData')
@TableIndex(name: 'accounts_company_kind_idx', columns: {#companyId, #kind})
class Accounts extends Table {
  TextColumn get id => text()();
  TextColumn get companyId => text().withDefault(const Constant('cmp_default'))();
  TextColumn get code => text()();
  TextColumn get name => text()();
  TextColumn get type => text()(); // asset, liability, equity, income, expense
  TextColumn get kind => text().withDefault(const Constant('system'))(); // wallet, category, system
  TextColumn get parentAccountId => text().nullable()();
  BoolColumn get isSystem => boolean().withDefault(const Constant(false))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get description => text().nullable()();
  IntColumn get currentBalanceInCents => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  TextColumn get syncStatus => textEnum<SyncRecordStatus>().withDefault(const Constant('pending'))();
  IntColumn get revision => integer().withDefault(const Constant(0))();
  DateTimeColumn get remoteUpdatedAt => dateTime().named('remote_updated_at').nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('VoucherTableData')
@TableIndex(name: 'vouchers_company_date_idx', columns: {#companyId, #date})
@TableIndex(name: 'vouchers_company_type_status_idx', columns: {#companyId, #type, #status})
class Vouchers extends Table {
  TextColumn get id => text()();
  TextColumn get companyId => text().withDefault(const Constant('cmp_default'))();
  TextColumn get voucherNumber => text()();
  TextColumn get type => text()(); // sales, purchase, receipt, payment, contra, journal, salesOrder, purchaseOrder, estimate, expense, income, transfer
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
  @ReferenceName('categoryVouchers')
  TextColumn get categoryAccountId => text().references(Accounts, #id).nullable()();
  @ReferenceName('walletVouchers')
  TextColumn get walletAccountId => text().references(Accounts, #id).nullable()();
  @ReferenceName('toWalletVouchers')
  TextColumn get toWalletAccountId => text().references(Accounts, #id).nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  TextColumn get syncStatus => textEnum<SyncRecordStatus>().withDefault(const Constant('pending'))();
  IntColumn get revision => integer().withDefault(const Constant(0))();
  DateTimeColumn get remoteUpdatedAt => dateTime().named('remote_updated_at').nullable()();

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
  IntColumn get revision => integer().withDefault(const Constant(0))();
  DateTimeColumn get remoteUpdatedAt => dateTime().named('remote_updated_at').nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('JournalLineTableData')
@TableIndex(name: 'journal_lines_journal_idx', columns: {#journalId})
@TableIndex(name: 'journal_lines_account_idx', columns: {#accountId})
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
  IntColumn get revision => integer().withDefault(const Constant(0))();
  DateTimeColumn get remoteUpdatedAt => dateTime().named('remote_updated_at').nullable()();

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
  IntColumn get revision => integer().withDefault(const Constant(0))();
  DateTimeColumn get remoteUpdatedAt => dateTime().named('remote_updated_at').nullable()();

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
  IntColumn get revision => integer().withDefault(const Constant(0))();
  DateTimeColumn get remoteUpdatedAt => dateTime().named('remote_updated_at').nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('SharedMembershipTableData')
@TableIndex(name: 'shared_memberships_profile_account_idx', columns: {#profileId, #accountId}, unique: true)
class SharedMemberships extends Table {
  TextColumn get id => text()();
  TextColumn get profileId => text().references(Companies, #id)();
  TextColumn get accountId => text()();
  TextColumn get role => text()(); // owner, admin, accountant, manager, data_entry, viewer
  DateTimeColumn get joinedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('SharedDeviceTableData')
@TableIndex(name: 'shared_devices_account_device_idx', columns: {#accountId, #deviceUuid}, unique: true)
class SharedDevices extends Table {
  TextColumn get id => text()();
  TextColumn get accountId => text()();
  TextColumn get deviceUuid => text()();
  TextColumn get deviceName => text()();
  TextColumn get platform => text()(); // android, ios, windows, web, macos, linux
  TextColumn get pushToken => text().nullable()();
  DateTimeColumn get lastSyncAt => dateTime().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('UserPreferenceTableData')
class UserPreferences extends Table {
  TextColumn get key => text()();
  TextColumn get profileId => text().nullable()();
  TextColumn get value => text()();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {key, profileId};
}

@DataClassName('ExpenseWalletTableData')
@TableIndex(name: 'exp_wallets_profile_idx', columns: {#profileId})
class ExpenseWallets extends Table {
  TextColumn get id => text()();
  TextColumn get profileId => text().references(Companies, #id)();
  TextColumn get name => text()();
  TextColumn get walletType => text().withDefault(const Constant('cash'))(); // cash, bank, credit_card, digital_wallet, savings
  TextColumn get currencyCode => text().withDefault(const Constant('INR'))();
  IntColumn get startingBalanceInCents => integer().withDefault(const Constant(0))();
  IntColumn get currentBalanceInCents => integer().withDefault(const Constant(0))();
  TextColumn get colorHex => text().nullable()();
  TextColumn get iconName => text().nullable()();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  TextColumn get syncStatus => textEnum<SyncRecordStatus>().withDefault(const Constant('pending'))();
  IntColumn get revision => integer().withDefault(const Constant(0))();
  DateTimeColumn get remoteUpdatedAt => dateTime().named('remote_updated_at').nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('ExpenseCategoryTableData')
@TableIndex(name: 'exp_categories_profile_type_idx', columns: {#profileId, #categoryType})
class ExpenseCategories extends Table {
  TextColumn get id => text()();
  TextColumn get profileId => text().references(Companies, #id)();
  TextColumn get name => text()();
  TextColumn get categoryType => text().withDefault(const Constant('expense'))(); // expense, income
  TextColumn get parentCategoryId => text().nullable()();
  TextColumn get iconName => text().nullable()();
  TextColumn get colorHex => text().nullable()();
  BoolColumn get isSystem => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  TextColumn get syncStatus => textEnum<SyncRecordStatus>().withDefault(const Constant('pending'))();
  IntColumn get revision => integer().withDefault(const Constant(0))();
  DateTimeColumn get remoteUpdatedAt => dateTime().named('remote_updated_at').nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('ExpenseTransactionTableData')
@TableIndex(name: 'exp_txns_profile_date_idx', columns: {#profileId, #transactionDate})
@TableIndex(name: 'exp_txns_wallet_idx', columns: {#walletId})
@TableIndex(name: 'exp_txns_category_idx', columns: {#categoryId})
class ExpenseTransactions extends Table {
  TextColumn get id => text()();
  TextColumn get profileId => text().references(Companies, #id)();
  TextColumn get transactionType => text()(); // expense, income, transfer
  IntColumn get amountInCents => integer()();
  @ReferenceName('outgoingTransactions')
  TextColumn get walletId => text().references(ExpenseWallets, #id)();
  @ReferenceName('incomingTransactions')
  TextColumn get toWalletId => text().references(ExpenseWallets, #id).nullable()();
  TextColumn get categoryId => text().references(ExpenseCategories, #id).nullable()();
  DateTimeColumn get transactionDate => dateTime()();
  TextColumn get note => text().nullable()();
  TextColumn get payeeOrPayer => text().nullable()();
  TextColumn get referenceNumber => text().nullable()();
  TextColumn get receiptPhotoUrl => text().nullable()();
  BoolColumn get isCleared => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  TextColumn get syncStatus => textEnum<SyncRecordStatus>().withDefault(const Constant('pending'))();
  IntColumn get revision => integer().withDefault(const Constant(0))();
  DateTimeColumn get remoteUpdatedAt => dateTime().named('remote_updated_at').nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('ExpenseBudgetTableData')
@TableIndex(name: 'exp_budgets_profile_category_idx', columns: {#profileId, #categoryId})
class ExpenseBudgets extends Table {
  TextColumn get id => text()();
  TextColumn get profileId => text().references(Companies, #id)();
  TextColumn get categoryId => text().references(ExpenseCategories, #id).nullable()();
  TextColumn get periodType => text().withDefault(const Constant('monthly'))(); // monthly, weekly, yearly
  IntColumn get amountInCents => integer()();
  DateTimeColumn get startDate => dateTime()();
  DateTimeColumn get endDate => dateTime().nullable()();
  IntColumn get alertThresholdPercent => integer().withDefault(const Constant(80))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  TextColumn get syncStatus => textEnum<SyncRecordStatus>().withDefault(const Constant('pending'))();
  IntColumn get revision => integer().withDefault(const Constant(0))();
  DateTimeColumn get remoteUpdatedAt => dateTime().named('remote_updated_at').nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('ExpenseRecurringRuleTableData')
@TableIndex(name: 'exp_recurring_profile_next_idx', columns: {#profileId, #nextRunDate})
class ExpenseRecurringRules extends Table {
  TextColumn get id => text()();
  TextColumn get profileId => text().references(Companies, #id)();
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
  IntColumn get revision => integer().withDefault(const Constant(0))();
  DateTimeColumn get remoteUpdatedAt => dateTime().named('remote_updated_at').nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('ExpenseAttachmentTableData')
@TableIndex(name: 'exp_attachments_profile_txn_idx', columns: {#profileId, #transactionId})
class ExpenseAttachments extends Table {
  TextColumn get id => text()();
  TextColumn get profileId => text().references(Companies, #id)();
  TextColumn get transactionId => text().references(ExpenseTransactions, #id)();
  TextColumn get filePath => text()();
  TextColumn get fileType => text().nullable()(); // image/jpeg, application/pdf
  IntColumn get fileSize => integer().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  TextColumn get syncStatus => textEnum<SyncRecordStatus>().withDefault(const Constant('pending'))();
  IntColumn get revision => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [
  Companies,
  UserProfiles,
  SharedMemberships,
  SharedDevices,
  UserPreferences,
  Parties,
  LedgerEntries,
  AuditLogs,
  SyncOutbox,
  SyncState,
  InventoryItems,
  StockLedger,
  Vouchers,
  Accounts,
  Journals,
  JournalLines,
  Budgets,
  RecurringRules,
  ExpenseWallets,
  ExpenseCategories,
  ExpenseTransactions,
  ExpenseBudgets,
  ExpenseRecurringRules,
  ExpenseAttachments,
])
class AppDatabase extends _$AppDatabase {
  final String userId;

  AppDatabase([QueryExecutor? e, String? userId])
      : userId = userId ?? 'usr_default',
        super(e ?? _openConnection(userId ?? 'usr_default'));

  @override
  int get schemaVersion => 11;

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
            } catch (_) {}
            try {
              await customStatement(
                  'ALTER TABLE parties ADD COLUMN updated_at INTEGER NOT NULL DEFAULT 0;');
            } catch (_) {}
            try {
              await customStatement(
                  "UPDATE parties SET updated_at = CAST(strftime('%s', updated_at) AS INTEGER) WHERE typeof(updated_at) = 'text';");
              await customStatement(
                  "UPDATE parties SET updated_at = CAST(strftime('%s', 'now') AS INTEGER) WHERE updated_at = 0;");
            } catch (_) {}
            try {
              await m.addColumn(schema.parties, schema.parties.syncStatus);
            } catch (_) {}
            try {
              await customStatement(
                  'ALTER TABLE ledger_entries ADD COLUMN updated_at INTEGER NOT NULL DEFAULT 0;');
            } catch (_) {}
            try {
              await customStatement(
                  "UPDATE ledger_entries SET updated_at = CAST(strftime('%s', updated_at) AS INTEGER) WHERE typeof(updated_at) = 'text';");
              await customStatement(
                  "UPDATE ledger_entries SET updated_at = CAST(strftime('%s', 'now') AS INTEGER) WHERE updated_at = 0;");
            } catch (_) {}
            try {
              await m.addColumn(schema.ledgerEntries, schema.ledgerEntries.isDeleted);
              await m.addColumn(schema.ledgerEntries, schema.ledgerEntries.syncStatus);
            } catch (_) {}
            try {
              await customStatement(
                  'ALTER TABLE audit_logs ADD COLUMN updated_at INTEGER NOT NULL DEFAULT 0;');
            } catch (_) {}
            try {
              await customStatement(
                  "UPDATE audit_logs SET updated_at = CAST(strftime('%s', updated_at) AS INTEGER) WHERE typeof(updated_at) = 'text';");
              await customStatement(
                  "UPDATE audit_logs SET updated_at = CAST(strftime('%s', 'now') AS INTEGER) WHERE updated_at = 0;");
            } catch (_) {}
            try {
              await m.addColumn(schema.auditLogs, schema.auditLogs.isDeleted);
              await m.addColumn(schema.auditLogs, schema.auditLogs.syncStatus);
            } catch (_) {}
            try {
              await m.addColumn(schema.inventoryItems, schema.inventoryItems.isDeleted);
              await m.addColumn(schema.inventoryItems, schema.inventoryItems.syncStatus);
            } catch (_) {}
            try {
              await customStatement(
                  'ALTER TABLE stock_ledger ADD COLUMN updated_at INTEGER NOT NULL DEFAULT 0;');
            } catch (_) {}
            try {
              await customStatement(
                  "UPDATE stock_ledger SET updated_at = CAST(strftime('%s', updated_at) AS INTEGER) WHERE typeof(updated_at) = 'text';");
              await customStatement(
                  "UPDATE stock_ledger SET updated_at = CAST(strftime('%s', 'now') AS INTEGER) WHERE updated_at = 0;");
            } catch (_) {}
            try {
              await m.addColumn(schema.stockLedger, schema.stockLedger.isDeleted);
              await m.addColumn(schema.stockLedger, schema.stockLedger.syncStatus);
            } catch (_) {}
            try {
              await m.addColumn(schema.vouchers, schema.vouchers.isDeleted);
              await m.addColumn(schema.vouchers, schema.vouchers.syncStatus);
            } catch (_) {}
            try {
              await m.deleteTable('sync_outbox');
            } catch (_) {}
            try {
              await m.createTable(schema.syncOutbox);
            } catch (_) {}
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
          from8To9: (m, schema) async {
            await m.createTable(schema.syncState);
            // Recreate sync_outbox to gain the UNIQUE (table_name, record_id) table constraint
            await customStatement('''
              CREATE TABLE IF NOT EXISTS "sync_outbox_v9" (
                "id" TEXT NOT NULL,
                "table_name" TEXT NOT NULL,
                "record_id" TEXT NOT NULL,
                "mutation_type" TEXT NOT NULL,
                "payload" TEXT NOT NULL,
                "attempts" INTEGER NOT NULL DEFAULT 0,
                "last_error" TEXT NULL,
                "next_attempt_at" INTEGER NULL,
                "created_at" INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)),
                PRIMARY KEY ("id"),
                UNIQUE ("table_name", "record_id")
              );
            ''');
            await customStatement('''
              INSERT OR IGNORE INTO "sync_outbox_v9" ("id", "table_name", "record_id", "mutation_type", "payload", "created_at")
              SELECT "id", "table_name", "record_id", "mutation_type", "payload", "created_at" FROM "sync_outbox";
            ''');
            await customStatement('DROP TABLE "sync_outbox";');
            await customStatement('ALTER TABLE "sync_outbox_v9" RENAME TO "sync_outbox";');
            await customStatement(
                'CREATE UNIQUE INDEX IF NOT EXISTS sync_outbox_table_record_idx ON sync_outbox (table_name, record_id);');

            final domainTables = [
              schema.companies,
              schema.userProfiles,
              schema.parties,
              schema.ledgerEntries,
              schema.auditLogs,
              schema.inventoryItems,
              schema.stockLedger,
              schema.vouchers,
              schema.accounts,
              schema.journals,
              schema.journalLines,
              schema.budgets,
              schema.recurringRules,
            ];

            for (final table in domainTables) {
              if (table.columnsByName.containsKey('revision')) {
                await m.addColumn(table, table.columnsByName['revision']!);
              }
              if (table.columnsByName.containsKey('remote_updated_at')) {
                await m.addColumn(table, table.columnsByName['remote_updated_at']!);
              }
            }
          },
          from9To10: (m, schema) async {
            try {
              await customStatement('ALTER TABLE companies ADD COLUMN owner_id TEXT;');
            } catch (_) {}

            await m.addColumn(schema.accounts, schema.accounts.kind);

            // Backfill accounts.kind
            await customStatement(
                "UPDATE accounts SET kind = 'wallet' WHERE id LIKE '%_acc_wallet_%' OR id LIKE '%_wallet_cash' OR id LIKE '%_wallet_bank';");
            await customStatement(
                "UPDATE accounts SET kind = 'category' WHERE kind = 'system' AND (id LIKE '%_acc_cat_%' OR type IN ('income', 'expense'));");

            // Repair orphan FK references before creating indexes
            await customStatement(
                "UPDATE vouchers SET wallet_account_id = NULL WHERE wallet_account_id IS NOT NULL AND wallet_account_id NOT IN (SELECT id FROM accounts);");
            await customStatement(
                "UPDATE vouchers SET to_wallet_account_id = NULL WHERE to_wallet_account_id IS NOT NULL AND to_wallet_account_id NOT IN (SELECT id FROM accounts);");
            await customStatement(
                "UPDATE vouchers SET category_account_id = NULL WHERE category_account_id IS NOT NULL AND category_account_id NOT IN (SELECT id FROM accounts);");
            await customStatement(
                "UPDATE parties SET company_id = 'cmp_default' WHERE company_id NOT IN (SELECT id FROM companies);");
            await customStatement(
                "UPDATE ledger_entries SET company_id = 'cmp_default' WHERE company_id NOT IN (SELECT id FROM companies);");

            // Create new indexes
            await customStatement(
                'CREATE INDEX IF NOT EXISTS ledger_entries_company_party_date_idx ON ledger_entries (company_id, party_id, date);');
            await customStatement(
                'CREATE INDEX IF NOT EXISTS vouchers_company_date_idx ON vouchers (company_id, date);');
            await customStatement(
                'CREATE INDEX IF NOT EXISTS vouchers_company_type_status_idx ON vouchers (company_id, type, status);');
            await customStatement(
                'CREATE INDEX IF NOT EXISTS journal_lines_journal_idx ON journal_lines (journal_id);');
            await customStatement(
                'CREATE INDEX IF NOT EXISTS journal_lines_account_idx ON journal_lines (account_id);');
            await customStatement(
                'CREATE INDEX IF NOT EXISTS accounts_company_kind_idx ON accounts (company_id, kind);');
            await customStatement(
                'CREATE INDEX IF NOT EXISTS parties_company_idx ON parties (company_id);');
            await customStatement(
                'CREATE UNIQUE INDEX IF NOT EXISTS accounts_company_code_idx ON accounts (company_id, code) WHERE is_deleted = 0;');
          },
          from10To11: (m, schema) async {
            // 1. Create shared governance & system tables
            await m.createTable(schema.sharedMemberships);
            await m.createTable(schema.sharedDevices);
            await m.createTable(schema.userPreferences);

            // 2. Create dedicated single-entry Expense tables
            await m.createTable(schema.expenseWallets);
            await m.createTable(schema.expenseCategories);
            await m.createTable(schema.expenseTransactions);
            await m.createTable(schema.expenseBudgets);
            await m.createTable(schema.expenseRecurringRules);
            await m.createTable(schema.expenseAttachments);

            // 2b. Create indexes on newly added tables
            await m.createIndex(schema.sharedMembershipsProfileAccountIdx);
            await m.createIndex(schema.sharedDevicesAccountDeviceIdx);
            await m.createIndex(schema.expWalletsProfileIdx);
            await m.createIndex(schema.expCategoriesProfileTypeIdx);
            await m.createIndex(schema.expTxnsProfileDateIdx);
            await m.createIndex(schema.expTxnsWalletIdx);
            await m.createIndex(schema.expTxnsCategoryIdx);
            await m.createIndex(schema.expBudgetsProfileCategoryIdx);
            await m.createIndex(schema.expRecurringProfileNextIdx);
            await m.createIndex(schema.expAttachmentsProfileTxnIdx);

            // 3. Backfill shared_memberships from companies.owner_id
            await customStatement('''
              INSERT OR IGNORE INTO shared_memberships (id, profile_id, account_id, role, joined_at, updated_at)
              SELECT lower(hex(randomblob(16))), id, owner_id, 'owner', 
                     COALESCE(created_at, CAST(strftime('%s', 'now') AS INTEGER)), 
                     COALESCE(updated_at, CAST(strftime('%s', 'now') AS INTEGER))
              FROM companies
              WHERE owner_id IS NOT NULL AND owner_id != '';
            ''');

            // 4. Backfill Wallets from accounts where kind = 'wallet'
            await customStatement('''
              INSERT OR IGNORE INTO expense_wallets (
                id, profile_id, name, wallet_type, starting_balance_in_cents, current_balance_in_cents,
                created_at, updated_at, is_deleted, sync_status, revision
              )
              SELECT a.id, a.company_id, a.name, 'cash', 0, a.current_balance_in_cents,
                     a.created_at, a.updated_at, a.is_deleted, a.sync_status, a.revision
              FROM accounts a
              JOIN companies c ON c.id = a.company_id
              WHERE c.mode IN ('expense', 'expenseTracker') 
                AND a.kind = 'wallet'
                AND a.is_deleted = 0;
            ''');

            // 5. Backfill Categories from accounts where kind = 'category'
            await customStatement('''
              INSERT OR IGNORE INTO expense_categories (
                id, profile_id, name, category_type, is_system,
                created_at, updated_at, is_deleted, sync_status, revision
              )
              SELECT a.id, a.company_id, a.name,
                     CASE WHEN a.type = 'income' THEN 'income' ELSE 'expense' END,
                     a.is_system, a.created_at, a.updated_at, a.is_deleted, a.sync_status, a.revision
              FROM accounts a
              JOIN companies c ON c.id = a.company_id
              WHERE c.mode IN ('expense', 'expenseTracker')
                AND (a.kind = 'category' OR a.type IN ('income', 'expense'))
                AND a.is_deleted = 0;
            ''');

            // 6. Backfill Transactions from vouchers (expense, income, transfer)
            await customStatement('''
              INSERT OR IGNORE INTO expense_transactions (
                id, profile_id, transaction_type, amount_in_cents,
                wallet_id, to_wallet_id, category_id, transaction_date,
                note, reference_number, receipt_photo_url,
                created_at, updated_at, is_deleted, sync_status, revision
              )
              SELECT v.id, v.company_id, v.type, v.total_amount_in_cents,
                     COALESCE(v.wallet_account_id, (SELECT id FROM expense_wallets WHERE profile_id = v.company_id LIMIT 1), 'wal_default'),
                     v.to_wallet_account_id, v.category_account_id, v.date,
                     v.narration, v.reference_number, v.receipt_photo_url,
                     v.created_at, v.updated_at, v.is_deleted, v.sync_status, v.revision
              FROM vouchers v
              JOIN companies c ON c.id = v.company_id
              WHERE c.mode IN ('expense', 'expenseTracker')
                AND v.type IN ('expense', 'income', 'transfer')
                AND v.is_deleted = 0;
            ''');

            // 7. Backfill Budgets
            await customStatement('''
              INSERT OR IGNORE INTO expense_budgets (
                id, profile_id, category_id, period_type, amount_in_cents,
                start_date, created_at, updated_at, is_deleted, sync_status, revision
              )
              SELECT b.id, b.company_id, b.category_account_id, b.period_type, b.amount_in_cents,
                     b.start_date, b.created_at, b.updated_at, b.is_deleted, b.sync_status, b.revision
              FROM budgets b
              JOIN companies c ON c.id = b.company_id
              WHERE c.mode IN ('expense', 'expenseTracker') AND b.is_deleted = 0;
            ''');

            // 8. Backfill Recurring Rules
            await customStatement('''
              INSERT OR IGNORE INTO expense_recurring_rules (
                id, profile_id, template_json, interval_type, interval_count,
                next_run_date, end_date, is_active, created_at, updated_at, is_deleted, sync_status, revision
              )
              SELECT r.id, r.company_id, r.template_json, r.interval_type, r.interval_count,
                     r.next_run_date, r.end_date, r.is_active, r.created_at, r.updated_at, r.is_deleted, r.sync_status, r.revision
              FROM recurring_rules r
              JOIN companies c ON c.id = r.company_id
              WHERE c.mode IN ('expense', 'expenseTracker') AND r.is_deleted = 0;
            ''');
          },
        ),
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
}

QueryExecutor _openConnection([String uid = 'usr_default']) {
  return impl.openConnection(uid);
}
