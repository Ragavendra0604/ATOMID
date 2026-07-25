import 'package:hive_ce/hive.dart';
import 'package:uuid/uuid.dart';

part 'activity_log_model.g.dart';

@HiveType(typeId: 64)
class ActivityLogModel extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final DateTime timestamp;

  @HiveField(2)
  final String action;

  @HiveField(3)
  final String ownerId;

  @HiveField(4)
  final String targetEmployeeId;

  @HiveField(5)
  final bool isSynced;

  ActivityLogModel({
    String? id,
    required this.timestamp,
    required this.action,
    required this.ownerId,
    required this.targetEmployeeId,
    this.isSynced = false,
  }) : id = id ?? const Uuid().v4();
}
