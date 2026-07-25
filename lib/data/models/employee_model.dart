import 'package:hive_ce/hive.dart';
import 'package:uuid/uuid.dart';
import 'role_model.dart';
import 'permission_model.dart';

part 'employee_model.g.dart';

@HiveType(typeId: 60)
class EmployeeModel extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String fullName;

  @HiveField(2)
  final String? profilePicture;

  @HiveField(3)
  final String email;

  @HiveField(4)
  final String phoneNumber;

  @HiveField(5)
  final Role role;

  @HiveField(6)
  final List<Permission> permissions;

  @HiveField(7)
  final String? pin;

  @HiveField(8)
  final bool isActive;

  @HiveField(9)
  final DateTime dateJoined;

  @HiveField(10)
  final DateTime? lastLogin;

  @HiveField(11)
  final String? createdBy;

  @HiveField(12)
  final String? updatedBy;

  @HiveField(13)
  final bool isDeleted;

  @HiveField(14)
  final bool isSynced;

  EmployeeModel({
    String? id,
    required this.fullName,
    this.profilePicture,
    required this.email,
    required this.phoneNumber,
    required this.role,
    required this.permissions,
    this.pin,
    this.isActive = true,
    DateTime? dateJoined,
    this.lastLogin,
    this.createdBy,
    this.updatedBy,
    this.isDeleted = false,
    this.isSynced = false,
  })  : id = id ?? const Uuid().v4(),
        dateJoined = dateJoined ?? DateTime.now();

  EmployeeModel copyWith({
    String? fullName,
    String? profilePicture,
    String? email,
    String? phoneNumber,
    Role? role,
    List<Permission>? permissions,
    String? pin,
    bool? isActive,
    DateTime? lastLogin,
    String? updatedBy,
    bool? isDeleted,
    bool? isSynced,
  }) {
    return EmployeeModel(
      id: id,
      fullName: fullName ?? this.fullName,
      profilePicture: profilePicture ?? this.profilePicture,
      email: email ?? this.email,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      role: role ?? this.role,
      permissions: permissions ?? this.permissions,
      pin: pin ?? this.pin,
      isActive: isActive ?? this.isActive,
      dateJoined: dateJoined,
      lastLogin: lastLogin ?? this.lastLogin,
      createdBy: createdBy,
      updatedBy: updatedBy ?? this.updatedBy,
      isDeleted: isDeleted ?? this.isDeleted,
      isSynced: isSynced ?? this.isSynced,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'fullName': fullName,
      'profilePicture': profilePicture,
      'email': email,
      'phoneNumber': phoneNumber,
      'role': role.index,
      'permissions': permissions.map((e) => e.index).toList(),
      'pin': pin,
      'isActive': isActive,
      'dateJoined': dateJoined.toIso8601String(),
      'lastLogin': lastLogin?.toIso8601String(),
      'createdBy': createdBy,
      'updatedBy': updatedBy,
      'isDeleted': isDeleted,
      'isSynced': isSynced,
    };
  }

  factory EmployeeModel.fromJson(Map<String, dynamic> json) {
    return EmployeeModel(
      id: json['id'],
      fullName: json['fullName'],
      profilePicture: json['profilePicture'],
      email: json['email'],
      phoneNumber: json['phoneNumber'],
      role: Role.values[json['role'] as int],
      permissions: (json['permissions'] as List<dynamic>)
          .map((e) => Permission.values[e as int])
          .toList(),
      pin: json['pin'],
      isActive: json['isActive'],
      dateJoined: DateTime.parse(json['dateJoined']),
      lastLogin: json['lastLogin'] != null
          ? DateTime.parse(json['lastLogin'])
          : null,
      createdBy: json['createdBy'],
      updatedBy: json['updatedBy'],
      isDeleted: json['isDeleted'] ?? false,
      isSynced: json['isSynced'] ?? false,
    );
  }
}
