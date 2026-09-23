import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_pulse/data/models/rbac_model.dart';
import 'package:ledger_pulse/data/security/access_control_service.dart';

void main() {
  group('RBAC AccessControlService Tests', () {
    test('Admin role has permission for all system actions', () {
      for (final action in UserAction.values) {
        expect(
          AccessControlService.hasPermission(Role.admin, action),
          isTrue,
          reason: 'Admin must have permission for $action',
        );
        expect(
          () => AccessControlService.verifyPermission(Role.admin, action),
          returnsNormally,
        );
      }
    });

    test('Accountant role has ledger, party, and report access but cannot delete company or manage users', () {
      expect(AccessControlService.hasPermission(Role.accountant, UserAction.createCustomerParty), isTrue);
      expect(AccessControlService.hasPermission(Role.accountant, UserAction.createSupplierParty), isTrue);
      expect(AccessControlService.hasPermission(Role.accountant, UserAction.createCustomerEntry), isTrue);
      expect(AccessControlService.hasPermission(Role.accountant, UserAction.updateEntry), isTrue);
      expect(AccessControlService.hasPermission(Role.accountant, UserAction.voidEntry), isTrue);
      expect(AccessControlService.hasPermission(Role.accountant, UserAction.viewAuditLogs), isTrue);

      // Blocked actions
      expect(AccessControlService.hasPermission(Role.accountant, UserAction.createCompany), isFalse);
      expect(AccessControlService.hasPermission(Role.accountant, UserAction.manageUsersAndRoles), isFalse);
      expect(AccessControlService.hasPermission(Role.accountant, UserAction.deleteParty), isFalse);

      expect(
        () => AccessControlService.verifyPermission(Role.accountant, UserAction.createCompany),
        throwsA(isA<RbacException>()),
      );
    });

    test('Sales Staff role is limited to customer operations only', () {
      // Allowed
      expect(AccessControlService.hasPermission(Role.salesStaff, UserAction.viewParties), isTrue);
      expect(AccessControlService.hasPermission(Role.salesStaff, UserAction.createCustomerParty), isTrue);
      expect(AccessControlService.hasPermission(Role.salesStaff, UserAction.updateCustomerParty), isTrue);
      expect(AccessControlService.hasPermission(Role.salesStaff, UserAction.createCustomerEntry), isTrue);
      expect(AccessControlService.hasPermission(Role.salesStaff, UserAction.viewReports), isTrue);

      // Blocked
      expect(AccessControlService.hasPermission(Role.salesStaff, UserAction.createSupplierParty), isFalse);
      expect(AccessControlService.hasPermission(Role.salesStaff, UserAction.createSupplierEntry), isFalse);
      expect(AccessControlService.hasPermission(Role.salesStaff, UserAction.deleteParty), isFalse);
      expect(AccessControlService.hasPermission(Role.salesStaff, UserAction.voidEntry), isFalse);
      expect(AccessControlService.hasPermission(Role.salesStaff, UserAction.viewAuditLogs), isFalse);

      expect(
        () => AccessControlService.verifyPermission(Role.salesStaff, UserAction.createSupplierParty),
        throwsA(isA<RbacException>()),
      );
    });

    test('Purchase Staff role is limited to supplier operations only', () {
      // Allowed
      expect(AccessControlService.hasPermission(Role.purchaseStaff, UserAction.viewParties), isTrue);
      expect(AccessControlService.hasPermission(Role.purchaseStaff, UserAction.createSupplierParty), isTrue);
      expect(AccessControlService.hasPermission(Role.purchaseStaff, UserAction.updateSupplierParty), isTrue);
      expect(AccessControlService.hasPermission(Role.purchaseStaff, UserAction.createSupplierEntry), isTrue);

      // Blocked
      expect(AccessControlService.hasPermission(Role.purchaseStaff, UserAction.createCustomerParty), isFalse);
      expect(AccessControlService.hasPermission(Role.purchaseStaff, UserAction.createCustomerEntry), isFalse);
      expect(AccessControlService.hasPermission(Role.purchaseStaff, UserAction.deleteParty), isFalse);

      expect(
        () => AccessControlService.verifyPermission(Role.purchaseStaff, UserAction.createCustomerParty),
        throwsA(isA<RbacException>()),
      );
    });

    test('Warehouse Operator role has read-only access and no mutation permissions', () {
      expect(AccessControlService.hasPermission(Role.warehouseOperator, UserAction.viewParties), isTrue);
      expect(AccessControlService.hasPermission(Role.warehouseOperator, UserAction.viewLedgerEntries), isTrue);

      expect(AccessControlService.hasPermission(Role.warehouseOperator, UserAction.createCustomerParty), isFalse);
      expect(AccessControlService.hasPermission(Role.warehouseOperator, UserAction.createCustomerEntry), isFalse);
      expect(AccessControlService.hasPermission(Role.warehouseOperator, UserAction.updateEntry), isFalse);

      expect(
        () => AccessControlService.verifyPermission(Role.warehouseOperator, UserAction.createCustomerEntry),
        throwsA(isA<RbacException>()),
      );
    });
  });
}
