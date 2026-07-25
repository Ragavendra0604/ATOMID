import 'package:hive_ce/hive.dart';

part 'sale_model.g.dart';

@HiveType(typeId: 6)
class Sale extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String invoiceNumber;

  @HiveField(2)
  DateTime date;

  @HiveField(3)
  String customerId;

  @HiveField(12) // newly added
  String customerName;

  @HiveField(4)
  List<SaleItem> items;

  @HiveField(5)
  double subtotal;

  @HiveField(6)
  double discountPercent;

  @HiveField(7)
  double discountAmount;

  @HiveField(8)
  double taxAmount;

  @HiveField(9)
  double grandTotal;

  @HiveField(10)
  String paymentMethod;

  @HiveField(11)
  String notes;

  @HiveField(13)
  double rewardDiscountAmount;

  @HiveField(14)
  double rewardPointsEarned;

  @HiveField(15)
  bool isSynced;

  @HiveField(16)
  DateTime? updatedAt;

  @HiveField(17)
  int version;

  @HiveField(18)
  String deviceId;

  @HiveField(19)
  String createdBy;

  @HiveField(20)
  bool isDeleted;

  @HiveField(21)
  DateTime? lastSyncedAt;

  Sale({
    required this.id,
    required this.invoiceNumber,
    required this.date,
    required this.customerId,
    required this.customerName,
    required this.items,
    required this.subtotal,
    required this.discountPercent,
    required this.discountAmount,
    required this.taxAmount,
    required this.grandTotal,
    required this.paymentMethod,
    this.notes = '',
    this.rewardDiscountAmount = 0,
    this.rewardPointsEarned = 0,
    this.isSynced = false,
    this.updatedAt,
    this.version = 1,
    this.deviceId = '',
    this.createdBy = '',
    this.isDeleted = false,
    this.lastSyncedAt,
  });
}

@HiveType(typeId: 7)
class SaleItem {
  @HiveField(0)
  String productId;

  @HiveField(1)
  String productName;

  @HiveField(2)
  String productCode;

  @HiveField(3)
  String variantBarcode;

  @HiveField(4)
  String variantSize;

  @HiveField(5)
  double price;

  @HiveField(6)
  int quantity;

  @HiveField(7)
  double total;

  SaleItem({
    required this.productId,
    required this.productName,
    required this.productCode,
    required this.variantBarcode,
    required this.variantSize,
    required this.price,
    required this.quantity,
    required this.total,
  });
}
