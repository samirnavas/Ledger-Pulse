enum Role {
  admin,
  accountant,
  salesStaff,
  purchaseStaff,
  warehouseOperator;

  String get displayName {
    switch (this) {
      case Role.admin:
        return 'Admin';
      case Role.accountant:
        return 'Accountant';
      case Role.salesStaff:
        return 'Sales Staff';
      case Role.purchaseStaff:
        return 'Purchase Staff';
      case Role.warehouseOperator:
        return 'Warehouse Operator';
    }
  }

  String get description {
    switch (this) {
      case Role.admin:
        return 'Full access to all company records, configuration, and security settings.';
      case Role.accountant:
        return 'Full ledger, parties, entries, vouchers, statements, and audit log inspection.';
      case Role.salesStaff:
        return 'Manage customer parties and sales transactions.';
      case Role.purchaseStaff:
        return 'Manage supplier parties and purchase transactions.';
      case Role.warehouseOperator:
        return 'View stock, parties, and deliveries with read-only ledger access.';
    }
  }
}

enum UserAction {
  // Party actions
  viewParties,
  createCustomerParty,
  createSupplierParty,
  updateCustomerParty,
  updateSupplierParty,
  deleteParty,

  // Ledger entry actions
  viewLedgerEntries,
  createCustomerEntry,
  createSupplierEntry,
  updateEntry,
  voidEntry,
  deleteEntry,

  // Reports & Auditing
  viewReports,
  exportStatements,
  viewAuditLogs,
  verifyAuditIntegrity,

  // Company & Sync Management
  createCompany,
  editCompanySettings,
  manageUsersAndRoles,
  configureSync,
  triggerSync,
}

class UserCompanyRole {
  final String companyId;
  final Role role;

  const UserCompanyRole({
    required this.companyId,
    required this.role,
  });

  Map<String, dynamic> toMap() {
    return {
      'companyId': companyId,
      'role': role.name,
    };
  }

  factory UserCompanyRole.fromMap(Map<String, dynamic> map) {
    return UserCompanyRole(
      companyId: map['companyId'] as String,
      role: Role.values.byName(map['role'] as String),
    );
  }
}
