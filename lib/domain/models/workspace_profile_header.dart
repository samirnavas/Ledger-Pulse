import 'package:flutter/foundation.dart';

enum ProfileType {
  expense,
  ledger;

  static ProfileType fromString(String val) {
    final lower = val.toLowerCase().trim();
    if (lower == 'expense' || lower == 'expensetracker') return ProfileType.expense;
    return ProfileType.ledger;
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

