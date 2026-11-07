import 'package:flutter/foundation.dart';

enum ExpenseCategoryType {
  expense,
  income;

  static ExpenseCategoryType fromString(String val) {
    if (val.toLowerCase().trim() == 'income') return ExpenseCategoryType.income;
    return ExpenseCategoryType.expense;
  }

  String toDbValue() => name;
}

@immutable
class ExpenseCategoryModel {
  final String id;
  final String profileId;
  final String name;
  final ExpenseCategoryType categoryType;
  final String? parentCategoryId;
  final String? iconName;
  final String? colorHex;
  final bool isSystem;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isDeleted;

  const ExpenseCategoryModel({
    required this.id,
    required this.profileId,
    required this.name,
    this.categoryType = ExpenseCategoryType.expense,
    this.parentCategoryId,
    this.iconName,
    this.colorHex,
    this.isSystem = false,
    required this.createdAt,
    required this.updatedAt,
    this.isDeleted = false,
  });

  bool get isIncome => categoryType == ExpenseCategoryType.income;
  bool get isExpense => categoryType == ExpenseCategoryType.expense;

  ExpenseCategoryModel copyWith({
    String? id,
    String? profileId,
    String? name,
    ExpenseCategoryType? categoryType,
    String? parentCategoryId,
    String? iconName,
    String? colorHex,
    bool? isSystem,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isDeleted,
  }) {
    return ExpenseCategoryModel(
      id: id ?? this.id,
      profileId: profileId ?? this.profileId,
      name: name ?? this.name,
      categoryType: categoryType ?? this.categoryType,
      parentCategoryId: parentCategoryId ?? this.parentCategoryId,
      iconName: iconName ?? this.iconName,
      colorHex: colorHex ?? this.colorHex,
      isSystem: isSystem ?? this.isSystem,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }
}

