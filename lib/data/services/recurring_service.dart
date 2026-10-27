import 'dart:async';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../core/network/sync_engine.dart';
import '../local/audit_service.dart';
import '../local/database.dart';
import '../local/drift_expense_repository.dart';
import '../models/audit_log_model.dart';
import '../models/company_model.dart';
import '../models/rbac_model.dart';
import '../models/recurring_rule_model.dart';
import '../models/voucher_model.dart';
import '../security/access_control_service.dart';

/// Dedicated service responsible for generating due recurring transactions,
/// scheduling, and managing recurring rules.
class RecurringService {
  final AppDatabase _db;
  final DriftExpenseRepository _expenseRepo;
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

  RecurringService({
    required AppDatabase db,
    required DriftExpenseRepository expenseRepo,
    AuditService? auditService,
    SyncEngine? syncEngine,
    String currentCompanyId = 'cmp_default',
    String currentUserId = 'usr_default',
    Role currentRole = Role.admin,
    Company? company,
  })  : _db = db,
        _expenseRepo = expenseRepo,
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
    _expenseRepo.setContext(
      companyId: _currentCompanyId,
      userId: _currentUserId,
      role: _currentRole,
      company: _cachedCompany,
    );
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
      enabledModules: const {AppModule.vouchers, AppModule.recurring},
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  Future<bool> isRecurringEnabled() async {
    final company = await _getCompany();
    return company.mode == CompanyMode.expenseTracker &&
        company.isModuleEnabled(AppModule.recurring);
  }

  Future<void> _ensureRecurringEnabled() async {
    final enabled = await isRecurringEnabled();
    if (!enabled) {
      final company = await _getCompany();
      throw StateError(
        'Recurring module is disabled for company ${company.name} (${company.id}).',
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
  // GENERATE DUE TRANSACTIONS
  // ==========================================

  /// Evaluates all active recurring rules for the company that have `nextRunDate <= now`.
  /// Posts template vouchers through [DriftExpenseRepository] with a deterministic voucher ID
  /// (e.g. `rec_<ruleId>_<yyyyMMdd>`), advances `nextRunDate`, and deactivates rules whose
  /// end date has elapsed.
  /// Catch-up iterations are capped at [maxIterations] (default 366).
  Future<int> generateDue(DateTime now, {int maxIterations = 366}) async {
    final enabled = await isRecurringEnabled();
    if (!enabled) return 0;

    final dueRules = await (_db.select(_db.recurringRules)
          ..where((t) =>
              t.companyId.equals(_currentCompanyId) &
              t.isActive.equals(true) &
              t.isDeleted.equals(false) &
              t.nextRunDate.isSmallerOrEqualValue(now)))
        .get();

    int generatedCount = 0;

    for (final ruleRow in dueRules) {
      final rule = _ruleFromRow(ruleRow);
      DateTime currentRun = rule.nextRunDate;
      int iterations = 0;
      bool ruleActive = rule.isActive;

      while ((currentRun.isBefore(now) || currentRun.isAtSameMomentAs(now)) &&
          iterations < maxIterations) {
        // If end date has elapsed, deactivate rule and exit loop
        if (rule.endDate != null && currentRun.isAfter(rule.endDate!)) {
          ruleActive = false;
          break;
        }

        // Deterministic voucher ID ensuring idempotent generation
        final dateStr = DateFormat('yyyyMMdd').format(currentRun);
        final deterministicId = 'rec_${rule.id}_$dateStr';

        // Check if voucher already exists for this execution
        final existingVoucher = await (_db.select(_db.vouchers)
              ..where((t) => t.id.equals(deterministicId)))
            .getSingleOrNull();

        if (existingVoucher == null) {
          try {
            final t = rule.template;
            switch (t.type) {
              case VoucherType.expense:
                if (t.categoryAccountId != null && t.walletAccountId != null) {
                  await _expenseRepo.addExpense(
                    categoryAccountId: t.categoryAccountId!,
                    walletAccountId: t.walletAccountId!,
                    amountInCents: t.amountInCents,
                    date: currentRun,
                    narration: t.narration,
                    referenceNumber: t.referenceNumber,
                    receiptPhotoUrl: t.receiptPhotoUrl,
                    customId: deterministicId,
                  );
                  generatedCount++;
                }
                break;

              case VoucherType.income:
                if (t.categoryAccountId != null && t.walletAccountId != null) {
                  await _expenseRepo.addIncome(
                    categoryAccountId: t.categoryAccountId!,
                    walletAccountId: t.walletAccountId!,
                    amountInCents: t.amountInCents,
                    date: currentRun,
                    narration: t.narration,
                    referenceNumber: t.referenceNumber,
                    receiptPhotoUrl: t.receiptPhotoUrl,
                    customId: deterministicId,
                  );
                  generatedCount++;
                }
                break;

              case VoucherType.transfer:
                if (t.walletAccountId != null && t.toWalletAccountId != null) {
                  await _expenseRepo.addTransfer(
                    walletAccountId: t.walletAccountId!,
                    toWalletAccountId: t.toWalletAccountId!,
                    amountInCents: t.amountInCents,
                    date: currentRun,
                    narration: t.narration,
                    referenceNumber: t.referenceNumber,
                    customId: deterministicId,
                  );
                  generatedCount++;
                }
                break;

              default:
                break;
            }
          } catch (e) {
            debugPrint('Failed to post recurring voucher for rule ${rule.id}: $e');
            // Continue catch-up progression even if an individual voucher fails
          }
        }

        // Advance to next execution interval
        currentRun = advanceDate(currentRun, rule.intervalType, rule.intervalCount);
        iterations++;
      }

      // Check if newly advanced nextRunDate surpasses optional endDate
      if (rule.endDate != null && currentRun.isAfter(rule.endDate!)) {
        ruleActive = false;
      }

      // Update rule row in database
      await (_db.update(_db.recurringRules)
            ..where((t) => t.id.equals(rule.id)))
          .write(RecurringRulesCompanion(
        nextRunDate: Value(currentRun),
        isActive: Value(ruleActive),
        updatedAt: Value(DateTime.now()),
        syncStatus: const Value(SyncRecordStatus.pending),
      ));

      await _queueOutbox(
        entityType: 'recurring_rule',
        entityId: rule.id,
        operation: 'update',
        payload: {
          'id': rule.id,
          'nextRunDate': currentRun.toIso8601String(),
          'isActive': ruleActive,
        },
      );
    }

    if (generatedCount > 0) {
      _notifyUpdates();
    }

    return generatedCount;
  }

  /// Advances [date] forward by [intervalCount] units of [intervalType].
  static DateTime advanceDate(
    DateTime date,
    RecurringIntervalType intervalType, [
    int intervalCount = 1,
  ]) {
    final count = intervalCount < 1 ? 1 : intervalCount;
    switch (intervalType) {
      case RecurringIntervalType.daily:
        return date.add(Duration(days: count));

      case RecurringIntervalType.weekly:
        return date.add(Duration(days: 7 * count));

      case RecurringIntervalType.monthly:
        final nextMonth = date.month + count;
        final yearOffset = (nextMonth - 1) ~/ 12;
        final targetYear = date.year + yearOffset;
        final targetMonth = ((nextMonth - 1) % 12) + 1;
        final daysInTargetMonth = DateTime(targetYear, targetMonth + 1, 0).day;
        final targetDay = date.day > daysInTargetMonth ? daysInTargetMonth : date.day;
        return DateTime(
          targetYear,
          targetMonth,
          targetDay,
          date.hour,
          date.minute,
          date.second,
          date.millisecond,
        );

      case RecurringIntervalType.yearly:
        final targetYear = date.year + count;
        final isLeapTarget = (targetYear % 4 == 0 && targetYear % 100 != 0) || (targetYear % 400 == 0);
        final targetDay = (date.month == 2 && date.day == 29 && !isLeapTarget) ? 28 : date.day;
        return DateTime(
          targetYear,
          date.month,
          targetDay,
          date.hour,
          date.minute,
          date.second,
          date.millisecond,
        );
    }
  }

  // ==========================================
  // CRUD OPERATIONS FOR RECURRING RULES
  // ==========================================

  Future<RecurringRuleModel> createRule({
    required RecurringTemplate template,
    RecurringIntervalType? intervalType,
    RecurringIntervalType? interval,
    int intervalCount = 1,
    required DateTime nextRunDate,
    DateTime? endDate,
  }) async {
    await _ensureRecurringEnabled();
    AccessControlService.verifyPermission(
        _currentRole, UserAction.createExpense);

    final effectiveInterval =
        intervalType ?? interval ?? RecurringIntervalType.monthly;
    final ruleId = 'rec_rule_${_uuid.v4().substring(0, 12)}';
    final now = DateTime.now();

    final companion = RecurringRulesCompanion.insert(
      id: ruleId,
      companyId: Value(_currentCompanyId),
      templateJson: template.toJson(),
      intervalType: effectiveInterval.name,
      intervalCount: Value(intervalCount),
      nextRunDate: nextRunDate,
      endDate: Value(endDate),
      isActive: const Value(true),
      createdAt: Value(now),
      updatedAt: Value(now),
      isDeleted: const Value(false),
      syncStatus: const Value(SyncRecordStatus.pending),
    );

    await _db.into(_db.recurringRules).insertOnConflictUpdate(companion);

    final model = RecurringRuleModel(
      id: ruleId,
      companyId: _currentCompanyId,
      template: template,
      intervalType: effectiveInterval,
      intervalCount: intervalCount,
      nextRunDate: nextRunDate,
      endDate: endDate,
      isActive: true,
      createdAt: now,
      updatedAt: now,
      isDeleted: false,
      syncStatus: SyncRecordStatus.pending,
    );

    await _auditService.recordLog(
      companyId: _currentCompanyId,
      userId: _currentUserId,
      entityType: 'recurring_rule',
      entityId: ruleId,
      action: AuditAction.insert,
      newState: model.toMap(),
    );

    await _queueOutbox(
      entityType: 'recurring_rules',
      entityId: ruleId,
      operation: 'insert',
      payload: model.toMap(),
    );

    _notifyUpdates();
    return model;
  }

  Future<RecurringRuleModel> updateRule({
    RecurringRuleModel? rule,
    String? id,
    RecurringTemplate? template,
    RecurringIntervalType? intervalType,
    RecurringIntervalType? interval,
    int? intervalCount,
    DateTime? nextRunDate,
    DateTime? endDate,
    bool? isActive,
  }) async {
    final effectiveId = id ?? rule?.id;
    if (effectiveId == null) throw ArgumentError('Rule id is required');
    final effectiveTemplate = template ?? rule?.template;
    final effectiveInterval =
        intervalType ?? interval ?? rule?.intervalType;
    final effectiveCount = intervalCount ?? rule?.intervalCount;
    final effectiveNextRun = nextRunDate ?? rule?.nextRunDate;
    final effectiveEndDate = endDate ?? rule?.endDate;
    final effectiveActive = isActive ?? rule?.isActive;

    await _ensureRecurringEnabled();
    AccessControlService.verifyPermission(
        _currentRole, UserAction.editExpense);

    final existing = await getRuleById(effectiveId);
    final now = DateTime.now();

    final updated = existing.copyWith(
      template: effectiveTemplate,
      intervalType: effectiveInterval,
      intervalCount: effectiveCount,
      nextRunDate: effectiveNextRun,
      endDate: effectiveEndDate,
      isActive: effectiveActive,
      updatedAt: now,
    );

    await (_db.update(_db.recurringRules)
          ..where((t) =>
              t.id.equals(effectiveId) & t.companyId.equals(_currentCompanyId)))
        .write(RecurringRulesCompanion(
      templateJson: Value(updated.template.toJson()),
      intervalType: Value(updated.intervalType.name),
      intervalCount: Value(updated.intervalCount),
      nextRunDate: Value(updated.nextRunDate),
      endDate: Value(updated.endDate),
      isActive: Value(updated.isActive),
      updatedAt: Value(now),
      syncStatus: const Value(SyncRecordStatus.pending),
    ));

    await _auditService.recordLog(
      companyId: _currentCompanyId,
      userId: _currentUserId,
      entityType: 'recurring_rule',
      entityId: effectiveId,
      action: AuditAction.update,
      oldState: existing.toMap(),
      newState: updated.toMap(),
    );

    await _queueOutbox(
      entityType: 'recurring_rules',
      entityId: effectiveId,
      operation: 'update',
      payload: updated.toMap(),
    );

    _notifyUpdates();
    return updated;
  }

  Future<void> toggleRuleActive(String id, bool isActive) async {
    await updateRule(id: id, isActive: isActive);
  }

  Future<bool> deleteRule(String id) async {
    await _ensureRecurringEnabled();
    AccessControlService.verifyPermission(
        _currentRole, UserAction.editExpense);

    final existing = await getRuleById(id);
    final now = DateTime.now();

    await (_db.update(_db.recurringRules)
          ..where((t) =>
              t.id.equals(id) & t.companyId.equals(_currentCompanyId)))
        .write(RecurringRulesCompanion(
      isDeleted: const Value(true),
      isActive: const Value(false),
      updatedAt: Value(now),
      syncStatus: const Value(SyncRecordStatus.pending),
    ));

    await _auditService.recordLog(
      companyId: _currentCompanyId,
      userId: _currentUserId,
      entityType: 'recurring_rule',
      entityId: id,
      action: AuditAction.delete,
      oldState: existing.toMap(),
      newState: {'id': id, 'isDeleted': true},
    );

    await _queueOutbox(
      entityType: 'recurring_rule',
      entityId: id,
      operation: 'delete',
      payload: {'id': id},
    );

    _notifyUpdates();
    return true;
  }

  Future<RecurringRuleModel> getRuleById(String id) async {
    await _ensureRecurringEnabled();
    final row = await (_db.select(_db.recurringRules)
          ..where((t) =>
              t.id.equals(id) &
              t.companyId.equals(_currentCompanyId) &
              t.isDeleted.equals(false)))
        .getSingleOrNull();

    if (row == null) {
      throw StateError('Recurring rule not found: $id');
    }
    return _ruleFromRow(row);
  }

  Future<List<RecurringRuleModel>> getRules({bool includeInactive = true}) async {
    await _ensureRecurringEnabled();
    final query = _db.select(_db.recurringRules)
      ..where((t) =>
          t.companyId.equals(_currentCompanyId) & t.isDeleted.equals(false))
      ..orderBy([(t) => OrderingTerm.asc(t.nextRunDate)]);

    if (!includeInactive) {
      query.where((t) => t.isActive.equals(true));
    }

    final rows = await query.get();
    return rows.map(_ruleFromRow).toList();
  }

  Stream<List<RecurringRuleModel>> watchRules({bool includeInactive = true}) {
    final query = _db.select(_db.recurringRules)
      ..where((t) =>
          t.companyId.equals(_currentCompanyId) & t.isDeleted.equals(false))
      ..orderBy([(t) => OrderingTerm.asc(t.nextRunDate)]);

    if (!includeInactive) {
      query.where((t) => t.isActive.equals(true));
    }

    return query.watch().map((rows) => rows.map(_ruleFromRow).toList());
  }

  // ==========================================
  // HELPERS
  // ==========================================

  RecurringRuleModel _ruleFromRow(RecurringRuleTableData r) {
    return RecurringRuleModel(
      id: r.id,
      companyId: r.companyId,
      template: RecurringTemplate.fromJson(r.templateJson),
      intervalType: RecurringIntervalType.fromString(r.intervalType),
      intervalCount: r.intervalCount,
      nextRunDate: r.nextRunDate,
      endDate: r.endDate,
      isActive: r.isActive,
      createdAt: r.createdAt,
      updatedAt: r.updatedAt,
      isDeleted: r.isDeleted,
      syncStatus: r.syncStatus,
    );
  }
}
