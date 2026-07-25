import 'package:hive_ce/hive.dart';

part 'sync_queue_model.g.dart';

@HiveType(typeId: 30)
class SyncQueueItem extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String entityType; // e.g., 'Customer', 'Sale', 'LoyaltyTransaction'

  @HiveField(2)
  String entityId;

  @HiveField(3)
  String action; // 'CREATE', 'UPDATE', 'DELETE'

  @HiveField(4)
  String status; // 'PENDING', 'SYNCING', 'COMPLETED', 'FAILED'

  @HiveField(5)
  String? payload; // JSON serialized string of the object (optional)

  @HiveField(6)
  int retryCount;

  @HiveField(7)
  DateTime createdAt;

  @HiveField(8)
  DateTime? lastAttempt;

  @HiveField(9)
  int priority; // Lower number = higher priority

  SyncQueueItem({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.action,
    required this.status,
    this.payload,
    required this.retryCount,
    required this.createdAt,
    this.lastAttempt,
    this.priority = 10,
  });
}
