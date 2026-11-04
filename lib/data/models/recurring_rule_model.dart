import 'dart:convert';
import '../../core/network/sync_codec.dart';
import 'package:flutter/foundation.dart';
import '../../data/local/database.dart' show SyncRecordStatus;
import '../../data/models/voucher_model.dart';

enum RecurringIntervalType {
  daily,
  weekly,
  monthly,
  yearly;

  static RecurringIntervalType fromString(String val) {
    switch (val.toLowerCase()) {
      case 'daily':
        return RecurringIntervalType.daily;
      case 'weekly':
        return RecurringIntervalType.weekly;
      case 'yearly':
        return RecurringIntervalType.yearly;
      case 'monthly':
      default:
        return RecurringIntervalType.monthly;
    }
  }

  String get displayName {
    switch (this) {
      case RecurringIntervalType.daily:
        return 'Daily';
      case RecurringIntervalType.weekly:
        return 'Weekly';
      case RecurringIntervalType.monthly:
        return 'Monthly';
      case RecurringIntervalType.yearly:
        return 'Yearly';
    }
  }
}

/// Template data used to post the recurring voucher when due.
@immutable
class RecurringTemplate {
  final VoucherType type;
  final int amountInCents;
  final String? categoryAccountId;
  final String? walletAccountId;
  final String? toWalletAccountId;
  final String? narration;
  final String? referenceNumber;
  final String? receiptPhotoUrl;

  const RecurringTemplate({
    required this.type,
    required this.amountInCents,
    this.categoryAccountId,
    this.walletAccountId,
    this.toWalletAccountId,
    String? narration,
    this.referenceNumber,
    this.receiptPhotoUrl,
    String? notes,
  }) : narration = narration ?? notes;

  String? get notes => narration;

  Map<String, dynamic> toMap() {
    return {
      'type': type.name,
      'amountInCents': amountInCents,
      'categoryAccountId': categoryAccountId,
      'walletAccountId': walletAccountId,
      'toWalletAccountId': toWalletAccountId,
      'narration': narration,
      'referenceNumber': referenceNumber,
      'receiptPhotoUrl': receiptPhotoUrl,
    };
  }

  factory RecurringTemplate.fromMap(Map<String, dynamic> map) {
    return RecurringTemplate(
      type: VoucherType.values.firstWhere(
        (t) => t.name == map['type'],
        orElse: () => VoucherType.expense,
      ),
      amountInCents: map['amountInCents'] as int? ?? 0,
      categoryAccountId: map['categoryAccountId'] as String?,
      walletAccountId: map['walletAccountId'] as String?,
      toWalletAccountId: map['toWalletAccountId'] as String?,
      narration: map['narration'] as String?,
      referenceNumber: map['referenceNumber'] as String?,
      receiptPhotoUrl: map['receiptPhotoUrl'] as String?,
    );
  }

  String toJson() => jsonEncode(toMap());

  factory RecurringTemplate.fromJson(String source) =>
      RecurringTemplate.fromMap(jsonDecode(source) as Map<String, dynamic>);
}

/// Model representing a recurring transaction generation rule.
@immutable
class RecurringRuleModel {
  final String id;
  final String companyId;
  final RecurringTemplate template;
  final RecurringIntervalType intervalType;
  final int intervalCount;
  final DateTime nextRunDate;
  final DateTime? endDate;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isDeleted;
  final SyncRecordStatus syncStatus;

  const RecurringRuleModel({
    required this.id,
    required this.companyId,
    required this.template,
    required this.intervalType,
    this.intervalCount = 1,
    required this.nextRunDate,
    this.endDate,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
    this.isDeleted = false,
    this.syncStatus = SyncRecordStatus.pending,
  });

  RecurringIntervalType get interval => intervalType;

  RecurringRuleModel copyWith({
    String? id,
    String? companyId,
    RecurringTemplate? template,
    RecurringIntervalType? intervalType,
    RecurringIntervalType? interval,
    int? intervalCount,
    DateTime? nextRunDate,
    DateTime? endDate,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isDeleted,
    SyncRecordStatus? syncStatus,
  }) {
    return RecurringRuleModel(
      id: id ?? this.id,
      companyId: companyId ?? this.companyId,
      template: template ?? this.template,
      intervalType: intervalType ?? interval ?? this.intervalType,
      intervalCount: intervalCount ?? this.intervalCount,
      nextRunDate: nextRunDate ?? this.nextRunDate,
      endDate: endDate ?? this.endDate,
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
      'templateJson': template.toJson(),
      'intervalType': intervalType.name,
      'intervalCount': intervalCount,
      'nextRunDate': encodeTime(nextRunDate),
      'endDate': endDate != null ? encodeTime(endDate!) : null,
      'isActive': isActive,
      'createdAt': encodeTime(createdAt),
      'updatedAt': encodeTime(updatedAt),
      'isDeleted': isDeleted,
      'syncStatus': syncStatus.name,
    };
  }

  factory RecurringRuleModel.fromMap(Map<String, dynamic> map) {
    return RecurringRuleModel(
      id: map['id'] as String,
      companyId: map['companyId'] as String? ?? 'cmp_default',
      template: RecurringTemplate.fromJson((map['templateJson'] ?? map['template_json']) as String),
      intervalType: RecurringIntervalType.fromString((map['intervalType'] ?? map['interval_type']) as String? ?? 'monthly'),
      intervalCount: (map['intervalCount'] ?? map['interval_count'] as int?) ?? 1,
      nextRunDate: decodeTime(map['nextRunDate'] ?? map['next_run_date']),
      endDate: map['endDate'] != null || map['end_date'] != null
          ? decodeTime(map['endDate'] ?? map['end_date'])
          : null,
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
