import '../models/rbac_model.dart';

class RbacException implements Exception {
  final String message;
  final Role role;
  final UserAction action;

  const RbacException({
    required this.message,
    required this.role,
    required this.action,
  });

  @override
  String toString() => 'RbacException: [$role] is not authorized to execute [$action]. Reason: $message';
}

class AccessControlService {
  static final Map<Role, Set<UserAction>> _permissions = {
    Role.admin: {
      UserAction.viewParties,
      UserAction.createCustomerParty,
      UserAction.createSupplierParty,
      UserAction.updateCustomerParty,
      UserAction.updateSupplierParty,
      UserAction.deleteParty,
      UserAction.viewLedgerEntries,
      UserAction.createCustomerEntry,
      UserAction.createSupplierEntry,
      UserAction.updateEntry,
      UserAction.voidEntry,
      UserAction.deleteEntry,
      UserAction.viewReports,
      UserAction.exportStatements,
      UserAction.viewAuditLogs,
      UserAction.verifyAuditIntegrity,
      UserAction.createCompany,
      UserAction.editCompanySettings,
      UserAction.manageUsersAndRoles,
      UserAction.configureSync,
      UserAction.triggerSync,
    },
    Role.accountant: {
      UserAction.viewParties,
      UserAction.createCustomerParty,
      UserAction.createSupplierParty,
      UserAction.updateCustomerParty,
      UserAction.updateSupplierParty,
      UserAction.viewLedgerEntries,
      UserAction.createCustomerEntry,
      UserAction.createSupplierEntry,
      UserAction.updateEntry,
      UserAction.voidEntry,
      UserAction.viewReports,
      UserAction.exportStatements,
      UserAction.viewAuditLogs,
      UserAction.verifyAuditIntegrity,
      UserAction.triggerSync,
    },
    Role.salesStaff: {
      UserAction.viewParties,
      UserAction.createCustomerParty,
      UserAction.updateCustomerParty,
      UserAction.viewLedgerEntries,
      UserAction.createCustomerEntry,
      UserAction.viewReports,
      UserAction.exportStatements,
    },
    Role.purchaseStaff: {
      UserAction.viewParties,
      UserAction.createSupplierParty,
      UserAction.updateSupplierParty,
      UserAction.viewLedgerEntries,
      UserAction.createSupplierEntry,
      UserAction.viewReports,
      UserAction.exportStatements,
    },
    Role.warehouseOperator: {
      UserAction.viewParties,
      UserAction.viewLedgerEntries,
    },
  };

  /// Checks whether a given [role] is permitted to perform [action].
  static bool hasPermission(Role role, UserAction action) {
    final rolePerms = _permissions[role];
    if (rolePerms == null) return false;
    return rolePerms.contains(action);
  }

  /// Asserts permission or throws an [RbacException].
  static void verifyPermission(Role role, UserAction action) {
    if (!hasPermission(role, action)) {
      throw RbacException(
        message: 'Permission denied for action "${action.name}" with role "${role.displayName}".',
        role: role,
        action: action,
      );
    }
  }
}
