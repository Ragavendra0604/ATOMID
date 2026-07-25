import 'package:hive_ce/hive.dart';

part 'inventory_movement_model.g.dart';

@HiveType(typeId: 4)
class InventoryMovement extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String productId;

  @HiveField(2)
  String productName;

  @HiveField(3)
  String variantBarcode;

  @HiveField(4)
  String variantSize;

  @HiveField(5)
  int quantity;

  @HiveField(6)
  String type; // 'Stock In' or 'Stock Out'

  @HiveField(7)
  String reason;

  @HiveField(8)
  DateTime date;

  @HiveField(9)
  String movementReferenceId;

  @HiveField(10)
  String performedAt;

  InventoryMovement({
    required this.id,
    required this.productId,
    required this.productName,
    required this.variantBarcode,
    required this.variantSize,
    required this.quantity,
    required this.type,
    required this.reason,
    required this.date,
    this.movementReferenceId = '',
    this.performedAt = '',
  });
}
