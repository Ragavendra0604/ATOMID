import 'package:hive_ce/hive.dart';

part 'loyalty_transaction_model.g.dart';

@HiveType(typeId: 20)
class LoyaltyTransaction extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String customerId;

  @HiveField(2)
  String? saleId;

  @HiveField(3)
  String transactionType; // Earn, Redeem, Refund, Expire, ManualAdjustment

  @HiveField(4)
  double points;

  @HiveField(5)
  double monetaryValue;

  @HiveField(6)
  String reference;

  @HiveField(7)
  String remarks;

  @HiveField(8)
  DateTime createdDate;

  @HiveField(9)
  String createdBy;

  @HiveField(10)
  bool isSynced;

  @HiveField(11)
  DateTime? updatedAt;

  @HiveField(12)
  int version;

  @HiveField(13)
  String deviceId;

  @HiveField(14)
  bool isDeleted;

  @HiveField(15)
  DateTime? lastSyncedAt;

  LoyaltyTransaction({
    required this.id,
    required this.customerId,
    this.saleId,
    required this.transactionType,
    required this.points,
    required this.monetaryValue,
    this.reference = '',
    this.remarks = '',
    required this.createdDate,
    required this.createdBy,
    this.isSynced = false,
    this.updatedAt,
    this.version = 1,
    this.deviceId = '',
    this.isDeleted = false,
    this.lastSyncedAt,
  });
}
