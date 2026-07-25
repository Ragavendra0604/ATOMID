import 'package:hive_ce/hive.dart';

part 'sync_log_model.g.dart';

@HiveType(typeId: 40)
class SyncLogModel extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String entityType;

  @HiveField(2)
  String entityId;

  @HiveField(3)
  String operation; // CREATE, UPDATE, DELETE

  @HiveField(4)
  String deviceId;

  @HiveField(5)
  DateTime startedAt;

  @HiveField(6)
  DateTime completedAt;

  @HiveField(7)
  int durationMs;

  @HiveField(8)
  String status; // SUCCESS, FAILED

  @HiveField(9)
  int retryCount;

  @HiveField(10)
  String? error;

  SyncLogModel({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.operation,
    required this.deviceId,
    required this.startedAt,
    required this.completedAt,
    required this.durationMs,
    required this.status,
    required this.retryCount,
    this.error,
  });
}
