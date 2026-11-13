import 'dart:async';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../core/network/sync_codec.dart';
import '../../core/network/sync_engine.dart';
import '../../domain/exceptions/ledger_exceptions.dart';
import '../local/audit_service.dart';
import '../local/database.dart';
import '../local/outbox_helper.dart';
import '../models/account_model.dart';
import '../models/audit_log_model.dart';
import '../models/company_model.dart';
import '../models/expense/expense_category_model.dart';
import '../models/rbac_model.dart';
import '../models/voucher_model.dart';
import '../security/access_control_service.dart';

/// Month summary data structure for expense tracker mode.
class ExpenseMonthSummary {
  final DateTime month;
  final int totalIncomeInCents;
  final int totalExpenseInCents;
  final int netInCents;
  final Map<String, int> walletBalancesInCents;
  final Map<String, int> categoryTotalsInCents;
  final Map<String, int> incomeCategoryTotalsInCents;
  final Map<String, int> expenseCategoryTotalsInCents;

  const ExpenseMonthSummary({
    required this.month,
    required this.totalIncomeInCents,
    required this.totalExpenseInCents,
    required this.netInCents,
    required this.walletBalancesInCents,
    required this.categoryTotalsInCents,
    this.incomeCategoryTotalsInCents = const {},
    this.expenseCategoryTotalsInCents = const {},
  });

  int get income => totalIncomeInCents;
  int get expense => totalExpenseInCents;
  int get net => netInCents;
  Map<String, int> get walletBalances => walletBalancesInCents;
  Map<String, int> get categoryTotals => categoryTotalsInCents;

  factory ExpenseMonthSummary.empty(DateTime month) => ExpenseMonthSummary(
        month: month,
        totalIncomeInCents: 0,
        totalExpenseInCents: 0,
        netInCents: 0,
        walletBalancesInCents: const {},
        categoryTotalsInCents: const {},
      );

  @override
  String toString() =>
      'ExpenseMonthSummary(month: $month, income: $totalIncomeInCents, expense: $totalExpenseInCents, net: $netInCents)';
}

/// Filter criteria for querying expense tracker transactions.
class TransactionFilters {
  final DateTime? startDate;
  final DateTime? endDate;
  final List<String>? categoryIds;
  final List<String>? walletIds;
  final String? textQuery;
  final VoucherType? type;

  const TransactionFilters({
    this.startDate,
    this.endDate,
    this.categoryIds,
    this.walletIds,
    this.textQuery,
    this.type,
  });

  static const Object _sentinel = Object();

  TransactionFilters copyWith({
    Object? startDate = _sentinel,
    Object? endDate = _sentinel,
    Object? categoryIds = _sentinel,
    Object? walletIds = _sentinel,
    Object? textQuery = _sentinel,
    Object? type = _sentinel,
    bool clearTextQuery = false,
    bool clearType = false,
  }) {
    return TransactionFilters(
      startDate: identical(startDate, _sentinel)
          ? this.startDate
          : startDate as DateTime?,
      endDate: identical(endDate, _sentinel)
          ? this.endDate
          : endDate as DateTime?,
      categoryIds: identical(categoryIds, _sentinel)
          ? this.categoryIds
          : categoryIds as List<String>?,
      walletIds: identical(walletIds, _sentinel)
          ? this.walletIds
          : walletIds as List<String>?,
      textQuery: clearTextQuery
          ? null
          : (identical(textQuery, _sentinel)
              ? this.textQuery
              : textQuery as String?),
      type: clearType
          ? null
          : (identical(type, _sentinel)
              ? this.type
              : type as VoucherType?),
    );
  }
}

/// Dedicated repository for Expense Tracker mode operations.
/// Operates exclusively on dedicated single-entry Expense tables:
/// `exp_transactions`, `exp_wallets`, and `exp_categories`,
/// with full RBAC, audit logging, outbox synchronization, and reactive update stream.
class DriftExpenseRepository {
  final AppDatabase _db;
  final AuditService _auditService;
  final SyncEngine? _syncEngine;
  final _uuid = const Uuid();

  final StreamController<void> _updateStreamController =
      StreamController<void>.broadcast();

  String _currentCompanyId;
  String _currentUserId;
  Role _currentRole;
  Company? _cachedCompany;
  DateTime? _companyCacheTime;
  bool _isDisposed = false;

  DriftExpenseRepository({
    required AppDatabase db,
    Object? postingEngine,
    Object? voucherRepo,
    AuditService? auditService,
    SyncEngine? syncEngine,
    String currentCompanyId = 'cmp_default',
    String currentUserId = 'usr_default',
    Role currentRole = Role.admin,
    Company? company,
  })  : _db = db,
        _auditService = auditService ?? AuditService(db),
        _syncEngine = syncEngine,
        _currentCompanyId = currentCompanyId,
        _currentUserId = currentUserId,
        _currentRole = currentRole,
        _cachedCompany = company,
        _companyCacheTime = company != null ? DateTime.now() : null;

  AppDatabase get db => _db;
  AuditService get auditService => _auditService;
  SyncEngine? get syncEngine => _syncEngine;
  String get currentCompanyId => _currentCompanyId;
  String get currentUserId => _currentUserId;
  Role get currentRole => _currentRole;

  Stream<void> get repositoryUpdatesStream => _updateStreamController.stream;

  void setContext({
    String? companyId,
    String? userId,
    Role? role,
    Company? company,
  }) {
    if (companyId != null && companyId != _currentCompanyId) {
      _cachedCompany = null;
      _companyCacheTime = null;
      _currentCompanyId = companyId;
    }
    if (userId != null) _currentUserId = userId;
    if (role != null) _currentRole = role;
    if (company != null) {
      _cachedCompany = company;
      _companyCacheTime = DateTime.now();
    }
  }

  void invalidateCompanyCache() {
    _cachedCompany = null;
    _companyCacheTime = null;
  }

  Future<Company> _getActiveCompany([Company? override]) async {
    if (override != null) return override;
    if (_cachedCompany != null &&
        _companyCacheTime != null &&
        DateTime.now().difference(_companyCacheTime!).inSeconds < 10) {
      return _cachedCompany!;
    }
    final row = await (_db.select(_db.companies)
          ..where((t) => t.id.equals(_currentCompanyId)))
        .getSingleOrNull();
    if (row != null) {
      _cachedCompany = Company(
        id: row.id,
        name: row.name,
        legalName: row.legalName,
        gstin: row.gstin,
        stateCode: row.stateCode,
        dealerType: row.dealerType,
        currencyCode: row.currencyCode,
        address: row.address,
        email: row.email,
        phoneNumber: row.phoneNumber,
        logoUrl: row.logoUrl,
        signatureUrl: row.signatureUrl,
        signatoryName: row.signatoryName,
        bankName: row.bankName,
        bankAccountNumber: row.bankAccountNumber,
        bankIfsc: row.bankIfsc,
        upiId: row.upiId,
        isCloudSyncEnabled: row.isCloudSyncEnabled,
        isDropboxSyncEnabled: row.isDropboxSyncEnabled,
        isActive: row.isActive,
        mode: CompanyMode.fromName(row.mode),
        enabledModules: AppModule.parseSet(row.enabledModulesJson),
        createdAt: row.createdAt,
        updatedAt: row.updatedAt,
      );
      _companyCacheTime = DateTime.now();
      return _cachedCompany!;
    }

    // Check profiles table for canonical profile
    final prof = await (_db.select(_db.profiles)
          ..where((t) => t.id.equals(_currentCompanyId)))
        .getSingleOrNull();
    if (prof != null) {
      final comp = Company(
        id: prof.id,
        name: prof.name,
        legalName: prof.name,
        currencyCode: prof.currencyCode,
        mode: prof.profileType == 'expense'
            ? CompanyMode.expenseTracker
            : CompanyMode.ledger,
        isActive: prof.isActive,
        createdAt: prof.createdAt,
        updatedAt: prof.updatedAt,
      );
      _cachedCompany = comp;
      _companyCacheTime = DateTime.now();
      return comp;
    }

    throw Exception('Active profile/company not found: $_currentCompanyId');
  }

  Future<void> _ensureExpenseTrackerMode() async {
    final company = await _getActiveCompany();
    if (company.mode != CompanyMode.expenseTracker) {
      throw ExpenseModeRequiredException(
        'Operation refused: Active profile "${company.name}" is in ${company.mode.name} mode. Expense repository requires expenseTracker mode.',
      );
    }
  }

  void _notifyUpdates() {
    if (!_isDisposed && !_updateStreamController.isClosed) {
      _updateStreamController.add(null);
      _syncEngine?.triggerBackgroundSync(companyId: _currentCompanyId);
    }
  }

  void dispose() {
    _isDisposed = true;
    _updateStreamController.close();
  }

  // ==========================================
  // TRANSACTIONS (EXPENSE, INCOME, TRANSFER)
  // ==========================================

  Future<VoucherModel> addExpense({
    required String categoryAccountId,
    required String walletAccountId,
    required int amountInCents,
    DateTime? date,
    String? narration,
    String? referenceNumber,
    String? receiptPhotoUrl,
    String? customId,
  }) async {
    await _ensureExpenseTrackerMode();
    AccessControlService.verifyPermission(_currentRole, UserAction.createExpense);

    if (amountInCents <= 0) {
      throw ArgumentError('Transaction amount must be greater than zero.');
    }

    final now = DateTime.now();
    final txnDate = date ?? now;
    final txnId = customId ?? 'tx_${_uuid.v4().replaceAll('-', '').substring(0, 16)}';

    return await _db.transaction(() async {
      await _db.into(_db.expenseTransactions).insertOnConflictUpdate(
            ExpenseTransactionsCompanion.insert(
              id: txnId,
              profileId: _currentCompanyId,
              transactionType: 'expense',
              amountInCents: amountInCents,
              walletId: walletAccountId,
              toWalletId: const Value(null),
              categoryId: Value(categoryAccountId),
              transactionDate: txnDate,
              note: Value(narration),
              payeeOrPayer: const Value(null),
              referenceNumber: Value(referenceNumber),
              receiptPhotoUrl: Value(receiptPhotoUrl),
              isCleared: const Value(true),
              createdAt: Value(now),
              updatedAt: Value(now),
              isDeleted: const Value(false),
              syncStatus: const Value(SyncRecordStatus.pending),
            ),
          );

      // Adjust wallet balance (decrease for asset, increase for liability)
      await _adjustWalletBalance(walletAccountId, -amountInCents);

      final model = VoucherModel(
        id: txnId,
        companyId: _currentCompanyId,
        voucherNumber: referenceNumber ?? txnId,
        type: VoucherType.expense,
        date: txnDate,
        status: VoucherStatus.posted,
        totalAmountInCents: amountInCents,
        categoryAccountId: categoryAccountId,
        walletAccountId: walletAccountId,
        narration: narration,
        referenceNumber: referenceNumber,
        receiptPhotoUrl: receiptPhotoUrl,
        createdAt: now,
        updatedAt: now,
      );

      await _auditService.recordLog(
        companyId: _currentCompanyId,
        userId: _currentUserId,
        entityType: 'expense_transaction',
        entityId: txnId,
        action: AuditAction.insert,
        newState: model.toMap(),
      );

      await enqueueMutation(
        db: _db,
        table: 'exp_transactions',
        recordId: txnId,
        type: 'INSERT',
        fullRowMap: {
          'id': txnId,
          'profile_id': _currentCompanyId,
          'transaction_type': 'expense',
          'amount_in_cents': amountInCents,
          'wallet_id': walletAccountId,
          'to_wallet_id': null,
          'category_id': categoryAccountId,
          'transaction_date': encodeTime(txnDate),
          'note': narration,
          'payee_or_payer': null,
          'reference_number': referenceNumber,
          'receipt_photo_url': receiptPhotoUrl,
          'is_cleared': true,
          'created_at': encodeTime(now),
          'updated_at': encodeTime(now),
          'is_deleted': false,
        },
      );

      _notifyUpdates();
      return model;
    });
  }

  Future<VoucherModel> addIncome({
    required String categoryAccountId,
    required String walletAccountId,
    required int amountInCents,
    DateTime? date,
    String? narration,
    String? referenceNumber,
    String? receiptPhotoUrl,
    String? customId,
  }) async {
    await _ensureExpenseTrackerMode();
    AccessControlService.verifyPermission(_currentRole, UserAction.createExpense);

    if (amountInCents <= 0) {
      throw ArgumentError('Transaction amount must be greater than zero.');
    }

    final now = DateTime.now();
    final txnDate = date ?? now;
    final txnId = customId ?? 'tx_${_uuid.v4().replaceAll('-', '').substring(0, 16)}';

    return await _db.transaction(() async {
      await _db.into(_db.expenseTransactions).insertOnConflictUpdate(
            ExpenseTransactionsCompanion.insert(
              id: txnId,
              profileId: _currentCompanyId,
              transactionType: 'income',
              amountInCents: amountInCents,
              walletId: walletAccountId,
              toWalletId: const Value(null),
              categoryId: Value(categoryAccountId),
              transactionDate: txnDate,
              note: Value(narration),
              payeeOrPayer: const Value(null),
              referenceNumber: Value(referenceNumber),
              receiptPhotoUrl: Value(receiptPhotoUrl),
              isCleared: const Value(true),
              createdAt: Value(now),
              updatedAt: Value(now),
              isDeleted: const Value(false),
              syncStatus: const Value(SyncRecordStatus.pending),
            ),
          );

      // Adjust wallet balance (increase for asset, decrease for liability)
      await _adjustWalletBalance(walletAccountId, amountInCents);

      final model = VoucherModel(
        id: txnId,
        companyId: _currentCompanyId,
        voucherNumber: referenceNumber ?? txnId,
        type: VoucherType.income,
        date: txnDate,
        status: VoucherStatus.posted,
        totalAmountInCents: amountInCents,
        categoryAccountId: categoryAccountId,
        walletAccountId: walletAccountId,
        narration: narration,
        referenceNumber: referenceNumber,
        receiptPhotoUrl: receiptPhotoUrl,
        createdAt: now,
        updatedAt: now,
      );

      await _auditService.recordLog(
        companyId: _currentCompanyId,
        userId: _currentUserId,
        entityType: 'expense_transaction',
        entityId: txnId,
        action: AuditAction.insert,
        newState: model.toMap(),
      );

      await enqueueMutation(
        db: _db,
        table: 'exp_transactions',
        recordId: txnId,
        type: 'INSERT',
        fullRowMap: {
          'id': txnId,
          'profile_id': _currentCompanyId,
          'transaction_type': 'income',
          'amount_in_cents': amountInCents,
          'wallet_id': walletAccountId,
          'to_wallet_id': null,
          'category_id': categoryAccountId,
          'transaction_date': encodeTime(txnDate),
          'note': narration,
          'payee_or_payer': null,
          'reference_number': referenceNumber,
          'receipt_photo_url': receiptPhotoUrl,
          'is_cleared': true,
          'created_at': encodeTime(now),
          'updated_at': encodeTime(now),
          'is_deleted': false,
        },
      );

      _notifyUpdates();
      return model;
    });
  }

  Future<VoucherModel> addTransfer({
    required String walletAccountId,
    required String toWalletAccountId,
    required int amountInCents,
    DateTime? date,
    String? narration,
    String? referenceNumber,
    String? receiptPhotoUrl,
    String? customId,
  }) async {
    await _ensureExpenseTrackerMode();
    AccessControlService.verifyPermission(_currentRole, UserAction.createExpense);

    if (amountInCents <= 0) {
      throw ArgumentError('Transaction amount must be greater than zero.');
    }
    if (walletAccountId == toWalletAccountId) {
      throw ArgumentError('Source and destination wallets must be different.');
    }

    final now = DateTime.now();
    final txnDate = date ?? now;
    final txnId = customId ?? 'tx_${_uuid.v4().replaceAll('-', '').substring(0, 16)}';

    return await _db.transaction(() async {
      await _db.into(_db.expenseTransactions).insertOnConflictUpdate(
            ExpenseTransactionsCompanion.insert(
              id: txnId,
              profileId: _currentCompanyId,
              transactionType: 'transfer',
              amountInCents: amountInCents,
              walletId: walletAccountId,
              toWalletId: Value(toWalletAccountId),
              categoryId: const Value(null),
              transactionDate: txnDate,
              note: Value(narration),
              payeeOrPayer: const Value(null),
              referenceNumber: Value(referenceNumber),
              receiptPhotoUrl: Value(receiptPhotoUrl),
              isCleared: const Value(true),
              createdAt: Value(now),
              updatedAt: Value(now),
              isDeleted: const Value(false),
              syncStatus: const Value(SyncRecordStatus.pending),
            ),
          );

      // Decrement source wallet, increment destination wallet
      await _adjustWalletBalance(walletAccountId, -amountInCents);
      await _adjustWalletBalance(toWalletAccountId, amountInCents);

      final model = VoucherModel(
        id: txnId,
        companyId: _currentCompanyId,
        voucherNumber: referenceNumber ?? txnId,
        type: VoucherType.transfer,
        date: txnDate,
        status: VoucherStatus.posted,
        totalAmountInCents: amountInCents,
        walletAccountId: walletAccountId,
        toWalletAccountId: toWalletAccountId,
        narration: narration,
        referenceNumber: referenceNumber,
        receiptPhotoUrl: receiptPhotoUrl,
        createdAt: now,
        updatedAt: now,
      );

      await _auditService.recordLog(
        companyId: _currentCompanyId,
        userId: _currentUserId,
        entityType: 'expense_transaction',
        entityId: txnId,
        action: AuditAction.insert,
        newState: model.toMap(),
      );

      await enqueueMutation(
        db: _db,
        table: 'exp_transactions',
        recordId: txnId,
        type: 'INSERT',
        fullRowMap: {
          'id': txnId,
          'profile_id': _currentCompanyId,
          'transaction_type': 'transfer',
          'amount_in_cents': amountInCents,
          'wallet_id': walletAccountId,
          'to_wallet_id': toWalletAccountId,
          'category_id': null,
          'transaction_date': encodeTime(txnDate),
          'note': narration,
          'payee_or_payer': null,
          'reference_number': referenceNumber,
          'receipt_photo_url': receiptPhotoUrl,
          'is_cleared': true,
          'created_at': encodeTime(now),
          'updated_at': encodeTime(now),
          'is_deleted': false,
        },
      );

      _notifyUpdates();
      return model;
    });
  }

  Future<VoucherModel> updateTransaction(VoucherModel voucher) async {
    await _ensureExpenseTrackerMode();
    AccessControlService.verifyPermission(_currentRole, UserAction.editExpense);

    return await _db.transaction(() async {
      final existing = await (_db.select(_db.expenseTransactions)
            ..where((t) => t.id.equals(voucher.id) & t.profileId.equals(_currentCompanyId)))
          .getSingleOrNull();

      if (existing != null) {
        // Revert old effect
        await _applyTransactionBalanceEffects(
          type: existing.transactionType,
          amountInCents: existing.amountInCents,
          walletId: existing.walletId,
          toWalletId: existing.toWalletId,
          isReversal: true,
        );
      }

      final now = DateTime.now();
      final typeStr = voucher.type.name;

      await (_db.update(_db.expenseTransactions)..where((t) => t.id.equals(voucher.id)))
          .write(
        ExpenseTransactionsCompanion(
          transactionType: Value(typeStr),
          amountInCents: Value(voucher.totalAmountInCents),
          walletId: Value(voucher.walletAccountId ?? (existing?.walletId ?? '')),
          toWalletId: Value(voucher.toWalletAccountId),
          categoryId: Value(voucher.categoryAccountId),
          transactionDate: Value(voucher.date),
          note: Value(voucher.narration),
          referenceNumber: Value(voucher.referenceNumber),
          receiptPhotoUrl: Value(voucher.receiptPhotoUrl),
          updatedAt: Value(now),
          syncStatus: const Value(SyncRecordStatus.pending),
        ),
      );

      // Apply new effect
      final effectiveWalletId = voucher.walletAccountId ?? (existing?.walletId ?? '');
      await _applyTransactionBalanceEffects(
        type: typeStr,
        amountInCents: voucher.totalAmountInCents,
        walletId: effectiveWalletId,
        toWalletId: voucher.toWalletAccountId,
        isReversal: false,
      );

      await enqueueMutation(
        db: _db,
        table: 'exp_transactions',
        recordId: voucher.id,
        type: 'UPDATE',
        fullRowMap: {
          'id': voucher.id,
          'profile_id': _currentCompanyId,
          'transaction_type': typeStr,
          'amount_in_cents': voucher.totalAmountInCents,
          'wallet_id': effectiveWalletId,
          'to_wallet_id': voucher.toWalletAccountId,
          'category_id': voucher.categoryAccountId,
          'transaction_date': encodeTime(voucher.date),
          'note': voucher.narration,
          'reference_number': voucher.referenceNumber,
          'receipt_photo_url': voucher.receiptPhotoUrl,
          'updated_at': encodeTime(now),
          'is_deleted': false,
        },
      );

      _notifyUpdates();
      return voucher.copyWith(updatedAt: now);
    });
  }

  Future<void> voidTransaction(String voucherId) async {
    await _ensureExpenseTrackerMode();
    AccessControlService.verifyPermission(_currentRole, UserAction.voidExpense);

    await _db.transaction(() async {
      final existing = await (_db.select(_db.expenseTransactions)
            ..where((t) => t.id.equals(voucherId) & t.profileId.equals(_currentCompanyId)))
          .getSingleOrNull();

      if (existing == null) return;

      // Revert balance effect
      await _applyTransactionBalanceEffects(
        type: existing.transactionType,
        amountInCents: existing.amountInCents,
        walletId: existing.walletId,
        toWalletId: existing.toWalletId,
        isReversal: true,
      );

      final now = DateTime.now();
      await (_db.update(_db.expenseTransactions)..where((t) => t.id.equals(voucherId)))
          .write(
        ExpenseTransactionsCompanion(
          isDeleted: const Value(true),
          updatedAt: Value(now),
          syncStatus: const Value(SyncRecordStatus.pending),
        ),
      );

      await enqueueMutation(
        db: _db,
        table: 'exp_transactions',
        recordId: voucherId,
        type: 'DELETE',
        fullRowMap: {
          'id': voucherId,
          'profile_id': _currentCompanyId,
          'is_deleted': true,
          'updated_at': encodeTime(now),
        },
      );

      _notifyUpdates();
    });
  }

  Future<void> deleteTransaction(String id) => voidTransaction(id);

  Future<void> restoreTransaction(String voucherId) async {
    await _ensureExpenseTrackerMode();
    AccessControlService.verifyPermission(_currentRole, UserAction.createExpense);

    await _db.transaction(() async {
      final existing = await (_db.select(_db.expenseTransactions)
            ..where((t) => t.id.equals(voucherId) & t.profileId.equals(_currentCompanyId)))
          .getSingleOrNull();

      if (existing == null) return;

      // Re-apply balance effect
      await _applyTransactionBalanceEffects(
        type: existing.transactionType,
        amountInCents: existing.amountInCents,
        walletId: existing.walletId,
        toWalletId: existing.toWalletId,
        isReversal: false,
      );

      final now = DateTime.now();
      await (_db.update(_db.expenseTransactions)..where((t) => t.id.equals(voucherId)))
          .write(
        ExpenseTransactionsCompanion(
          isDeleted: const Value(false),
          updatedAt: Value(now),
          syncStatus: const Value(SyncRecordStatus.pending),
        ),
      );

      await enqueueMutation(
        db: _db,
        table: 'exp_transactions',
        recordId: voucherId,
        type: 'UPDATE',
        fullRowMap: {
          'id': voucherId,
          'profile_id': _currentCompanyId,
          'is_deleted': false,
          'updated_at': encodeTime(now),
        },
      );

      _notifyUpdates();
    });
  }

  Future<List<VoucherModel>> getTransactions({
    DateTime? startDate,
    DateTime? endDate,
    List<String>? categoryIds,
    List<String>? walletIds,
    String? textQuery,
    VoucherType? type,
    bool includeVoided = false,
  }) async {
    await _ensureExpenseTrackerMode();
    AccessControlService.verifyPermission(_currentRole, UserAction.viewExpenses);

    final query = _db.select(_db.expenseTransactions)
      ..where((t) => t.profileId.equals(_currentCompanyId))
      ..orderBy([(t) => OrderingTerm.desc(t.transactionDate), (t) => OrderingTerm.desc(t.createdAt)]);

    if (!includeVoided) {
      query.where((t) => t.isDeleted.equals(false));
    }

    if (type != null) {
      query.where((t) => t.transactionType.equals(type.name));
    }

    if (startDate != null) {
      query.where((t) => t.transactionDate.isBiggerOrEqualValue(startDate));
    }
    if (endDate != null) {
      query.where((t) => t.transactionDate.isSmallerOrEqualValue(endDate));
    }

    if (categoryIds != null && categoryIds.isNotEmpty) {
      query.where((t) => t.categoryId.isIn(categoryIds));
    }

    if (walletIds != null && walletIds.isNotEmpty) {
      query.where((t) =>
          t.walletId.isIn(walletIds) |
          t.toWalletId.isIn(walletIds));
    }

    final rows = await query.get();
    var result = rows.map(_rowToVoucher).toList();

    if (textQuery != null && textQuery.trim().isNotEmpty) {
      final q = textQuery.trim().toLowerCase();
      result = result.where((v) {
        final narr = v.narration?.toLowerCase() ?? '';
        final vNum = v.voucherNumber.toLowerCase();
        final refNum = v.referenceNumber?.toLowerCase() ?? '';
        return narr.contains(q) || vNum.contains(q) || refNum.contains(q);
      }).toList();
    }

    return result;
  }

  Stream<List<VoucherModel>> watchTransactions({
    DateTime? startDate,
    DateTime? endDate,
    List<String>? categoryIds,
    List<String>? walletIds,
    String? textQuery,
    VoucherType? type,
    bool includeVoided = false,
  }) {
    AccessControlService.verifyPermission(_currentRole, UserAction.viewExpenses);

    final query = _db.select(_db.expenseTransactions)
      ..where((t) => t.profileId.equals(_currentCompanyId))
      ..orderBy([(t) => OrderingTerm.desc(t.transactionDate), (t) => OrderingTerm.desc(t.createdAt)]);

    if (!includeVoided) {
      query.where((t) => t.isDeleted.equals(false));
    }

    if (type != null) {
      query.where((t) => t.transactionType.equals(type.name));
    }

    if (startDate != null) {
      query.where((t) => t.transactionDate.isBiggerOrEqualValue(startDate));
    }
    if (endDate != null) {
      query.where((t) => t.transactionDate.isSmallerOrEqualValue(endDate));
    }

    if (categoryIds != null && categoryIds.isNotEmpty) {
      query.where((t) => t.categoryId.isIn(categoryIds));
    }

    if (walletIds != null && walletIds.isNotEmpty) {
      query.where((t) =>
          t.walletId.isIn(walletIds) |
          t.toWalletId.isIn(walletIds));
    }

    return query.watch().map((rows) {
      var result = rows.map(_rowToVoucher).toList();
      if (textQuery != null && textQuery.trim().isNotEmpty) {
        final q = textQuery.trim().toLowerCase();
        result = result.where((v) {
          final narr = v.narration?.toLowerCase() ?? '';
          final vNum = v.voucherNumber.toLowerCase();
          final refNum = v.referenceNumber?.toLowerCase() ?? '';
          return narr.contains(q) || vNum.contains(q) || refNum.contains(q);
        }).toList();
      }
      return result;
    });
  }

  // --- Balance Calculation Helpers ---

  Future<void> _applyTransactionBalanceEffects({
    required String type,
    required int amountInCents,
    required String walletId,
    String? toWalletId,
    required bool isReversal,
  }) async {
    final factor = isReversal ? -1 : 1;

    switch (type) {
      case 'expense':
        await _adjustWalletBalance(walletId, -1 * amountInCents * factor);
        break;
      case 'income':
        await _adjustWalletBalance(walletId, amountInCents * factor);
        break;
      case 'transfer':
        await _adjustWalletBalance(walletId, -1 * amountInCents * factor);
        if (toWalletId != null && toWalletId.isNotEmpty) {
          await _adjustWalletBalance(toWalletId, amountInCents * factor);
        }
        break;
    }
  }

  Future<void> _adjustWalletBalance(String walletId, int deltaInCents) async {
    final wallet = await (_db.select(_db.expenseWallets)
          ..where((t) => t.id.equals(walletId) & t.profileId.equals(_currentCompanyId)))
        .getSingleOrNull();

    if (wallet == null) return;

    final isLiability = wallet.walletType == 'credit_card';
    final effectiveDelta = isLiability ? -deltaInCents : deltaInCents;
    final newBalance = wallet.currentBalanceInCents + effectiveDelta;

    await (_db.update(_db.expenseWallets)..where((t) => t.id.equals(walletId)))
        .write(
      ExpenseWalletsCompanion(
        currentBalanceInCents: Value(newBalance),
        updatedAt: Value(DateTime.now()),
        syncStatus: const Value(SyncRecordStatus.pending),
      ),
    );

    await enqueueMutation(
      db: _db,
      table: 'exp_wallets',
      recordId: walletId,
      type: 'UPDATE',
      fullRowMap: {
        'id': walletId,
        'profile_id': _currentCompanyId,
        'name': wallet.name,
        'wallet_type': wallet.walletType,
        'currency_code': wallet.currencyCode,
        'starting_balance_in_cents': wallet.startingBalanceInCents,
        'current_balance_in_cents': newBalance,
        'color_hex': wallet.colorHex,
        'icon_name': wallet.iconName,
        'is_archived': wallet.isArchived,
        'updated_at': encodeTime(DateTime.now()),
        'is_deleted': wallet.isDeleted,
      },
    );
  }

  // ==========================================
  // WALLET CRUD & OPENING BALANCE
  // ==========================================

  Future<List<AccountModel>> getWallets({bool includeArchived = false}) async {
    await _ensureExpenseTrackerMode();
    AccessControlService.verifyPermission(_currentRole, UserAction.viewExpenses);

    final query = _db.select(_db.expenseWallets)
      ..where((t) => t.profileId.equals(_currentCompanyId) & t.isDeleted.equals(false))
      ..orderBy([
        (t) => OrderingTerm(expression: t.walletType.equals('cash'), mode: OrderingMode.desc),
        (t) => OrderingTerm.asc(t.createdAt),
        (t) => OrderingTerm.asc(t.name),
      ]);

    if (!includeArchived) {
      query.where((t) => t.isArchived.equals(false));
    }

    final rows = await query.get();
    return rows.map(_walletToAccount).toList();
  }

  Future<AccountModel> getWalletById(String id) async {
    await _ensureExpenseTrackerMode();
    AccessControlService.verifyPermission(_currentRole, UserAction.viewExpenses);

    final row = await (_db.select(_db.expenseWallets)
          ..where((t) =>
              t.id.equals(id) &
              t.profileId.equals(_currentCompanyId) &
              t.isDeleted.equals(false)))
        .getSingleOrNull();

    if (row == null) {
      throw AccountNotFoundException(id, 'Wallet account not found: $id');
    }
    return _walletToAccount(row);
  }

  Future<AccountModel> createWallet({
    required String name,
    required AccountType type,
    int openingBalanceInCents = 0,
    String? description,
    String? code,
    String? walletType,
    String? colorHex,
    String? iconName,
  }) async {
    await _ensureExpenseTrackerMode();
    AccessControlService.verifyPermission(
        _currentRole, UserAction.manageWalletsAndCategories);

    if (type != AccountType.asset && type != AccountType.liability) {
      throw ArgumentError('Wallet must be of type asset or liability.');
    }

    final now = DateTime.now();
    final walletId = '${_currentCompanyId}_wal_${_uuid.v4().substring(0, 8)}';
    final resolvedWalletType = walletType ?? (type == AccountType.liability ? 'credit_card' : 'cash');

    final companion = ExpenseWalletsCompanion.insert(
      id: walletId,
      profileId: _currentCompanyId,
      name: name,
      walletType: Value(resolvedWalletType),
      currencyCode: const Value('INR'),
      startingBalanceInCents: Value(openingBalanceInCents),
      currentBalanceInCents: Value(openingBalanceInCents),
      colorHex: Value(colorHex),
      iconName: Value(iconName),
      isArchived: const Value(false),
      createdAt: Value(now),
      updatedAt: Value(now),
      isDeleted: const Value(false),
      syncStatus: const Value(SyncRecordStatus.pending),
    );

    await _db.into(_db.expenseWallets).insert(companion);

    final created = await getWalletById(walletId);

    await _auditService.recordLog(
      companyId: _currentCompanyId,
      userId: _currentUserId,
      entityType: 'wallet',
      entityId: walletId,
      action: AuditAction.insert,
      newState: created.toMap(),
    );

    await enqueueMutation(
      db: _db,
      table: 'exp_wallets',
      recordId: walletId,
      type: 'INSERT',
      fullRowMap: {
        'id': walletId,
        'profile_id': _currentCompanyId,
        'name': name,
        'wallet_type': resolvedWalletType,
        'currency_code': 'INR',
        'starting_balance_in_cents': openingBalanceInCents,
        'current_balance_in_cents': openingBalanceInCents,
        'color_hex': colorHex,
        'icon_name': iconName,
        'is_archived': false,
        'created_at': encodeTime(now),
        'updated_at': encodeTime(now),
        'is_deleted': false,
      },
    );

    _notifyUpdates();
    return created;
  }

  Future<AccountModel> updateWallet({
    required String id,
    String? name,
    String? description,
    bool? isActive,
    String? colorHex,
    String? iconName,
  }) async {
    await _ensureExpenseTrackerMode();
    AccessControlService.verifyPermission(
        _currentRole, UserAction.manageWalletsAndCategories);

    final existing = await getWalletById(id);
    final now = DateTime.now();

    await (_db.update(_db.expenseWallets)..where((t) => t.id.equals(id))).write(
      ExpenseWalletsCompanion(
        name: name != null ? Value(name) : const Value.absent(),
        colorHex: colorHex != null ? Value(colorHex) : const Value.absent(),
        iconName: iconName != null ? Value(iconName) : const Value.absent(),
        isArchived: isActive != null ? Value(!isActive) : const Value.absent(),
        updatedAt: Value(now),
        syncStatus: const Value(SyncRecordStatus.pending),
      ),
    );

    final updated = await getWalletById(id);

    await _auditService.recordLog(
      companyId: _currentCompanyId,
      userId: _currentUserId,
      entityType: 'wallet',
      entityId: id,
      action: AuditAction.update,
      oldState: existing.toMap(),
      newState: updated.toMap(),
    );

    await enqueueMutation(
      db: _db,
      table: 'exp_wallets',
      recordId: id,
      type: 'UPDATE',
      fullRowMap: {
        'id': id,
        'profile_id': _currentCompanyId,
        'name': updated.name,
        'is_archived': !updated.isActive,
        'updated_at': encodeTime(now),
      },
    );

    _notifyUpdates();
    return updated;
  }

  Future<bool> deleteWallet(String id) async {
    await _ensureExpenseTrackerMode();
    AccessControlService.verifyPermission(
        _currentRole, UserAction.manageWalletsAndCategories);

    final existing = await getWalletById(id);

    // Check if wallet has transactions
    final hasTxns = await (_db.select(_db.expenseTransactions)
          ..where((t) =>
              t.profileId.equals(_currentCompanyId) &
              (t.walletId.equals(id) | t.toWalletId.equals(id)) &
              t.isDeleted.equals(false)))
        .get();

    final now = DateTime.now();

    if (hasTxns.isNotEmpty) {
      // Archive instead of delete
      await (_db.update(_db.expenseWallets)..where((t) => t.id.equals(id))).write(
        ExpenseWalletsCompanion(
          isArchived: const Value(true),
          updatedAt: Value(now),
          syncStatus: const Value(SyncRecordStatus.pending),
        ),
      );

      await enqueueMutation(
        db: _db,
        table: 'exp_wallets',
        recordId: id,
        type: 'UPDATE',
        fullRowMap: {
          'id': id,
          'profile_id': _currentCompanyId,
          'is_archived': true,
          'updated_at': encodeTime(now),
        },
      );

      _notifyUpdates();
      return false; // Archived, not deleted
    }

    // Soft delete
    await (_db.update(_db.expenseWallets)..where((t) => t.id.equals(id))).write(
      ExpenseWalletsCompanion(
        isDeleted: const Value(true),
        updatedAt: Value(now),
        syncStatus: const Value(SyncRecordStatus.pending),
      ),
    );

    await _auditService.recordLog(
      companyId: _currentCompanyId,
      userId: _currentUserId,
      entityType: 'wallet',
      entityId: id,
      action: AuditAction.delete,
      oldState: existing.toMap(),
    );

    await enqueueMutation(
      db: _db,
      table: 'exp_wallets',
      recordId: id,
      type: 'DELETE',
      fullRowMap: {
        'id': id,
        'profile_id': _currentCompanyId,
        'is_deleted': true,
        'updated_at': encodeTime(now),
      },
    );

    _notifyUpdates();
    return true;
  }

  Future<void> setOpeningBalance(String walletId, int openingBalanceInCents) async {
    await _ensureExpenseTrackerMode();
    AccessControlService.verifyPermission(
        _currentRole, UserAction.manageWalletsAndCategories);

    final wallet = await (_db.select(_db.expenseWallets)
          ..where((t) => t.id.equals(walletId) & t.profileId.equals(_currentCompanyId)))
        .getSingleOrNull();

    if (wallet == null) {
      throw AccountNotFoundException(walletId, 'Wallet not found: $walletId');
    }

    final now = DateTime.now();

    await (_db.update(_db.expenseWallets)..where((t) => t.id.equals(walletId))).write(
      ExpenseWalletsCompanion(
        startingBalanceInCents: Value(openingBalanceInCents),
        updatedAt: Value(now),
        syncStatus: const Value(SyncRecordStatus.pending),
      ),
    );

    await recalculateWalletBalances(walletId);

    await enqueueMutation(
      db: _db,
      table: 'exp_wallets',
      recordId: walletId,
      type: 'UPDATE',
      fullRowMap: {
        'id': walletId,
        'profile_id': _currentCompanyId,
        'starting_balance_in_cents': openingBalanceInCents,
        'updated_at': encodeTime(now),
      },
    );

    _notifyUpdates();
  }

  Future<void> recalculateWalletBalances([String? targetWalletId]) async {
    final wallets = await (_db.select(_db.expenseWallets)
          ..where((t) => t.profileId.equals(_currentCompanyId) & t.isDeleted.equals(false)))
        .get();

    for (final w in wallets) {
      if (targetWalletId != null && w.id != targetWalletId) continue;

      int balance = w.startingBalanceInCents;
      final isLiability = w.walletType == 'credit_card';

      final txns = await (_db.select(_db.expenseTransactions)
            ..where((t) =>
                t.profileId.equals(_currentCompanyId) &
                t.isDeleted.equals(false) &
                (t.walletId.equals(w.id) | t.toWalletId.equals(w.id))))
          .get();

      for (final tx in txns) {
        if (tx.transactionType == 'expense' && tx.walletId == w.id) {
          balance += isLiability ? tx.amountInCents : -tx.amountInCents;
        } else if (tx.transactionType == 'income' && tx.walletId == w.id) {
          balance += isLiability ? -tx.amountInCents : tx.amountInCents;
        } else if (tx.transactionType == 'transfer') {
          if (tx.walletId == w.id) {
            balance += isLiability ? tx.amountInCents : -tx.amountInCents;
          }
          if (tx.toWalletId == w.id) {
            balance += isLiability ? -tx.amountInCents : tx.amountInCents;
          }
        }
      }

      await (_db.update(_db.expenseWallets)..where((t) => t.id.equals(w.id))).write(
        ExpenseWalletsCompanion(
          currentBalanceInCents: Value(balance),
          updatedAt: Value(DateTime.now()),
          syncStatus: const Value(SyncRecordStatus.pending),
        ),
      );
    }
  }

  // ==========================================
  // CATEGORIES CRUD
  // ==========================================

  Future<List<AccountModel>> getCategories({
    ExpenseCategoryType? type,
    bool includeArchived = false,
  }) async {
    await _ensureExpenseTrackerMode();
    AccessControlService.verifyPermission(_currentRole, UserAction.viewExpenses);

    final query = _db.select(_db.expenseCategories)
      ..where((t) => t.profileId.equals(_currentCompanyId) & t.isDeleted.equals(false))
      ..orderBy([(t) => OrderingTerm.asc(t.name)]);

    if (type != null) {
      query.where((t) => t.categoryType.equals(type.name));
    }

    final rows = await query.get();
    final accounts = await (_db.select(_db.accounts)
          ..where((t) => t.companyId.equals(_currentCompanyId)))
        .get();
    final accountMap = {for (final a in accounts) a.id: a};

    final result = <AccountModel>[];
    for (final row in rows) {
      final acc = accountMap[row.id];
      final model = _categoryToAccount(row, acc);
      if (!includeArchived && !model.isActive) {
        continue;
      }
      result.add(model);
    }
    return result;
  }

  Future<AccountModel> getCategoryById(String id) async {
    await _ensureExpenseTrackerMode();
    AccessControlService.verifyPermission(_currentRole, UserAction.viewExpenses);

    final row = await (_db.select(_db.expenseCategories)
          ..where((t) =>
              t.id.equals(id) &
              t.profileId.equals(_currentCompanyId) &
              t.isDeleted.equals(false)))
        .getSingleOrNull();

    if (row == null) {
      throw AccountNotFoundException(id, 'Category account not found: $id');
    }
    final acc = await (_db.select(_db.accounts)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    return _categoryToAccount(row, acc);
  }

  Future<AccountModel> createCategory({
    required String name,
    required dynamic type, // AccountType or ExpenseCategoryType
    String? parentAccountId,
    String? description,
    String? code,
    String? colorHex,
    String? iconName,
  }) async {
    await _ensureExpenseTrackerMode();
    AccessControlService.verifyPermission(
        _currentRole, UserAction.manageWalletsAndCategories);

    final String typeStr;
    if (type is AccountType) {
      typeStr = type == AccountType.income ? 'income' : 'expense';
    } else if (type is ExpenseCategoryType) {
      typeStr = type.name;
    } else {
      typeStr = type.toString().toLowerCase().contains('income') ? 'income' : 'expense';
    }

    // If parent category provided, validate matching type
    if (parentAccountId != null && parentAccountId.isNotEmpty) {
      final parent = await (_db.select(_db.expenseCategories)
            ..where((t) =>
                t.id.equals(parentAccountId) &
                t.profileId.equals(_currentCompanyId) &
                t.isDeleted.equals(false)))
          .getSingleOrNull();

      if (parent != null && parent.categoryType != typeStr) {
        throw ArgumentError('Sub-category type ($typeStr) must match parent category type (${parent.categoryType}).');
      }
    }

    final now = DateTime.now();
    final catId = '${_currentCompanyId}_cat_${_uuid.v4().substring(0, 8)}';

    final companion = ExpenseCategoriesCompanion.insert(
      id: catId,
      profileId: _currentCompanyId,
      name: name,
      categoryType: Value(typeStr),
      parentCategoryId: Value(parentAccountId),
      iconName: Value(iconName),
      colorHex: Value(colorHex),
      isSystem: const Value(false),
      createdAt: Value(now),
      updatedAt: Value(now),
      isDeleted: const Value(false),
      syncStatus: const Value(SyncRecordStatus.pending),
    );

    await _db.into(_db.expenseCategories).insert(companion);

    // Keep legacy accounts table synchronized for backwards compatibility
    await _db.into(_db.accounts).insertOnConflictUpdate(
          AccountsCompanion.insert(
            id: catId,
            companyId: Value(_currentCompanyId),
            code: catId,
            name: name,
            type: typeStr,
            kind: const Value('category'),
            parentAccountId: Value(parentAccountId),
            isSystem: const Value(false),
            isActive: const Value(true),
            createdAt: Value(now),
            updatedAt: Value(now),
            isDeleted: const Value(false),
            syncStatus: const Value(SyncRecordStatus.synced),
          ),
        );

    final created = await getCategoryById(catId);

    await _auditService.recordLog(
      companyId: _currentCompanyId,
      userId: _currentUserId,
      entityType: 'category',
      entityId: catId,
      action: AuditAction.insert,
      newState: created.toMap(),
    );

    await enqueueMutation(
      db: _db,
      table: 'exp_categories',
      recordId: catId,
      type: 'INSERT',
      fullRowMap: {
        'id': catId,
        'profile_id': _currentCompanyId,
        'name': name,
        'category_type': typeStr,
        'parent_category_id': parentAccountId,
        'icon_name': iconName,
        'color_hex': colorHex,
        'is_system': false,
        'created_at': encodeTime(now),
        'updated_at': encodeTime(now),
        'is_deleted': false,
      },
    );

    _notifyUpdates();
    return created;
  }

  Future<AccountModel> updateCategory({
    required String id,
    String? name,
    String? parentAccountId,
    String? description,
    bool? isActive,
    String? colorHex,
    String? iconName,
  }) async {
    await _ensureExpenseTrackerMode();
    AccessControlService.verifyPermission(
        _currentRole, UserAction.manageWalletsAndCategories);

    final existing = await getCategoryById(id);
    final now = DateTime.now();

    await (_db.update(_db.expenseCategories)..where((t) => t.id.equals(id))).write(
      ExpenseCategoriesCompanion(
        name: name != null ? Value(name) : const Value.absent(),
        parentCategoryId: parentAccountId != null ? Value(parentAccountId) : const Value.absent(),
        colorHex: colorHex != null ? Value(colorHex) : const Value.absent(),
        iconName: iconName != null ? Value(iconName) : const Value.absent(),
        updatedAt: Value(now),
        syncStatus: const Value(SyncRecordStatus.pending),
      ),
    );

    final updated = await getCategoryById(id);

    await _auditService.recordLog(
      companyId: _currentCompanyId,
      userId: _currentUserId,
      entityType: 'category',
      entityId: id,
      action: AuditAction.update,
      oldState: existing.toMap(),
      newState: updated.toMap(),
    );

    await enqueueMutation(
      db: _db,
      table: 'exp_categories',
      recordId: id,
      type: 'UPDATE',
      fullRowMap: {
        'id': id,
        'profile_id': _currentCompanyId,
        'name': updated.name,
        'parent_category_id': updated.parentAccountId,
        'updated_at': encodeTime(now),
      },
    );

    _notifyUpdates();
    return updated;
  }

  Future<bool> deleteCategory(String id) async {
    await _ensureExpenseTrackerMode();
    AccessControlService.verifyPermission(
        _currentRole, UserAction.manageWalletsAndCategories);

    final existing = await getCategoryById(id);

    // Check if category has transactions
    final hasTxns = await (_db.select(_db.expenseTransactions)
          ..where((t) =>
              t.profileId.equals(_currentCompanyId) &
              t.categoryId.equals(id) &
              t.isDeleted.equals(false)))
        .get();

    final now = DateTime.now();

    if (hasTxns.isNotEmpty) {
      // In use: archive by keeping it in expenseCategories, mark inactive in accounts
      await (_db.update(_db.accounts)..where((t) => t.id.equals(id))).write(
        AccountsCompanion(
          isActive: const Value(false),
          updatedAt: Value(now),
        ),
      );
      _notifyUpdates();
      return false; // Archived / in-use, not deleted
    }

    // Soft delete
    await (_db.update(_db.expenseCategories)..where((t) => t.id.equals(id))).write(
      ExpenseCategoriesCompanion(
        isDeleted: const Value(true),
        updatedAt: Value(now),
        syncStatus: const Value(SyncRecordStatus.pending),
      ),
    );
    await (_db.update(_db.accounts)..where((t) => t.id.equals(id))).write(
      AccountsCompanion(
        isDeleted: const Value(true),
        updatedAt: Value(now),
      ),
    );

    await _auditService.recordLog(
      companyId: _currentCompanyId,
      userId: _currentUserId,
      entityType: 'category',
      entityId: id,
      action: AuditAction.delete,
      oldState: existing.toMap(),
    );

    await enqueueMutation(
      db: _db,
      table: 'exp_categories',
      recordId: id,
      type: 'DELETE',
      fullRowMap: {
        'id': id,
        'profile_id': _currentCompanyId,
        'is_deleted': true,
        'updated_at': encodeTime(now),
      },
    );

    _notifyUpdates();
    return true;
  }

  // ==========================================
  // MONTH SUMMARY
  // ==========================================

  Future<ExpenseMonthSummary> getMonthSummary(DateTime month) async {
    await _ensureExpenseTrackerMode();
    AccessControlService.verifyPermission(_currentRole, UserAction.viewExpenses);

    final start = DateTime(month.year, month.month, 1);
    final end = DateTime(month.year, month.month + 1, 0, 23, 59, 59, 999);

    final txns = await (_db.select(_db.expenseTransactions)
          ..where((t) =>
              t.profileId.equals(_currentCompanyId) &
              t.isDeleted.equals(false) &
              t.transactionDate.isBiggerOrEqualValue(start) &
              t.transactionDate.isSmallerOrEqualValue(end)))
        .get();

    int totalIncome = 0;
    int totalExpense = 0;
    final categoryTotals = <String, int>{};
    final incomeCatTotals = <String, int>{};
    final expenseCatTotals = <String, int>{};

    for (final tx in txns) {
      if (tx.transactionType == 'expense') {
        totalExpense += tx.amountInCents;
        if (tx.categoryId != null) {
          categoryTotals[tx.categoryId!] =
              (categoryTotals[tx.categoryId!] ?? 0) + tx.amountInCents;
          expenseCatTotals[tx.categoryId!] =
              (expenseCatTotals[tx.categoryId!] ?? 0) + tx.amountInCents;
        }
      } else if (tx.transactionType == 'income') {
        totalIncome += tx.amountInCents;
        if (tx.categoryId != null) {
          categoryTotals[tx.categoryId!] =
              (categoryTotals[tx.categoryId!] ?? 0) + tx.amountInCents;
          incomeCatTotals[tx.categoryId!] =
              (incomeCatTotals[tx.categoryId!] ?? 0) + tx.amountInCents;
        }
      }
    }

    final walletBalances = <String, int>{};
    final wallets = await (_db.select(_db.expenseWallets)
          ..where((t) => t.profileId.equals(_currentCompanyId) & t.isDeleted.equals(false)))
        .get();
    for (final w in wallets) {
      walletBalances[w.id] = w.currentBalanceInCents;
    }

    return ExpenseMonthSummary(
      month: month,
      totalIncomeInCents: totalIncome,
      totalExpenseInCents: totalExpense,
      netInCents: totalIncome - totalExpense,
      walletBalancesInCents: walletBalances,
      categoryTotalsInCents: categoryTotals,
      incomeCategoryTotalsInCents: incomeCatTotals,
      expenseCategoryTotalsInCents: expenseCatTotals,
    );
  }

  // ==========================================
  // MODEL MAPPING HELPERS
  // ==========================================

  VoucherModel _rowToVoucher(ExpenseTransactionTableData r) {
    VoucherType type;
    switch (r.transactionType) {
      case 'income':
        type = VoucherType.income;
        break;
      case 'transfer':
        type = VoucherType.transfer;
        break;
      case 'expense':
      default:
        type = VoucherType.expense;
        break;
    }

    return VoucherModel(
      id: r.id,
      companyId: r.profileId,
      voucherNumber: r.referenceNumber ?? r.id,
      type: type,
      date: r.transactionDate,
      status: r.isDeleted ? VoucherStatus.voided : VoucherStatus.posted,
      totalAmountInCents: r.amountInCents,
      subtotalInCents: r.amountInCents,
      categoryAccountId: r.categoryId,
      walletAccountId: r.walletId,
      toWalletAccountId: r.toWalletId,
      narration: r.note,
      referenceNumber: r.referenceNumber,
      receiptPhotoUrl: r.receiptPhotoUrl,
      createdAt: r.createdAt,
      updatedAt: r.updatedAt,
    );
  }

  AccountModel _walletToAccount(ExpenseWalletTableData w) {
    return AccountModel(
      id: w.id,
      companyId: w.profileId,
      code: w.id,
      name: w.name,
      type: w.walletType == 'credit_card' ? AccountType.liability : AccountType.asset,
      kind: 'wallet',
      isSystem: false,
      isActive: !w.isArchived && !w.isDeleted,
      description: 'Wallet: ${w.name}',
      currentBalanceInCents: w.currentBalanceInCents,
      createdAt: w.createdAt,
      updatedAt: w.updatedAt,
    );
  }

  AccountModel _categoryToAccount(ExpenseCategoryTableData c, [AccountTableData? acc]) {
    final isActive = acc?.isActive ?? true;
    return AccountModel(
      id: c.id,
      companyId: c.profileId,
      code: c.id,
      name: c.name,
      type: c.categoryType == 'income' ? AccountType.income : AccountType.expense,
      kind: 'category',
      isSystem: c.isSystem,
      isActive: isActive && !c.isDeleted,
      parentAccountId: c.parentCategoryId,
      description: 'Category: ${c.name}',
      currentBalanceInCents: 0,
      createdAt: c.createdAt,
      updatedAt: c.updatedAt,
    );
  }
}
