import 'dart:async';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../core/network/sync_engine.dart';
import '../local/audit_service.dart';
import '../local/database.dart';
import '../models/account_model.dart';
import '../models/audit_log_model.dart';
import '../models/budget_model.dart';
import '../models/company_model.dart';
import '../models/rbac_model.dart';
import '../models/voucher_model.dart';
import '../security/access_control_service.dart';

/// Dedicated repository for Budget management and spending progress computations.
/// Operates on Drift database Budgets table with full RBAC, audit logging, outbox
/// synchronization, and reactive update stream.
class DriftBudgetRepository {
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
  bool _isDisposed = false;

  DriftBudgetRepository({
    required AppDatabase db,
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
        _cachedCompany = company;

  Stream<void> get repositoryUpdatesStream => _updateStreamController.stream;

  void _notifyUpdates() {
    if (!_isDisposed && !_updateStreamController.isClosed) {
      _updateStreamController.add(null);
    }
  }

  void dispose() {
    _isDisposed = true;
    _updateStreamController.close();
  }

  void setContext({
    String? companyId,
    String? userId,
    Role? role,
    Company? company,
  }) {
    if (companyId != null && companyId != _currentCompanyId) {
      _currentCompanyId = companyId;
      _cachedCompany = null;
    }
    if (userId != null) _currentUserId = userId;
    if (role != null) _currentRole = role;
    if (company != null) {
      _cachedCompany = company;
      _currentCompanyId = company.id;
    }
  }

  void invalidateCompanyCache() {
    _cachedCompany = null;
  }

  Future<Company> _getCompany() async {
    if (_cachedCompany != null && _cachedCompany!.id == _currentCompanyId) {
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
        mode: CompanyMode.fromName(row.mode),
        enabledModules: AppModule.parseSet(row.enabledModulesJson),
        createdAt: row.createdAt,
        updatedAt: row.updatedAt,
      );
      return _cachedCompany!;
    }

    return Company(
      id: _currentCompanyId,
      name: 'Default Company',
      legalName: 'Default Company',
      mode: CompanyMode.expenseTracker,
      enabledModules: const {AppModule.vouchers, AppModule.budgets},
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  Future<void> _ensureBudgetsEnabled() async {
    final company = await _getCompany();
    if (company.mode != CompanyMode.expenseTracker) {
      throw StateError(
        'Budgets are only available in Expense Tracker mode. Current company mode: ${company.mode.name}',
      );
    }
    if (!company.isModuleEnabled(AppModule.budgets)) {
      throw StateError(
        'Budgets module is disabled for company ${company.name} (${company.id}).',
      );
    }
  }

  Future<void> _queueOutbox({
    required String entityType,
    required String entityId,
    required String operation,
    required Map<String, dynamic> payload,
  }) async {
    try {
      await _db.into(_db.syncOutbox).insert(
            SyncOutboxCompanion.insert(
              id: _uuid.v4(),
              targetTable: entityType,
              recordId: entityId,
              mutationType: operation,
              payload: payload.toString(),
            ),
          );
      _syncEngine?.pushQueue(companyId: _currentCompanyId);
    } catch (e) {
      debugPrint('Failed to enqueue sync outbox mutation: $e');
    }
  }

  // ==========================================
  // CRUD OPERATIONS
  // ==========================================

  Future<BudgetModel> createBudget({
    String? categoryAccountId,
    String? categoryId,
    int? amountInCents,
    int? allocatedInCents,
    BudgetPeriodType? periodType,
    BudgetPeriodType? period,
    DateTime? startDate,
    bool rolloverEnabled = false,
  }) async {
    await _ensureBudgetsEnabled();
    AccessControlService.verifyPermission(
        _currentRole, UserAction.manageWalletsAndCategories);

    final effCategoryId = categoryAccountId ?? categoryId;
    if (effCategoryId == null) {
      throw ArgumentError('categoryAccountId or categoryId is required.');
    }
    final effAmount = amountInCents ?? allocatedInCents ?? 0;
    final effPeriod = periodType ?? period ?? BudgetPeriodType.monthly;

    if (effAmount <= 0) {
      throw ArgumentError('Budget amount must be greater than zero.');
    }

    // Verify category exists and belongs to company
    final cat = await (_db.select(_db.accounts)
          ..where((t) =>
              t.id.equals(effCategoryId) &
              t.companyId.equals(_currentCompanyId) &
              t.isDeleted.equals(false)))
        .getSingleOrNull();

    if (cat == null) {
      throw ArgumentError('Category account not found: $effCategoryId');
    }

    final now = DateTime.now();
    final effectiveStart = startDate ?? now;
    final budgetId = 'bgt_${_uuid.v4().substring(0, 12)}';

    final companion = BudgetsCompanion.insert(
      id: budgetId,
      companyId: Value(_currentCompanyId),
      categoryAccountId: effCategoryId,
      periodType: effPeriod.name,
      amountInCents: effAmount,
      startDate: effectiveStart,
      rolloverEnabled: Value(rolloverEnabled),
      isActive: const Value(true),
      createdAt: Value(now),
      updatedAt: Value(now),
      isDeleted: const Value(false),
      syncStatus: const Value(SyncRecordStatus.pending),
    );

    await _db.into(_db.budgets).insertOnConflictUpdate(companion);

    final model = BudgetModel(
      id: budgetId,
      companyId: _currentCompanyId,
      categoryAccountId: effCategoryId,
      periodType: effPeriod,
      amountInCents: effAmount,
      startDate: effectiveStart,
      rolloverEnabled: rolloverEnabled,
      isActive: true,
      createdAt: now,
      updatedAt: now,
      isDeleted: false,
      syncStatus: SyncRecordStatus.pending,
    );

    await _auditService.recordLog(
      companyId: _currentCompanyId,
      userId: _currentUserId,
      entityType: 'budget',
      entityId: budgetId,
      action: AuditAction.insert,
      newState: model.toMap(),
    );

    await _queueOutbox(
      entityType: 'budget',
      entityId: budgetId,
      operation: 'insert',
      payload: model.toMap(),
    );

    _notifyUpdates();
    return model;
  }

  Future<BudgetModel> updateBudget({
    BudgetModel? budget,
    String? id,
    int? amountInCents,
    int? allocatedInCents,
    BudgetPeriodType? periodType,
    BudgetPeriodType? period,
    bool? rolloverEnabled,
    bool? isActive,
    DateTime? startDate,
  }) async {
    await _ensureBudgetsEnabled();
    AccessControlService.verifyPermission(
        _currentRole, UserAction.manageWalletsAndCategories);

    final effectiveId = id ?? budget?.id;
    if (effectiveId == null) throw ArgumentError('Budget id is required');

    final existing = await getBudgetById(effectiveId);
    final now = DateTime.now();

    final updated = existing.copyWith(
      amountInCents:
          amountInCents ?? allocatedInCents ?? budget?.amountInCents,
      periodType: periodType ?? period ?? budget?.periodType,
      rolloverEnabled: rolloverEnabled ?? budget?.rolloverEnabled,
      isActive: isActive ?? budget?.isActive,
      startDate: startDate ?? budget?.startDate,
      updatedAt: now,
    );

    await (_db.update(_db.budgets)
          ..where((t) =>
              t.id.equals(effectiveId) & t.companyId.equals(_currentCompanyId)))
        .write(BudgetsCompanion(
      amountInCents: Value(updated.amountInCents),
      periodType: Value(updated.periodType.name),
      rolloverEnabled: Value(updated.rolloverEnabled),
      isActive: Value(updated.isActive),
      startDate: Value(updated.startDate),
      updatedAt: Value(now),
      syncStatus: const Value(SyncRecordStatus.pending),
    ));

    await _auditService.recordLog(
      companyId: _currentCompanyId,
      userId: _currentUserId,
      entityType: 'budget',
      entityId: effectiveId,
      action: AuditAction.update,
      oldState: existing.toMap(),
      newState: updated.toMap(),
    );

    await _queueOutbox(
      entityType: 'budget',
      entityId: effectiveId,
      operation: 'update',
      payload: updated.toMap(),
    );

    _notifyUpdates();
    return updated;
  }

  Future<bool> deleteBudget(String id) async {
    await _ensureBudgetsEnabled();
    AccessControlService.verifyPermission(
        _currentRole, UserAction.manageWalletsAndCategories);

    final existing = await getBudgetById(id);
    final now = DateTime.now();

    await (_db.update(_db.budgets)
          ..where((t) =>
              t.id.equals(id) & t.companyId.equals(_currentCompanyId)))
        .write(BudgetsCompanion(
      isDeleted: const Value(true),
      isActive: const Value(false),
      updatedAt: Value(now),
      syncStatus: const Value(SyncRecordStatus.pending),
    ));

    await _auditService.recordLog(
      companyId: _currentCompanyId,
      userId: _currentUserId,
      entityType: 'budget',
      entityId: id,
      action: AuditAction.delete,
      oldState: existing.toMap(),
      newState: {'id': id, 'isDeleted': true},
    );

    await _queueOutbox(
      entityType: 'budget',
      entityId: id,
      operation: 'delete',
      payload: {'id': id},
    );

    _notifyUpdates();
    return true;
  }

  Future<BudgetModel> getBudgetById(String id) async {
    await _ensureBudgetsEnabled();
    final row = await (_db.select(_db.budgets)
          ..where((t) =>
              t.id.equals(id) &
              t.companyId.equals(_currentCompanyId) &
              t.isDeleted.equals(false)))
        .getSingleOrNull();

    if (row == null) {
      throw StateError('Budget not found with ID $id');
    }
    return _budgetFromRow(row);
  }

  Future<List<BudgetModel>> getBudgets({bool includeInactive = false}) async {
    await _ensureBudgetsEnabled();
    final query = _db.select(_db.budgets)
      ..where((t) =>
          t.companyId.equals(_currentCompanyId) & t.isDeleted.equals(false))
      ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]);

    if (!includeInactive) {
      query.where((t) => t.isActive.equals(true));
    }

    final rows = await query.get();
    return rows.map(_budgetFromRow).toList();
  }

  Stream<List<BudgetModel>> watchBudgets({bool includeInactive = false}) {
    final query = _db.select(_db.budgets)
      ..where((t) =>
          t.companyId.equals(_currentCompanyId) & t.isDeleted.equals(false))
      ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]);

    if (!includeInactive) {
      query.where((t) => t.isActive.equals(true));
    }

    return query.watch().map((rows) => rows.map(_budgetFromRow).toList());
  }

  // ==========================================
  // PERIOD BOUNDS & PROGRESS MATH
  // ==========================================

  /// Returns `(startDate, endDate)` bounds for the given [periodType] enclosing [date].
  static ({DateTime start, DateTime end}) getPeriodBounds(
    BudgetPeriodType periodType,
    DateTime date,
  ) {
    switch (periodType) {
      case BudgetPeriodType.weekly:
        // ISO-8601: Monday is 1, Sunday is 7
        final monday = DateTime(date.year, date.month, date.day)
            .subtract(Duration(days: date.weekday - 1));
        final sunday = monday
            .add(const Duration(days: 6, hours: 23, minutes: 59, seconds: 59, milliseconds: 999));
        return (start: monday, end: sunday);

      case BudgetPeriodType.monthly:
        final start = DateTime(date.year, date.month, 1);
        final end = DateTime(date.year, date.month + 1, 0, 23, 59, 59, 999);
        return (start: start, end: end);

      case BudgetPeriodType.yearly:
        final start = DateTime(date.year, 1, 1);
        final end = DateTime(date.year, 12, 31, 23, 59, 59, 999);
        return (start: start, end: end);
    }
  }

  /// Returns `(startDate, endDate)` bounds for the period immediately preceding [date].
  static ({DateTime start, DateTime end}) getPreviousPeriodBounds(
    BudgetPeriodType periodType,
    DateTime date,
  ) {
    switch (periodType) {
      case BudgetPeriodType.weekly:
        final currentBounds = getPeriodBounds(periodType, date);
        final prevSunday = currentBounds.start.subtract(const Duration(milliseconds: 1));
        return getPeriodBounds(periodType, prevSunday);

      case BudgetPeriodType.monthly:
        final prevMonth = DateTime(date.year, date.month - 1, 15);
        return getPeriodBounds(periodType, prevMonth);

      case BudgetPeriodType.yearly:
        final prevYear = DateTime(date.year - 1, 6, 1);
        return getPeriodBounds(periodType, prevYear);
    }
  }

  /// Recursively collects all category account IDs under [parentCategoryId] (including itself).
  Future<List<String>> _getCategoryAndSubCategoryIds(
      String parentCategoryId) async {
    final result = <String>[parentCategoryId];
    final queue = <String>[parentCategoryId];

    while (queue.isNotEmpty) {
      final currentId = queue.removeAt(0);
      final children = await (_db.select(_db.accounts)
            ..where((t) =>
                t.companyId.equals(_currentCompanyId) &
                t.parentAccountId.equals(currentId) &
                t.isDeleted.equals(false)))
          .get();

      for (final child in children) {
        if (!result.contains(child.id)) {
          result.add(child.id);
          queue.add(child.id);
        }
      }
    }

    return result;
  }

  /// Calculates the sum of expense debits for the category (including sub-categories)
  /// between [startDate] and [endDate].
  Future<int> _calculateSpentInPeriod(
    List<String> categoryIds,
    DateTime startDate,
    DateTime endDate,
  ) async {
    final rows = await (_db.select(_db.vouchers)
          ..where((t) =>
              t.companyId.equals(_currentCompanyId) &
              t.type.equals(VoucherType.expense.name) &
              t.status.equals(VoucherStatus.posted.name) &
              t.categoryAccountId.isIn(categoryIds) &
              t.date.isBiggerOrEqualValue(startDate) &
              t.date.isSmallerOrEqualValue(endDate)))
        .get();

    int total = 0;
    for (final r in rows) {
      total += r.totalAmountInCents;
    }
    return total;
  }

  /// Calculates spending progress, remaining allocation, and rollover for [budget] as of [asOfDate].
  Future<BudgetProgress> calculateProgress(
    BudgetModel budget, {
    DateTime? asOfDate,
  }) async {
    final date = asOfDate ?? DateTime.now();
    final bounds = getPeriodBounds(budget.periodType, date);

    // Get category account details
    final catRow = await (_db.select(_db.accounts)
          ..where((t) =>
              t.id.equals(budget.categoryAccountId) &
              t.companyId.equals(_currentCompanyId)))
        .getSingleOrNull();
    final catModel = catRow != null ? _accountFromRow(catRow) : null;

    // Collect category and all sub-categories
    final categoryIds =
        await _getCategoryAndSubCategoryIds(budget.categoryAccountId);

    // Calculate spent in current period
    final spentInCents =
        await _calculateSpentInPeriod(categoryIds, bounds.start, bounds.end);

    // Calculate rollover if enabled
    int rolloverInCents = 0;
    if (budget.rolloverEnabled) {
      final prevBounds = getPreviousPeriodBounds(budget.periodType, date);
      // Only rollover if previous period is at or after budget start date
      if (prevBounds.end.isAfter(budget.startDate) ||
          prevBounds.end.isAtSameMomentAs(budget.startDate)) {
        final prevSpent = await _calculateSpentInPeriod(
            categoryIds, prevBounds.start, prevBounds.end);
        final unspent = budget.amountInCents - prevSpent;
        if (unspent > 0) {
          rolloverInCents = unspent;
        }
      }
    }

    final effectiveAllocated = budget.amountInCents + rolloverInCents;
    final remainingInCents = effectiveAllocated - spentInCents;
    final percentUsed = effectiveAllocated > 0
        ? (spentInCents / effectiveAllocated) * 100.0
        : 0.0;

    return BudgetProgress(
      budget: budget,
      category: catModel,
      baseAllocatedInCents: budget.amountInCents,
      rolloverInCents: rolloverInCents,
      effectiveAllocatedInCents: effectiveAllocated,
      spentInCents: spentInCents,
      remainingInCents: remainingInCents,
      percentUsed: percentUsed,
      periodStartDate: bounds.start,
      periodEndDate: bounds.end,
    );
  }

  /// Computes the overall monthly budget progress across all active budgets for [month].
  Future<OverallBudgetSummary> getOverallMonthlyBudget({DateTime? month}) async {
    final targetMonth = month ?? DateTime.now();
    final activeBudgets = await getBudgets(includeInactive: false);

    if (activeBudgets.isEmpty) {
      return OverallBudgetSummary.empty();
    }

    final items = <BudgetProgress>[];
    int totalAllocated = 0;
    int totalSpent = 0;

    for (final b in activeBudgets) {
      final progress = await calculateProgress(b, asOfDate: targetMonth);
      items.add(progress);
      totalAllocated += progress.effectiveAllocatedInCents;
      totalSpent += progress.spentInCents;
    }

    final totalRemaining = totalAllocated - totalSpent;
    final overallPercent = totalAllocated > 0
        ? (totalSpent / totalAllocated) * 100.0
        : 0.0;

    return OverallBudgetSummary(
      totalAllocatedInCents: totalAllocated,
      totalSpentInCents: totalSpent,
      totalRemainingInCents: totalRemaining,
      overallPercentUsed: overallPercent,
      items: items,
    );
  }

  // ==========================================
  // HELPERS
  // ==========================================

  BudgetModel _budgetFromRow(BudgetTableData r) {
    return BudgetModel(
      id: r.id,
      companyId: r.companyId,
      categoryAccountId: r.categoryAccountId,
      periodType: BudgetPeriodType.fromString(r.periodType),
      amountInCents: r.amountInCents,
      startDate: r.startDate,
      rolloverEnabled: r.rolloverEnabled,
      isActive: r.isActive,
      createdAt: r.createdAt,
      updatedAt: r.updatedAt,
      isDeleted: r.isDeleted,
      syncStatus: r.syncStatus,
    );
  }

  AccountModel _accountFromRow(AccountTableData r) {
    return AccountModel(
      id: r.id,
      companyId: r.companyId,
      code: r.code,
      name: r.name,
      type: AccountType.values.firstWhere(
        (t) => t.name == r.type,
        orElse: () => AccountType.expense,
      ),
      parentAccountId: r.parentAccountId,
      isSystem: r.isSystem,
      isActive: r.isActive,
      description: r.description,
      currentBalanceInCents: r.currentBalanceInCents,
      createdAt: r.createdAt,
      updatedAt: r.updatedAt,
    );
  }
}
