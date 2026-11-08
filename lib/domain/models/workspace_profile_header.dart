import 'package:flutter/foundation.dart';
import '../../data/models/company_mode.dart';

export '../../data/models/company_mode.dart' show UnknownProfileTypeException;

enum ProfileType {
  expense,
  ledger;

  /// Canonical wire/persistence string representation for Expense profiles.
  static const String canonicalExpense = CompanyMode.canonicalExpense;

  /// Canonical wire/persistence string representation for Ledger profiles.
  static const String canonicalLedger = CompanyMode.canonicalLedger;

  /// Returns the canonical string representation for persistence and wire serialization.
  String get canonicalValue {
    switch (this) {
      case ProfileType.expense:
        return canonicalExpense;
      case ProfileType.ledger:
        return canonicalLedger;
    }
  }

  /// Parses a string into a [ProfileType], recognizing canonical and legacy values:
  /// - Expense: 'expense', 'expenseTracker', 'expense_tracker'
  /// - Ledger: 'ledger'
  ///
  /// Returns `null` if the value is unrecognized or null.
  static ProfileType? tryParse(String? val) {
    final mode = CompanyMode.tryParse(val);
    if (mode == null) return null;
    switch (mode) {
      case CompanyMode.expenseTracker:
        return ProfileType.expense;
      case CompanyMode.ledger:
        return ProfileType.ledger;
    }
  }

  /// Parses a string into a [ProfileType], recognizing canonical and legacy values.
  ///
  /// Does NOT silently interpret unknown or null values as Ledger.
  /// If [val] is unrecognized and [fallback] is provided, returns [fallback].
  /// Otherwise, throws [UnknownProfileTypeException].
  static ProfileType fromString(String? val, {ProfileType? fallback}) {
    final parsed = tryParse(val);
    if (parsed != null) return parsed;
    if (fallback != null) return fallback;
    throw UnknownProfileTypeException(val);
  }

  /// Converts this [ProfileType] into its corresponding [CompanyMode].
  CompanyMode toCompanyMode() {
    switch (this) {
      case ProfileType.expense:
        return CompanyMode.expenseTracker;
      case ProfileType.ledger:
        return CompanyMode.ledger;
    }
  }
}

enum ProfileRole {
  owner,
  admin,
  editor,
  viewer;

  String get displayName {
    switch (this) {
      case ProfileRole.owner:
        return 'Owner';
      case ProfileRole.admin:
        return 'Administrator';
      case ProfileRole.editor:
        return 'Editor';
      case ProfileRole.viewer:
        return 'Viewer';
    }
  }

  static ProfileRole fromString(String val) {
    switch (val.toLowerCase().trim()) {
      case 'owner':
        return ProfileRole.owner;
      case 'admin':
        return ProfileRole.admin;
      case 'editor':
        return ProfileRole.editor;
      case 'viewer':
      default:
        return ProfileRole.viewer;
    }
  }
}

@immutable
class WorkspaceProfileHeader {
  final String id;
  final String name;
  final String legalName;
  final ProfileType type;
  final ProfileRole role;
  final String currencyCode;
  final String? gstin;
  final bool isActive;
  final DateTime updatedAt;

  const WorkspaceProfileHeader({
    required this.id,
    required this.name,
    required this.legalName,
    required this.type,
    required this.role,
    this.currencyCode = 'INR',
    this.gstin,
    this.isActive = true,
    required this.updatedAt,
  });

  bool get isExpense => type == ProfileType.expense;
  bool get isLedger => type == ProfileType.ledger;

  WorkspaceProfileHeader copyWith({
    String? id,
    String? name,
    String? legalName,
    ProfileType? type,
    ProfileRole? role,
    String? currencyCode,
    String? gstin,
    bool? isActive,
    DateTime? updatedAt,
  }) {
    return WorkspaceProfileHeader(
      id: id ?? this.id,
      name: name ?? this.name,
      legalName: legalName ?? this.legalName,
      type: type ?? this.type,
      role: role ?? this.role,
      currencyCode: currencyCode ?? this.currencyCode,
      gstin: gstin ?? this.gstin,
      isActive: isActive ?? this.isActive,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

