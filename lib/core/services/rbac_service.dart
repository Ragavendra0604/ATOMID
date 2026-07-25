import 'package:atomid/data/models/employee_model.dart';
import 'package:atomid/data/models/permission_model.dart';
import 'package:atomid/data/models/role_model.dart';

class RbacService {
  /// Checks if the employee has the specific permission.
  /// Owners automatically have all permissions.
  static bool hasPermission(EmployeeModel employee, Permission requiredPermission) {
    if (employee.role == Role.owner) {
      return true; // Owners have omnipotent access
    }

    if (!employee.isActive || employee.isDeleted) {
      return false; // Inactive or deleted users have no access
    }

    return employee.permissions.contains(requiredPermission);
  }

  /// Checks if the employee can manage another employee.
  /// Only Owners can manage (create/edit/delete/assign roles to) other employees.
  static bool canManageEmployees(EmployeeModel employee) {
    return employee.role == Role.owner || employee.permissions.contains(Permission.manageEmployees);
  }

  /// A strict check ensuring only the true Owner role can access this.
  static bool isOwner(EmployeeModel employee) {
    return employee.role == Role.owner;
  }
}
