import 'dart:async';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../core/network/sync_engine.dart';
import '../../domain/exceptions/ledger_exceptions.dart';
import '../accounting/voucher_posting_engine.dart';
import '../local/audit_service.dart';
import '../local/database.dart';
import '../local/drift_voucher_repository.dart';
import '../local/outbox_helper.dart';
import '../models/account_model.dart';
import '../models/audit_log_model.dart';
import '../models/company_model.dart';
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
/// Operates on top of Drift database, VoucherPostingEngine, DriftVoucherRepository,
/// with full RBAC, audit logging, outbox synchronization, and reactive update stream.
class DriftExpenseRepository {
  final AppDatabase _db;
  final VoucherPostingEngine _postingEngine;
  final DriftVoucherRepository _voucherRepo;
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
    VoucherPostingEngine? postingEngine,
    DriftVoucherRepository? voucherRepo,
    AuditService? auditService,
    SyncEngine? syncEngine,
    String currentCompanyId = 'cmp_default',
    String currentUserId = 'usr_default',
    Role currentRole = Role.admin,
    Company? company,
  })  : _db = db,
        _auditService = auditService ?? AuditService(db),
        _postingEngine = postingEngine ??
            VoucherPostingEngine(db, auditService ?? AuditService(db)),
        _voucherRepo = voucherRepo ??
            DriftVoucherRepository(
              db: db,
              auditService: auditService ?? AuditService(db),
              postingEngine: postingEngine ??
                  VoucherPostingEngine(db, auditService ?? AuditService(db)),
              currentCompanyId: currentCompanyId,
              currentUserId: currentUserId,
              currentRole: currentRole,
            ),
        _syncEngine = syncEngine,
        _currentCompanyId = currentCompanyId,
        _currentUserId = currentUserId,
        _currentRole = currentRole,
        _cachedCompany = company,
        _companyCacheTime = company != null ? DateTime.now() : null;

  AppDatabase get db => _db;
  VoucherPostingEngine get postingEngine => _postingEngine;
  DriftVoucherRepository get voucherRepo => _voucherRepo;
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
    }
    if (companyId != null) _currentCompanyId = companyId;
    if (userId != null) _currentUserId = userId;
    if (role != null) _currentRole = role;
    if (company != null) {
      _cachedCompany = company;
      _companyCacheTime = DateTime.now();
    }
    _voucherRepo.setContext(
      companyId: _currentCompanyId,
      userId: _currentUserId,
      role: _currentRole,
    );
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
    throw Exception('Active company not found: $_currentCompanyId');
  }

  Future<void> _ensureExpenseTrackerMode() async {
    final company = await _getActiveCompany();
    if (company.mode != CompanyMode.expenseTracker) {
      throw ExpenseModeRequiredException(
        'Operation refused: Active company "${company.name}" is in ${company.mode.name} mode. Expense repository requires expenseTracker mode.',
      );
    }
  }

  void _notifyUpdates() {
    if (!_isDisposed && !_updateStreamController.isClosed) {
      _updateStreamController.add(null);
    }
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

    final now = DateTime.now();
    final txnDate = date ?? now;
    final voucherNumber =
        await _voucherRepo.generateNextVoucherNumber(VoucherType.expense);

    final voucher = VoucherModel(
      id: customId ?? 'exp_${_uuid.v4().substring(0, 12)}',
      companyId: _currentCompanyId,
      voucherNumber: voucherNumber,
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

    final posted = await _postingEngine.postVoucher(
      voucher: voucher,
      userId: _currentUserId,
    );

    await _auditService.recordLog(
      companyId: _currentCompanyId,
      userId: _currentUserId,
      entityType: 'expense',
      entityId: posted.id,
      action: AuditAction.insert,
      newState: posted.toMap(),
    );

    _notifyUpdates();
    return posted;
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

    final now = DateTime.now();
    final txnDate = date ?? now;
    final voucherNumber =
        await _voucherRepo.generateNextVoucherNumber(VoucherType.income);

    final voucher = VoucherModel(
      id: customId ?? 'inc_${_uuid.v4().substring(0, 12)}',
      companyId: _currentCompanyId,
      voucherNumber: voucherNumber,
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

    final posted = await _postingEngine.postVoucher(
      voucher: voucher,
      userId: _currentUserId,
    );

    await _auditService.recordLog(
      companyId: _currentCompanyId,
      userId: _currentUserId,
      entityType: 'income',
      entityId: posted.id,
      action: AuditAction.insert,
      newState: posted.toMap(),
    );

    _notifyUpdates();
    return posted;
  }

  Future<VoucherModel> addTransfer({
    required String walletAccountId,
    required String toWalletAccountId,
    required int amountInCents,
    DateTime? date,
    String? narration,
    String? referenceNumber,
    String? customId,
  }) async {
    await _ensureExpenseTrackerMode();
    AccessControlService.verifyPermission(_currentRole, UserAction.createExpense);

    final now = DateTime.now();
    final txnDate = date ?? now;
    final voucherNumber =
        await _voucherRepo.generateNextVoucherNumber(VoucherType.transfer);

    final voucher = VoucherModel(
      id: customId ?? 'trf_${_uuid.v4().substring(0, 12)}',
      companyId: _currentCompanyId,
      voucherNumber: voucherNumber,
      type: VoucherType.transfer,
      date: txnDate,
      status: VoucherStatus.posted,
      totalAmountInCents: amountInCents,
      walletAccountId: walletAccountId,
      toWalletAccountId: toWalletAccountId,
      narration: narration,
      referenceNumber: referenceNumber,
      createdAt: now,
      updatedAt: now,
    );

    final posted = await _postingEngine.postVoucher(
      voucher: voucher,
      userId: _currentUserId,
    );

    await _auditService.recordLog(
      companyId: _currentCompanyId,
      userId: _currentUserId,
      entityType: 'transfer',
      entityId: posted.id,
      action: AuditAction.insert,
      newState: posted.toMap(),
    );

    _notifyUpdates();
    return posted;
  }

  Future<VoucherModel> updateTransaction(VoucherModel voucher) async {
    await _ensureExpenseTrackerMode();
    AccessControlService.verifyPermission(_currentRole, UserAction.editExpense);

    final updated = await _postingEngine.editVoucher(
      voucher: voucher.copyWith(companyId: _currentCompanyId),
      userId: _currentUserId,
    );

    await _auditService.recordLog(
      companyId: _currentCompanyId,
      userId: _currentUserId,
      entityType: 'transaction',
      entityId: updated.id,
      action: AuditAction.update,
      newState: updated.toMap(),
    );

    _notifyUpdates();
    return updated;
  }

  Future<void> voidTransaction(String voucherId) async {
    await _ensureExpenseTrackerMode();
    AccessControlService.verifyPermission(_currentRole, UserAction.voidExpense);

    await _postingEngine.voidVoucher(
      voucherId: voucherId,
      companyId: _currentCompanyId,
      userId: _currentUserId,
    );

    _notifyUpdates();
  }

  Future<void> restoreTransaction(String voucherId) async {
    await _ensureExpenseTrackerMode();
    AccessControlService.verifyPermission(_currentRole, UserAction.voidExpense);

    await _postingEngine.restoreVoucher(
      voucherId: voucherId,
      companyId: _currentCompanyId,
      userId: _currentUserId,
    );

    _notifyUpdates();
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

    final query = _db.select(_db.vouchers)
      ..where((t) => t.companyId.equals(_currentCompanyId) & t.isDeleted.equals(false))
      ..orderBy([(t) => OrderingTerm.desc(t.date), (t) => OrderingTerm.desc(t.createdAt)]);

    if (!includeVoided) {
      query.where((t) => t.status.equals(VoucherStatus.posted.name));
    }

    if (type != null) {
      query.where((t) => t.type.equals(type.name));
    } else {
      // By default in expense tracker mode, show expense, income, and transfer vouchers
      query.where((t) =>
          t.type.equals(VoucherType.expense.name) |
          t.type.equals(VoucherType.income.name) |
          t.type.equals(VoucherType.transfer.name));
    }

    if (startDate != null) {
      query.where((t) => t.date.isBiggerOrEqualValue(startDate));
    }
    if (endDate != null) {
      query.where((t) => t.date.isSmallerOrEqualValue(endDate));
    }

    if (categoryIds != null && categoryIds.isNotEmpty) {
      query.where((t) => t.categoryAccountId.isIn(categoryIds));
    }

    if (walletIds != null && walletIds.isNotEmpty) {
      query.where((t) =>
          t.walletAccountId.isIn(walletIds) |
          t.toWalletAccountId.isIn(walletIds));
    }

    final rows = await query.get();
    var result = rows.map((r) => VoucherModel.fromMap({
          'id': r.id,
          'companyId': r.companyId,
          'voucherNumber': r.voucherNumber,
          'type': r.type,
          'date': r.date.toIso8601String(),
          'dueDate': r.dueDate?.toIso8601String(),
          'partyId': r.partyId,
          'partyName': r.partyName,
          'status': r.status,
          'paymentMode': r.paymentMode,
          'subtotalInCents': r.subtotalInCents,
          'taxInCents': r.taxInCents,
          'discountInCents': r.discountInCents,
          'totalAmountInCents': r.totalAmountInCents,
          'narration': r.narration,
          'referenceNumber': r.referenceNumber,
          'sourceVoucherId': r.sourceVoucherId,
          'receiptPhotoUrl': r.receiptPhotoUrl,
          'itemsJson': r.itemsJson,
          'categoryAccountId': r.categoryAccountId,
          'walletAccountId': r.walletAccountId,
          'toWalletAccountId': r.toWalletAccountId,
          'createdAt': r.createdAt.toIso8601String(),
          'updatedAt': r.updatedAt.toIso8601String(),
        })).toList();

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

    final query = _db.select(_db.vouchers)
      ..where((t) => t.companyId.equals(_currentCompanyId) & t.isDeleted.equals(false))
      ..orderBy([(t) => OrderingTerm.desc(t.date), (t) => OrderingTerm.desc(t.createdAt)]);

    if (!includeVoided) {
      query.where((t) => t.status.equals(VoucherStatus.posted.name));
    }

    if (type != null) {
      query.where((t) => t.type.equals(type.name));
    } else {
      query.where((t) =>
          t.type.equals(VoucherType.expense.name) |
          t.type.equals(VoucherType.income.name) |
          t.type.equals(VoucherType.transfer.name));
    }

    if (startDate != null) {
      query.where((t) => t.date.isBiggerOrEqualValue(startDate));
    }
    if (endDate != null) {
      query.where((t) => t.date.isSmallerOrEqualValue(endDate));
    }

    if (categoryIds != null && categoryIds.isNotEmpty) {
      query.where((t) => t.categoryAccountId.isIn(categoryIds));
    }

    if (walletIds != null && walletIds.isNotEmpty) {
      query.where((t) =>
          t.walletAccountId.isIn(walletIds) |
          t.toWalletAccountId.isIn(walletIds));
    }

    return query.watch().map((rows) {
      var result = rows.map((r) => VoucherModel.fromMap({
            'id': r.id,
            'companyId': r.companyId,
            'voucherNumber': r.voucherNumber,
            'type': r.type,
            'date': r.date.toIso8601String(),
            'dueDate': r.dueDate?.toIso8601String(),
            'partyId': r.partyId,
            'partyName': r.partyName,
            'status': r.status,
            'paymentMode': r.paymentMode,
            'subtotalInCents': r.subtotalInCents,
            'taxInCents': r.taxInCents,
            'discountInCents': r.discountInCents,
            'totalAmountInCents': r.totalAmountInCents,
            'narration': r.narration,
            'referenceNumber': r.referenceNumber,
            'sourceVoucherId': r.sourceVoucherId,
            'receiptPhotoUrl': r.receiptPhotoUrl,
            'itemsJson': r.itemsJson,
            'categoryAccountId': r.categoryAccountId,
            'walletAccountId': r.walletAccountId,
            'toWalletAccountId': r.toWalletAccountId,
            'createdAt': r.createdAt.toIso8601String(),
            'updatedAt': r.updatedAt.toIso8601String(),
          })).toList();

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

  // ==========================================
  // WALLET CRUD & OPENING BALANCE
  // ==========================================

  Future<List<AccountModel>> getWallets({bool includeArchived = false}) async {
    await _ensureExpenseTrackerMode();
    AccessControlService.verifyPermission(_currentRole, UserAction.viewExpenses);

    final query = _db.select(_db.accounts)
      ..where((t) =>
          t.companyId.equals(_currentCompanyId) &
          t.isDeleted.equals(false) &
          (t.type.equals(AccountType.asset.name) |
              t.type.equals(AccountType.liability.name)));

    if (!includeArchived) {
      query.where((t) => t.isActive.equals(true));
    }

    final rows = await query.get();
    return rows.map(_accountFromRow).toList();
  }

  Future<AccountModel> getWalletById(String id) async {
    await _ensureExpenseTrackerMode();
    AccessControlService.verifyPermission(_currentRole, UserAction.viewExpenses);

    final row = await (_db.select(_db.accounts)
          ..where((t) =>
              t.id.equals(id) &
              t.companyId.equals(_currentCompanyId) &
              t.isDeleted.equals(false)))
        .getSingleOrNull();

    if (row == null) {
      throw AccountNotFoundException(id, 'Wallet account not found: $id');
    }
    return _accountFromRow(row);
  }

  Future<String> _generateUniqueCode({
    required AccountType type,
    required String kind,
  }) async {
    int startCode;
    int endCode;

    if (kind == 'wallet') {
      startCode = (type == AccountType.asset) ? 1100 : 2100;
      endCode = startCode + 99;
    } else {
      startCode = (type == AccountType.expense) ? 5100 : 4100;
      endCode = startCode + 799;
    }

    final existingCodesRows = await (_db.select(_db.accounts)
          ..where((t) => t.companyId.equals(_currentCompanyId) & t.isDeleted.equals(false)))
        .get();

    final existingCodes = existingCodesRows.map((r) => r.code).toSet();

    for (int candidate = startCode; candidate <= endCode; candidate++) {
      final codeStr = candidate.toString();
      if (!existingCodes.contains(codeStr)) {
        return codeStr;
      }
    }

    return '${startCode}_${DateTime.now().millisecondsSinceEpoch}';
  }

  Future<AccountModel> createWallet({
    required String name,
    required AccountType type,
    int openingBalanceInCents = 0,
    String? description,
    String? code,
  }) async {
    await _ensureExpenseTrackerMode();
    AccessControlService.verifyPermission(
        _currentRole, UserAction.manageWalletsAndCategories);

    if (type != AccountType.asset && type != AccountType.liability) {
      throw ArgumentError('Wallet must be of type asset or liability.');
    }

    final now = DateTime.now();
    final walletId =
        '${_currentCompanyId}_acc_wallet_${_uuid.v4().substring(0, 8)}';
    final walletCode = code ?? await _generateUniqueCode(type: type, kind: 'wallet');

    final companion = AccountsCompanion.insert(
      id: walletId,
      companyId: Value(_currentCompanyId),
      code: walletCode,
      name: name,
      type: type.name,
      kind: const Value('wallet'),
      parentAccountId: const Value(null),
      isSystem: const Value(false),
      isActive: const Value(true),
      description: Value(description ?? 'Wallet: $name'),
      currentBalanceInCents: const Value(0),
      createdAt: Value(now),
      updatedAt: Value(now),
      isDeleted: const Value(false),
      syncStatus: const Value(SyncRecordStatus.pending),
    );

    await _db.into(_db.accounts).insert(companion);

    if (openingBalanceInCents != 0) {
      await setOpeningBalance(walletId, openingBalanceInCents);
    }

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
      table: 'accounts',
      recordId: walletId,
      type: 'INSERT',
      fullRowMap: created.toMap(),
    );

    _notifyUpdates();
    return created;
  }

  Future<AccountModel> updateWallet({
    required String id,
    String? name,
    String? description,
    bool? isActive,
  }) async {
    await _ensureExpenseTrackerMode();
    AccessControlService.verifyPermission(
        _currentRole, UserAction.manageWalletsAndCategories);

    final existing = await getWalletById(id);

    final companion = AccountsCompanion(
      name: name != null ? Value(name) : const Value.absent(),
      description:
          description != null ? Value(description) : const Value.absent(),
      isActive: isActive != null ? Value(isActive) : const Value.absent(),
      updatedAt: Value(DateTime.now()),
      syncStatus: const Value(SyncRecordStatus.pending),
    );

    await (_db.update(_db.accounts)
          ..where((t) => t.id.equals(id) & t.companyId.equals(_currentCompanyId)))
        .write(companion);

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
      table: 'accounts',
      recordId: id,
      type: 'UPDATE',
      fullRowMap: updated.toMap(),
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
    final vCount = await (_db.select(_db.vouchers)
          ..where((t) =>
              t.companyId.equals(_currentCompanyId) &
              (t.walletAccountId.equals(id) | t.toWalletAccountId.equals(id))))
        .get();

    final jCount = await (_db.select(_db.journalLines)
          ..where((t) =>
              t.companyId.equals(_currentCompanyId) &
              t.accountId.equals(id) &
              t.isDeleted.equals(false)))
        .get();

    final hasTransactions = vCount.isNotEmpty || jCount.isNotEmpty;
    final now = DateTime.now();

    if (hasTransactions) {
      // Archive instead of delete
      await (_db.update(_db.accounts)
            ..where((t) =>
                t.id.equals(id) & t.companyId.equals(_currentCompanyId)))
          .write(AccountsCompanion(
        isActive: const Value(false),
        updatedAt: Value(now),
        syncStatus: const Value(SyncRecordStatus.pending),
      ));
    } else {
      // Soft-delete
      await (_db.update(_db.accounts)
            ..where((t) =>
                t.id.equals(id) & t.companyId.equals(_currentCompanyId)))
          .write(AccountsCompanion(
        isDeleted: const Value(true),
        isActive: const Value(false),
        updatedAt: Value(now),
        syncStatus: const Value(SyncRecordStatus.pending),
      ));
    }

    final updated = existing.copyWith(
      isActive: false,
      isDeleted: !hasTransactions,
      updatedAt: now,
    );

    await _auditService.recordLog(
      companyId: _currentCompanyId,
      userId: _currentUserId,
      entityType: 'wallet',
      entityId: id,
      action: hasTransactions ? AuditAction.update : AuditAction.delete,
      oldState: existing.toMap(),
      newState: updated.toMap(),
    );

    await enqueueMutation(
      db: _db,
      table: 'accounts',
      recordId: id,
      type: 'UPDATE',
      fullRowMap: updated.toMap(),
    );

    _notifyUpdates();
    return !hasTransactions;
  }

  Future<void> setOpeningBalance(
    String walletId,
    int openingBalanceInCents,
  ) async {
    await _ensureExpenseTrackerMode();
    AccessControlService.verifyPermission(
        _currentRole, UserAction.manageWalletsAndCategories);

    final wallet = await getWalletById(walletId);
    final equityId =
        '${_currentCompanyId}_${ExpenseTrackerDefaults.openingBalanceEquityId}';

    // Ensure Opening Balance Equity account exists
    final equityRow = await (_db.select(_db.accounts)
          ..where((t) =>
              t.id.equals(equityId) & t.companyId.equals(_currentCompanyId)))
        .getSingleOrNull();

    if (equityRow == null) {
      await _db.into(_db.accounts).insertOnConflictUpdate(
            AccountsCompanion.insert(
              id: equityId,
              companyId: Value(_currentCompanyId),
              code: '3100',
              name: 'Opening Balance Equity',
              type: AccountType.equity.name,
              isSystem: const Value(true),
              isActive: const Value(true),
              description: const Value('Opening equity balancing account'),
              currentBalanceInCents: const Value(0),
              createdAt: Value(DateTime.now()),
              updatedAt: Value(DateTime.now()),
            ),
          );
    }

    final journalId = 'jnl_opening_${_currentCompanyId}_$walletId';
    final journalNumber = 'JNL-OP-$walletId';
    final now = DateTime.now();

    final List<JournalLinesCompanion> lines = [];
    final isAsset = wallet.type == AccountType.asset;

    if (openingBalanceInCents > 0) {
      if (isAsset) {
        // Debit Wallet, Credit Equity
        lines.add(JournalLinesCompanion.insert(
          id: '${journalId}_dr',
          companyId: Value(_currentCompanyId),
          journalId: journalId,
          accountId: walletId,
          debitInCents: Value(openingBalanceInCents),
          creditInCents: const Value(0),
          narration: Value('Opening balance for ${wallet.name}'),
          createdAt: Value(now),
          updatedAt: Value(now),
        ));
        lines.add(JournalLinesCompanion.insert(
          id: '${journalId}_cr',
          companyId: Value(_currentCompanyId),
          journalId: journalId,
          accountId: equityId,
          debitInCents: const Value(0),
          creditInCents: Value(openingBalanceInCents),
          narration: const Value('Opening Balance Equity offset'),
          createdAt: Value(now),
          updatedAt: Value(now),
        ));
      } else {
        // Liability wallet (e.g. Credit Card): spending/opening debt increases liability (Credit)
        // Debit Equity, Credit Wallet
        lines.add(JournalLinesCompanion.insert(
          id: '${journalId}_dr',
          companyId: Value(_currentCompanyId),
          journalId: journalId,
          accountId: equityId,
          debitInCents: Value(openingBalanceInCents),
          creditInCents: const Value(0),
          narration: const Value('Opening Balance Equity offset'),
          createdAt: Value(now),
          updatedAt: Value(now),
        ));
        lines.add(JournalLinesCompanion.insert(
          id: '${journalId}_cr',
          companyId: Value(_currentCompanyId),
          journalId: journalId,
          accountId: walletId,
          debitInCents: const Value(0),
          creditInCents: Value(openingBalanceInCents),
          narration: Value('Opening liability for ${wallet.name}'),
          createdAt: Value(now),
          updatedAt: Value(now),
        ));
      }
    }

    await _db.transaction(() async {
      // Upsert journal header
      await _db.into(_db.journals).insertOnConflictUpdate(
            JournalsCompanion.insert(
              id: journalId,
              companyId: Value(_currentCompanyId),
              journalNumber: journalNumber,
              voucherId: const Value(null),
              date: now,
              narration: Value('Opening Balance for ${wallet.name}'),
              totalAmountInCents: Value(openingBalanceInCents),
              status: const Value('posted'),
              createdAt: Value(now),
              updatedAt: Value(now),
            ),
          );

      // Delete existing opening journal lines for this wallet (from seed or prior setOpeningBalance)
      final priorOpeningLines = await (_db.select(_db.journalLines)
            ..where((t) =>
                t.companyId.equals(_currentCompanyId) &
                t.accountId.equals(walletId) &
                t.journalId.like('jnl_opening_$_currentCompanyId%')))
          .get();

      for (final l in priorOpeningLines) {
        await (_db.update(_db.journalLines)..where((t) => t.id.equals(l.id))).write(
          JournalLinesCompanion(
            isDeleted: const Value(true),
            syncStatus: const Value(SyncRecordStatus.pending),
            updatedAt: Value(now),
          ),
        );
      }

      // Soft-delete existing lines for this specific wallet opening journal
      await (_db.update(_db.journalLines)..where((t) => t.journalId.equals(journalId))).write(
        JournalLinesCompanion(
          isDeleted: const Value(true),
          syncStatus: const Value(SyncRecordStatus.pending),
          updatedAt: Value(now),
        ),
      );

      for (final line in lines) {
        await _db.into(_db.journalLines).insertOnConflictUpdate(line);
      }

      // Recalculate account balances
      await _postingEngine.recalculateAccountBalance(
          walletId, _currentCompanyId);
      await _postingEngine.recalculateAccountBalance(
          equityId, _currentCompanyId);
    });

    _notifyUpdates();
  }

  // ==========================================
  // CATEGORY CRUD
  // ==========================================

  Future<List<AccountModel>> getCategories({
    AccountType? type,
    bool includeArchived = false,
  }) async {
    await _ensureExpenseTrackerMode();
    AccessControlService.verifyPermission(_currentRole, UserAction.viewExpenses);

    final query = _db.select(_db.accounts)
      ..where((t) =>
          t.companyId.equals(_currentCompanyId) &
          t.isDeleted.equals(false) &
          (t.type.equals(AccountType.expense.name) |
              t.type.equals(AccountType.income.name)));

    if (type != null) {
      query.where((t) => t.type.equals(type.name));
    }
    if (!includeArchived) {
      query.where((t) => t.isActive.equals(true));
    }

    final rows = await query.get();
    return rows.map(_accountFromRow).toList();
  }

  Future<AccountModel> getCategoryById(String id) async {
    await _ensureExpenseTrackerMode();
    AccessControlService.verifyPermission(_currentRole, UserAction.viewExpenses);

    final row = await (_db.select(_db.accounts)
          ..where((t) =>
              t.id.equals(id) &
              t.companyId.equals(_currentCompanyId) &
              t.isDeleted.equals(false)))
        .getSingleOrNull();

    if (row == null) {
      throw AccountNotFoundException(id, 'Category account not found: $id');
    }
    return _accountFromRow(row);
  }

  Future<AccountModel> createCategory({
    required String name,
    required AccountType type,
    String? parentAccountId,
    String? description,
    String? code,
  }) async {
    await _ensureExpenseTrackerMode();
    AccessControlService.verifyPermission(
        _currentRole, UserAction.manageWalletsAndCategories);

    if (type != AccountType.expense && type != AccountType.income) {
      throw ArgumentError('Category must be of type expense or income.');
    }

    if (parentAccountId != null) {
      final parent = await getCategoryById(parentAccountId);
      if (parent.type != type) {
        throw ArgumentError(
            'Sub-category type must match parent category type.');
      }
    }

    final now = DateTime.now();
    final catId =
        '${_currentCompanyId}_acc_cat_${_uuid.v4().substring(0, 8)}';
    final catCode = code ?? await _generateUniqueCode(type: type, kind: 'category');

    final companion = AccountsCompanion.insert(
      id: catId,
      companyId: Value(_currentCompanyId),
      code: catCode,
      name: name,
      type: type.name,
      kind: const Value('category'),
      parentAccountId: Value(parentAccountId),
      isSystem: const Value(false),
      isActive: const Value(true),
      description: Value(description ?? 'Category: $name'),
      currentBalanceInCents: const Value(0),
      createdAt: Value(now),
      updatedAt: Value(now),
      isDeleted: const Value(false),
      syncStatus: const Value(SyncRecordStatus.pending),
    );

    await _db.into(_db.accounts).insert(companion);

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
      table: 'accounts',
      recordId: catId,
      type: 'INSERT',
      fullRowMap: created.toMap(),
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
  }) async {
    await _ensureExpenseTrackerMode();
    AccessControlService.verifyPermission(
        _currentRole, UserAction.manageWalletsAndCategories);

    final existing = await getCategoryById(id);

    if (parentAccountId != null && parentAccountId != existing.parentAccountId) {
      final parent = await getCategoryById(parentAccountId);
      if (parent.type != existing.type) {
        throw ArgumentError(
            'Sub-category type must match parent category type.');
      }
    }

    final companion = AccountsCompanion(
      name: name != null ? Value(name) : const Value.absent(),
      parentAccountId:
          parentAccountId != null ? Value(parentAccountId) : const Value.absent(),
      description:
          description != null ? Value(description) : const Value.absent(),
      isActive: isActive != null ? Value(isActive) : const Value.absent(),
      updatedAt: Value(DateTime.now()),
      syncStatus: const Value(SyncRecordStatus.pending),
    );

    await (_db.update(_db.accounts)
          ..where((t) => t.id.equals(id) & t.companyId.equals(_currentCompanyId)))
        .write(companion);

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
      table: 'accounts',
      recordId: id,
      type: 'UPDATE',
      fullRowMap: updated.toMap(),
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
    final vCount = await (_db.select(_db.vouchers)
          ..where((t) =>
              t.companyId.equals(_currentCompanyId) &
              t.categoryAccountId.equals(id)))
        .get();

    final jCount = await (_db.select(_db.journalLines)
          ..where((t) =>
              t.companyId.equals(_currentCompanyId) &
              t.accountId.equals(id) &
              t.isDeleted.equals(false)))
        .get();

    final hasTransactions = vCount.isNotEmpty || jCount.isNotEmpty;
    final now = DateTime.now();

    if (hasTransactions) {
      // Archive instead of delete
      await (_db.update(_db.accounts)
            ..where((t) =>
                t.id.equals(id) & t.companyId.equals(_currentCompanyId)))
          .write(AccountsCompanion(
        isActive: const Value(false),
        updatedAt: Value(now),
        syncStatus: const Value(SyncRecordStatus.pending),
      ));
    } else {
      // Soft-delete
      await (_db.update(_db.accounts)
            ..where((t) =>
                t.id.equals(id) & t.companyId.equals(_currentCompanyId)))
          .write(AccountsCompanion(
        isDeleted: const Value(true),
        isActive: const Value(false),
        updatedAt: Value(now),
        syncStatus: const Value(SyncRecordStatus.pending),
      ));
    }

    final updated = existing.copyWith(
      isActive: false,
      isDeleted: !hasTransactions,
      updatedAt: now,
    );

    await _auditService.recordLog(
      companyId: _currentCompanyId,
      userId: _currentUserId,
      entityType: 'category',
      entityId: id,
      action: hasTransactions ? AuditAction.update : AuditAction.delete,
      oldState: existing.toMap(),
      newState: updated.toMap(),
    );

    await enqueueMutation(
      db: _db,
      table: 'accounts',
      recordId: id,
      type: 'UPDATE',
      fullRowMap: updated.toMap(),
    );

    _notifyUpdates();
    return !hasTransactions;
  }

  // ==========================================
  // MONTH SUMMARY
  // ==========================================

  Future<ExpenseMonthSummary> getMonthSummary(DateTime month) async {
    await _ensureExpenseTrackerMode();
    AccessControlService.verifyPermission(_currentRole, UserAction.viewExpenses);

    final startOfMonth = DateTime(month.year, month.month, 1);
    final endOfMonth =
        DateTime(month.year, month.month + 1, 0, 23, 59, 59, 999);

    final txns = await getTransactions(
      startDate: startOfMonth,
      endDate: endOfMonth,
      includeVoided: false,
    );

    int totalIncome = 0;
    int totalExpense = 0;
    final Map<String, int> categoryTotals = {};
    final Map<String, int> incomeCategoryTotals = {};
    final Map<String, int> expenseCategoryTotals = {};

    for (final txn in txns) {
      if (txn.type == VoucherType.income) {
        totalIncome += txn.totalAmountInCents;
        if (txn.categoryAccountId != null) {
          categoryTotals[txn.categoryAccountId!] =
              (categoryTotals[txn.categoryAccountId!] ?? 0) +
                  txn.totalAmountInCents;
          incomeCategoryTotals[txn.categoryAccountId!] =
              (incomeCategoryTotals[txn.categoryAccountId!] ?? 0) +
                  txn.totalAmountInCents;
        }
      } else if (txn.type == VoucherType.expense) {
        totalExpense += txn.totalAmountInCents;
        if (txn.categoryAccountId != null) {
          categoryTotals[txn.categoryAccountId!] =
              (categoryTotals[txn.categoryAccountId!] ?? 0) +
                  txn.totalAmountInCents;
          expenseCategoryTotals[txn.categoryAccountId!] =
              (expenseCategoryTotals[txn.categoryAccountId!] ?? 0) +
                  txn.totalAmountInCents;
        }
      }
    }

    final wallets = await getWallets(includeArchived: false);
    final Map<String, int> walletBalances = {};

    for (final w in wallets) {
      final query = _db.select(_db.journalLines).join([
        innerJoin(_db.journals, _db.journals.id.equalsExp(_db.journalLines.journalId)),
      ])..where(
        _db.journalLines.accountId.equals(w.id) &
        _db.journalLines.companyId.equals(_currentCompanyId) &
        _db.journalLines.isDeleted.equals(false) &
        _db.journals.status.equals('posted'),
      );

      final rows = await query.get();
      int debit = 0;
      int credit = 0;
      for (final r in rows) {
        final line = r.readTable(_db.journalLines);
        debit += line.debitInCents;
        credit += line.creditInCents;
      }
      walletBalances[w.id] = debit - credit;
    }

    return ExpenseMonthSummary(
      month: startOfMonth,
      totalIncomeInCents: totalIncome,
      totalExpenseInCents: totalExpense,
      netInCents: totalIncome - totalExpense,
      walletBalancesInCents: walletBalances,
      categoryTotalsInCents: categoryTotals,
      incomeCategoryTotalsInCents: incomeCategoryTotals,
      expenseCategoryTotalsInCents: expenseCategoryTotals,
    );
  }

  AccountModel _accountFromRow(AccountTableData r) {
    return AccountModel(
      id: r.id,
      companyId: r.companyId,
      code: r.code,
      name: r.name,
      type: AccountType.values.firstWhere(
        (t) => t.name.toLowerCase() == r.type.toLowerCase(),
        orElse: () => AccountType.asset,
      ),
      parentAccountId: r.parentAccountId,
      kind: r.kind,
      isSystem: r.isSystem,
      isActive: r.isActive,
      description: r.description,
      currentBalanceInCents: r.currentBalanceInCents,
      createdAt: r.createdAt,
      updatedAt: r.updatedAt,
    );
  }

  void dispose() {
    _isDisposed = true;
    _updateStreamController.close();
  }
}
