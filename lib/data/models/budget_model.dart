import '../../core/network/sync_codec.dart';
import '../../data/local/database.dart' show SyncRecordStatus;
import '../../data/models/account_model.dart';

enum BudgetPeriodType {
  weekly,
  monthly,
  yearly;

  static BudgetPeriodType fromString(String val) {
    switch (val.toLowerCase()) {
      case 'weekly':
        return BudgetPeriodType.weekly;
      case 'yearly':
        return BudgetPeriodType.yearly;
      case 'monthly':
      default:
        return BudgetPeriodType.monthly;
    }
  }

  String get displayName {
    switch (this) {
      case BudgetPeriodType.weekly:
        return 'Weekly';
      case BudgetPeriodType.monthly:
        return 'Monthly';
      case BudgetPeriodType.yearly:
        return 'Yearly';
    }
  }
}

class BudgetModel {
  final String id;
  final String companyId;
  final String categoryAccountId;
  final BudgetPeriodType periodType;
  final int amountInCents;
  final DateTime startDate;
  final bool rolloverEnabled;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isDeleted;
  final SyncRecordStatus syncStatus;

  const BudgetModel({
    required this.id,
    required this.companyId,
    required this.categoryAccountId,
    required this.periodType,
    required this.amountInCents,
    required this.startDate,
    this.rolloverEnabled = false,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
    this.isDeleted = false,
    this.syncStatus = SyncRecordStatus.pending,
  });

  int get allocatedInCents => amountInCents;
  BudgetPeriodType get period => periodType;
  String get categoryId => categoryAccountId;

  BudgetModel copyWith({
    String? id,
    String? companyId,
    String? categoryAccountId,
    String? categoryId,
    BudgetPeriodType? periodType,
    BudgetPeriodType? period,
    int? amountInCents,
    int? allocatedInCents,
    DateTime? startDate,
    bool? rolloverEnabled,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isDeleted,
    SyncRecordStatus? syncStatus,
  }) {
    return BudgetModel(
      id: id ?? this.id,
      companyId: companyId ?? this.companyId,
      categoryAccountId:
          categoryAccountId ?? categoryId ?? this.categoryAccountId,
      periodType: periodType ?? period ?? this.periodType,
      amountInCents: amountInCents ?? allocatedInCents ?? this.amountInCents,
      startDate: startDate ?? this.startDate,
      rolloverEnabled: rolloverEnabled ?? this.rolloverEnabled,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isDeleted: isDeleted ?? this.isDeleted,
      syncStatus: syncStatus ?? this.syncStatus,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'companyId': companyId,
      'categoryAccountId': categoryAccountId,
      'periodType': periodType.name,
      'amountInCents': amountInCents,
      'startDate': encodeTime(startDate),
      'rolloverEnabled': rolloverEnabled,
      'isActive': isActive,
      'createdAt': encodeTime(createdAt),
      'updatedAt': encodeTime(updatedAt),
      'isDeleted': isDeleted,
      'syncStatus': syncStatus.name,
    };
  }

  factory BudgetModel.fromMap(Map<String, dynamic> map) {
    return BudgetModel(
      id: map['id'] as String,
      companyId: map['companyId'] as String? ?? 'cmp_default',
      categoryAccountId: (map['categoryAccountId'] ?? map['category_account_id'] ?? '') as String,
      periodType: BudgetPeriodType.fromString((map['periodType'] ?? map['period_type']) as String? ?? 'monthly'),
      amountInCents: (map['amountInCents'] ?? map['amount_in_cents'] as int?) ?? 0,
      startDate: decodeTime(map['startDate'] ?? map['start_date']),
      rolloverEnabled: (map['rolloverEnabled'] ?? map['rollover_enabled'] as bool?) ?? false,
      isActive: (map['isActive'] ?? map['is_active'] as bool?) ?? true,
      createdAt: decodeTime(map['createdAt'] ?? map['created_at']),
      updatedAt: decodeTime(map['updatedAt'] ?? map['updated_at']),
      isDeleted: (map['isDeleted'] ?? map['is_deleted'] as bool?) ?? false,
      syncStatus: SyncRecordStatus.values.firstWhere(
        (s) => s.name == map['syncStatus'],
        orElse: () => SyncRecordStatus.pending,
      ),
    );
  }
}

/// Computed status and spending progress for a specific budget.
class BudgetProgress {
  final BudgetModel budget;
  final AccountModel? category;
  final int baseAllocatedInCents;
  final int rolloverInCents;
  final int effectiveAllocatedInCents;
  final int spentInCents;
  final int remainingInCents;
  final double percentUsed;
  final DateTime periodStartDate;
  final DateTime periodEndDate;

  const BudgetProgress({
    required this.budget,
    this.category,
    required this.baseAllocatedInCents,
    required this.rolloverInCents,
    required this.effectiveAllocatedInCents,
    required this.spentInCents,
    required this.remainingInCents,
    required this.percentUsed,
    required this.periodStartDate,
    required this.periodEndDate,
  });

  bool get isWarning => percentUsed >= 80.0 && percentUsed < 100.0;
  bool get isExceeded => percentUsed >= 100.0;
  String get categoryName => category?.name ?? 'Category';
}

/// Overall aggregated monthly budget summary.
class OverallBudgetSummary {
  final int totalAllocatedInCents;
  final int totalSpentInCents;
  final int totalRemainingInCents;
  final double overallPercentUsed;
  final List<BudgetProgress> items;

  const OverallBudgetSummary({
    required this.totalAllocatedInCents,
    required this.totalSpentInCents,
    required this.totalRemainingInCents,
    required this.overallPercentUsed,
    required this.items,
  });

  int get remainingInCents => totalRemainingInCents;
  double get percentUsed => overallPercentUsed;
  bool get isWarning => overallPercentUsed >= 80.0 && overallPercentUsed < 100.0;
  bool get isExceeded => overallPercentUsed >= 100.0;

  factory OverallBudgetSummary.empty() => const OverallBudgetSummary(
        totalAllocatedInCents: 0,
        totalSpentInCents: 0,
        totalRemainingInCents: 0,
        overallPercentUsed: 0.0,
        items: [],
      );
}
