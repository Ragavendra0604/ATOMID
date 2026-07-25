import 'package:hive_ce/hive.dart';

part 'purchase_model.g.dart';

@HiveType(typeId: 8)
class Purchase extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String purchaseNumber;

  @HiveField(2)
  String supplierId;

  @HiveField(3)
  String supplierName;

  @HiveField(4)
  DateTime purchaseDate;

  @HiveField(5)
  List<PurchaseItem> items;

  @HiveField(6)
  double subtotal;

  @HiveField(7)
  double discount;

  @HiveField(8)
  double tax;

  @HiveField(9)
  double grandTotal;

  @HiveField(10)
  String notes;

  @HiveField(11)
  DateTime createdDate;

  @HiveField(12)
  bool isSynced;

  @HiveField(13)
  int version;

  @HiveField(14)
  String deviceId;

  @HiveField(15)
  String createdBy;

  @HiveField(16)
  bool isDeleted;

  @HiveField(17)
  DateTime? lastSyncedAt;

  @HiveField(18)
  DateTime? updatedAt;

  @HiveField(19)
  String status; // 'Draft', 'Issued', 'Partially Received', 'Received', 'Cancelled'

  @HiveField(20)
  String paymentStatus; // 'Unpaid', 'Partial', 'Paid'

  @HiveField(21)
  DateTime? expectedDeliveryDate;

  Purchase({
    required this.id,
    required this.purchaseNumber,
    required this.supplierId,
    required this.supplierName,
    required this.purchaseDate,
    required this.items,
    required this.subtotal,
    this.discount = 0,
    this.tax = 0,
    required this.grandTotal,
    this.notes = '',
    required this.createdDate,
    this.isSynced = false,
    this.version = 1,
    this.deviceId = '',
    this.createdBy = '',
    this.isDeleted = false,
    this.lastSyncedAt,
    this.updatedAt,
    this.status = 'Received', // Default to Received for legacy data
    this.paymentStatus = 'Unpaid',
    this.expectedDeliveryDate,
  });
}

@HiveType(typeId: 9)
class PurchaseItem {
  @HiveField(0)
  String productId;

  @HiveField(1)
  String productName;

  @HiveField(2)
  String variantBarcode;

  @HiveField(3)
  String variantSize;

  @HiveField(4)
  String sku;

  @HiveField(5)
  int quantity;

  @HiveField(6)
  double costPrice;

  @HiveField(7)
  double sellingPrice;

  @HiveField(8)
  double lineTotal;

  @HiveField(9)
  int receivedQuantity;

  PurchaseItem({
    required this.productId,
    required this.productName,
    required this.variantBarcode,
    required this.variantSize,
    this.sku = '',
    required this.quantity,
    required this.costPrice,
    required this.sellingPrice,
    required this.lineTotal,
    this.receivedQuantity = 0,
  });
}
