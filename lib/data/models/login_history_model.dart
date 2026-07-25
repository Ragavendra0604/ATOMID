import 'package:hive_ce/hive.dart';
import 'package:uuid/uuid.dart';

part 'login_history_model.g.dart';

@HiveType(typeId: 63)
class LoginHistoryModel extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String employeeId;

  @HiveField(2)
  final DateTime loginTime;

  @HiveField(3)
  final String deviceInfo;

  @HiveField(4)
  final String ipAddress;

  @HiveField(5)
  final bool isSynced;

  LoginHistoryModel({
    String? id,
    required this.employeeId,
    required this.loginTime,
    required this.deviceInfo,
    required this.ipAddress,
    this.isSynced = false,
  }) : id = id ?? const Uuid().v4();
}
