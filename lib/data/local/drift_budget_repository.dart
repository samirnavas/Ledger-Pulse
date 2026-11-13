import 'dart:async';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../core/network/sync_codec.dart';
import '../../core/network/sync_engine.dart';
import '../local/audit_service.dart';
import '../local/database.dart';
import '../local/outbox_helper.dart';
import '../models/account_model.dart';
import '../models/audit_log_model.dart';
import '../models/budget_model.dart';
import '../models/company_model.dart';
import '../models/rbac_model.dart';
import '../security/access_control_service.dart';

/// Dedicated repository for Budget management and spending progress computations.
/// Operates on Drift database dedicated `expense_budgets` table with full RBAC, audit logging,
/// outbox synchronization, and reactive update stream.
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
      _syncEngine?.triggerBackgroundSync(companyId: _currentCompanyId);
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

    final prof = await (_db.select(_db.profiles)
          ..where((t) => t.id.equals(_currentCompanyId)))
        .getSingleOrNull();
    if (prof != null) {
      _cachedCompany = Company(
        id: prof.id,
        name: prof.name,
        legalName: prof.name,
        currencyCode: prof.currencyCode,
        mode: prof.profileType == 'expense'
            ? CompanyMode.expenseTracker
            : CompanyMode.ledger,
        enabledModules: const {AppModule.vouchers, AppModule.budgets},
        createdAt: prof.createdAt,
        updatedAt: prof.updatedAt,
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

    // Verify category exists and belongs to profile in expense_categories
    if (effCategoryId != 'all' && effCategoryId != 'all_categories') {
      final cat = await (_db.select(_db.expenseCategories)
            ..where((t) =>
                t.id.equals(effCategoryId) &
                t.profileId.equals(_currentCompanyId) &
                t.isDeleted.equals(false)))
          .getSingleOrNull();

      if (cat == null) {
        // Fallback check on accounts table during migration period
        final accCat = await (_db.select(_db.accounts)
              ..where((t) =>
                  t.id.equals(effCategoryId) &
                  t.companyId.equals(_currentCompanyId) &
                  t.isDeleted.equals(false)))
            .getSingleOrNull();
        if (accCat == null) {
          throw ArgumentError('Category not found: $effCategoryId');
        }
      }
    }

    final now = DateTime.now();
    final effectiveStart = startDate ?? now;
    final budgetId = 'bgt_${_uuid.v4().substring(0, 12)}';

    final companion = ExpenseBudgetsCompanion.insert(
      id: budgetId,
      profileId: _currentCompanyId,
      categoryId: effCategoryId == 'all' || effCategoryId == 'all_categories'
          ? const Value(null)
          : Value(effCategoryId),
      periodType: Value(effPeriod.name),
      amountInCents: effAmount,
      startDate: effectiveStart,
      createdAt: Value(now),
      updatedAt: Value(now),
      isDeleted: const Value(false),
      syncStatus: const Value(SyncRecordStatus.pending),
    );

    await _db.into(_db.expenseBudgets).insertOnConflictUpdate(companion);

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

    await enqueueMutation(
      db: _db,
      table: 'exp_budgets',
      recordId: budgetId,
      type: 'INSERT',
      fullRowMap: {
        'id': budgetId,
        'profile_id': _currentCompanyId,
        'category_id': effCategoryId == 'all' || effCategoryId == 'all_categories'
            ? null
            : effCategoryId,
        'period_type': effPeriod.name,
        'amount_in_cents': effAmount,
        'start_date': encodeTime(effectiveStart),
        'created_at': encodeTime(now),
        'updated_at': encodeTime(now),
        'is_deleted': false,
      },
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

    final budgetId = id ?? budget?.id;
    if (budgetId == null) {
      throw ArgumentError('Budget id is required for update.');
    }

    final existing = await getBudgetById(budgetId);
    final now = DateTime.now();

    final newAmount = amountInCents ?? allocatedInCents ?? budget?.amountInCents ?? existing.amountInCents;
    final newPeriod = periodType ?? period ?? budget?.periodType ?? existing.periodType;
    final newStart = startDate ?? budget?.startDate ?? existing.startDate;

    await (_db.update(_db.expenseBudgets)..where((t) => t.id.equals(budgetId))).write(
      ExpenseBudgetsCompanion(
        amountInCents: Value(newAmount),
        periodType: Value(newPeriod.name),
        startDate: Value(newStart),
        updatedAt: Value(now),
        syncStatus: const Value(SyncRecordStatus.pending),
      ),
    );

    final updated = existing.copyWith(
      amountInCents: newAmount,
      periodType: newPeriod,
      startDate: newStart,
      rolloverEnabled: rolloverEnabled ?? existing.rolloverEnabled,
      isActive: isActive ?? existing.isActive,
      updatedAt: now,
      syncStatus: SyncRecordStatus.pending,
    );

    await _auditService.recordLog(
      companyId: _currentCompanyId,
      userId: _currentUserId,
      entityType: 'budget',
      entityId: budgetId,
      action: AuditAction.update,
      oldState: existing.toMap(),
      newState: updated.toMap(),
    );

    await enqueueMutation(
      db: _db,
      table: 'exp_budgets',
      recordId: budgetId,
      type: 'UPDATE',
      fullRowMap: {
        'id': budgetId,
        'profile_id': _currentCompanyId,
        'amount_in_cents': newAmount,
        'period_type': newPeriod.name,
        'start_date': encodeTime(newStart),
        'updated_at': encodeTime(now),
        'is_deleted': false,
      },
    );

    _notifyUpdates();
    return updated;
  }

  Future<void> deleteBudget(String id) async {
    await _ensureBudgetsEnabled();
    AccessControlService.verifyPermission(
        _currentRole, UserAction.manageWalletsAndCategories);

    final existing = await getBudgetById(id);
    final now = DateTime.now();

    await (_db.update(_db.expenseBudgets)..where((t) => t.id.equals(id))).write(
      ExpenseBudgetsCompanion(
        isDeleted: const Value(true),
        updatedAt: Value(now),
        syncStatus: const Value(SyncRecordStatus.pending),
      ),
    );

    await _auditService.recordLog(
      companyId: _currentCompanyId,
      userId: _currentUserId,
      entityType: 'budget',
      entityId: id,
      action: AuditAction.delete,
      oldState: existing.toMap(),
    );

    await enqueueMutation(
      db: _db,
      table: 'exp_budgets',
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
  }

  Future<void> restoreBudget(String id) async {
    await _ensureBudgetsEnabled();
    AccessControlService.verifyPermission(
        _currentRole, UserAction.manageWalletsAndCategories);

    final now = DateTime.now();

    await (_db.update(_db.expenseBudgets)..where((t) => t.id.equals(id))).write(
      ExpenseBudgetsCompanion(
        isDeleted: const Value(false),
        updatedAt: Value(now),
        syncStatus: const Value(SyncRecordStatus.pending),
      ),
    );

    await enqueueMutation(
      db: _db,
      table: 'exp_budgets',
      recordId: id,
      type: 'UPDATE',
      fullRowMap: {
        'id': id,
        'profile_id': _currentCompanyId,
        'is_deleted': false,
        'updated_at': encodeTime(now),
      },
    );

    _notifyUpdates();
  }

  Future<List<BudgetModel>> getBudgets({bool includeInactive = false}) async {
    await _ensureBudgetsEnabled();
    AccessControlService.verifyPermission(_currentRole, UserAction.viewExpenses);

    final query = _db.select(_db.expenseBudgets)
      ..where((t) => t.profileId.equals(_currentCompanyId) & t.isDeleted.equals(false))
      ..orderBy([(t) => OrderingTerm.asc(t.startDate)]);

    final rows = await query.get();
    final legacyList = await (_db.select(_db.budgets)
          ..where((t) => t.companyId.equals(_currentCompanyId)))
        .get();
    final legacyMap = {for (final b in legacyList) b.id: b};

    final result = <BudgetModel>[];
    for (final r in rows) {
      final model = _budgetFromRow(r, legacyMap[r.id]);
      if (!includeInactive && !model.isActive) {
        continue;
      }
      result.add(model);
    }
    return result;
  }

  Stream<List<BudgetModel>> watchBudgets({bool includeInactive = false}) {
    AccessControlService.verifyPermission(_currentRole, UserAction.viewExpenses);

    final query = _db.select(_db.expenseBudgets)
      ..where((t) => t.profileId.equals(_currentCompanyId) & t.isDeleted.equals(false))
      ..orderBy([(t) => OrderingTerm.asc(t.startDate)]);

    return query.watch().asyncMap((rows) async {
      final legacyList = await (_db.select(_db.budgets)
            ..where((t) => t.companyId.equals(_currentCompanyId)))
          .get();
      final legacyMap = {for (final b in legacyList) b.id: b};

      final result = <BudgetModel>[];
      for (final r in rows) {
        final model = _budgetFromRow(r, legacyMap[r.id]);
        if (!includeInactive && !model.isActive) {
          continue;
        }
        result.add(model);
      }
      return result;
    });
  }

  Future<BudgetModel> getBudgetById(String id) async {
    await _ensureBudgetsEnabled();
    AccessControlService.verifyPermission(_currentRole, UserAction.viewExpenses);

    final row = await (_db.select(_db.expenseBudgets)
          ..where((t) =>
              t.id.equals(id) &
              t.profileId.equals(_currentCompanyId) &
              t.isDeleted.equals(false)))
        .getSingleOrNull();

    if (row == null) {
      throw ArgumentError('Budget not found: $id');
    }

    final legacy = await (_db.select(_db.budgets)..where((t) => t.id.equals(id))).getSingleOrNull();
    return _budgetFromRow(row, legacy);
  }

  // ==========================================
  // PROGRESS COMPUTATION & HELPERS
  // ==========================================

  static ({DateTime start, DateTime end}) getPeriodBounds(
    BudgetPeriodType periodType,
    DateTime date,
  ) {
    switch (periodType) {
      case BudgetPeriodType.weekly:
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

  Future<List<String>> _getCategoryAndSubCategoryIds(
      String parentCategoryId) async {
    if (parentCategoryId == 'all' || parentCategoryId == 'all_categories') {
      final allCats = await (_db.select(_db.expenseCategories)
            ..where((t) =>
                t.profileId.equals(_currentCompanyId) &
                t.categoryType.equals('expense') &
                t.isDeleted.equals(false)))
          .get();
      return allCats.map((r) => r.id).toList();
    }

    final result = <String>[parentCategoryId];
    final queue = <String>[parentCategoryId];

    while (queue.isNotEmpty) {
      final currentId = queue.removeAt(0);
      final children = await (_db.select(_db.expenseCategories)
            ..where((t) =>
                t.profileId.equals(_currentCompanyId) &
                t.parentCategoryId.equals(currentId) &
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

  Future<int> _calculateSpentInPeriod(
    List<String> categoryIds,
    DateTime startDate,
    DateTime endDate,
  ) async {
    final rows = await (_db.select(_db.expenseTransactions)
          ..where((t) =>
              t.profileId.equals(_currentCompanyId) &
              t.transactionType.equals('expense') &
              t.isDeleted.equals(false) &
              t.categoryId.isIn(categoryIds) &
              t.transactionDate.isBiggerOrEqualValue(startDate) &
              t.transactionDate.isSmallerOrEqualValue(endDate)))
        .get();

    int total = 0;
    for (final r in rows) {
      total += r.amountInCents;
    }
    return total;
  }

  Future<BudgetProgress> calculateProgress(
    BudgetModel budget, {
    DateTime? asOfDate,
  }) async {
    final date = asOfDate ?? DateTime.now();
    final bounds = getPeriodBounds(budget.periodType, date);

    AccountModel? catModel;
    if (budget.categoryAccountId == 'all' || budget.categoryAccountId == 'all_categories') {
      catModel = AccountModel(
        id: 'all',
        companyId: _currentCompanyId,
        code: 'ALL',
        name: 'All Categories (Overall)',
        type: AccountType.expense,
        isSystem: true,
        isActive: true,
        currentBalanceInCents: 0,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
    } else {
      final catRow = await (_db.select(_db.expenseCategories)
            ..where((t) =>
                t.id.equals(budget.categoryAccountId) &
                t.profileId.equals(_currentCompanyId)))
          .getSingleOrNull();
      if (catRow != null) {
        catModel = AccountModel(
          id: catRow.id,
          companyId: catRow.profileId,
          code: catRow.id,
          name: catRow.name,
          type: AccountType.expense,
          kind: 'category',
          isSystem: catRow.isSystem,
          isActive: !catRow.isDeleted,
          currentBalanceInCents: 0,
          createdAt: catRow.createdAt,
          updatedAt: catRow.updatedAt,
        );
      }
    }

    final categoryIds =
        await _getCategoryAndSubCategoryIds(budget.categoryAccountId);

    final spentInCents =
        await _calculateSpentInPeriod(categoryIds, bounds.start, bounds.end);

    int rolloverInCents = 0;
    if (budget.rolloverEnabled) {
      final prevBounds = getPreviousPeriodBounds(budget.periodType, date);
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

  Future<BudgetProgress?> getAllCategoriesBudget({DateTime? month}) async {
    final targetMonth = month ?? DateTime.now();
    final activeBudgets = await getBudgets(includeInactive: false);
    final allCatBudget = activeBudgets
        .where((b) => b.categoryAccountId == 'all' || b.categoryAccountId == 'all_categories')
        .firstOrNull;

    if (allCatBudget == null) {
      return null;
    }

    return await calculateProgress(allCatBudget, asOfDate: targetMonth);
  }

  BudgetModel _budgetFromRow(ExpenseBudgetTableData r, [BudgetTableData? legacy]) {
    return BudgetModel(
      id: r.id,
      companyId: r.profileId,
      categoryAccountId: r.categoryId ?? 'all',
      periodType: BudgetPeriodType.fromString(r.periodType),
      amountInCents: r.amountInCents,
      startDate: r.startDate,
      rolloverEnabled: legacy?.rolloverEnabled ?? false,
      isActive: legacy?.isActive ?? true,
      createdAt: r.createdAt,
      updatedAt: r.updatedAt,
      isDeleted: r.isDeleted,
      syncStatus: r.syncStatus,
    );
  }
}
