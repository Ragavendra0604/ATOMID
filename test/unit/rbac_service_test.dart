import 'package:flutter_test/flutter_test.dart';
import 'package:atomid/core/services/rbac_service.dart';
import 'package:atomid/data/models/employee_model.dart';
import 'package:atomid/data/models/role_model.dart';
import 'package:atomid/data/models/permission_model.dart';

void main() {
  group('RbacService Tests', () {
    test('Owner has all permissions automatically', () {
      final owner = EmployeeModel(
        fullName: 'Owner',
        email: 'owner@test.com',
        phoneNumber: '123456',
        role: Role.owner,
        permissions: [], // Empty permissions
      );

      expect(RbacService.hasPermission(owner, Permission.createProducts), isTrue);
      expect(RbacService.isOwner(owner), isTrue);
      expect(RbacService.canManageEmployees(owner), isTrue);
    });

    test('Cashier without explicit permission is denied', () {
      final cashier = EmployeeModel(
        fullName: 'Cashier',
        email: 'cashier@test.com',
        phoneNumber: '123456',
        role: Role.cashier,
        permissions: [Permission.createSales],
      );

      expect(RbacService.hasPermission(cashier, Permission.createSales), isTrue);
      expect(RbacService.hasPermission(cashier, Permission.deleteProducts), isFalse);
      expect(RbacService.isOwner(cashier), isFalse);
      expect(RbacService.canManageEmployees(cashier), isFalse);
    });

    test('Inactive user is denied all permissions', () {
      final inactiveManager = EmployeeModel(
        fullName: 'Manager',
        email: 'manager@test.com',
        phoneNumber: '123456',
        role: Role.manager,
        isActive: false,
        permissions: [Permission.manageEmployees],
      );

      expect(RbacService.hasPermission(inactiveManager, Permission.manageEmployees), isFalse);
    });
  });
}
