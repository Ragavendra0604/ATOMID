import 'package:hive_ce/hive.dart';

part 'product_model.g.dart';

@HiveType(typeId: 0)
class Product extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String productName;

  @HiveField(2)
  String productCode;

  @HiveField(3)
  String category;

  @HiveField(4)
  String brand;

  @HiveField(5)
  String color;

  @HiveField(6)
  DateTime createdDate;

  @HiveField(7)
  DateTime updatedDate;

  @HiveField(8)
  List<ProductVariant> variants;

  @HiveField(9)
  int version;

  @HiveField(10)
  String deviceId;

  @HiveField(11)
  String createdBy;

  @HiveField(12)
  bool isDeleted;

  @HiveField(13)
  DateTime? lastSyncedAt;

  @HiveField(14)
  bool isSynced;

  @HiveField(15)
  String hsn;

  @HiveField(16)
  String uqc;

  @HiveField(17)
  String gstTreatment; // 'TAXABLE', 'NIL_RATED', 'EXEMPT', 'NON_GST', 'UNCONFIGURED'

  @HiveField(18)
  double? gstRate; // e.g. 5.0, 12.0, 18.0; null represents unconfigured

  @HiveField(19)
  double cessRate;

  @HiveField(20)
  String? gstRateConfigId;

  Product({
    required this.id,
    required this.productName,
    required this.productCode,
    required this.category,
    required this.brand,
    required this.color,
    required this.createdDate,
    required this.updatedDate,
    required this.variants,
    this.version = 1,
    this.deviceId = '',
    this.createdBy = '',
    this.isDeleted = false,
    this.lastSyncedAt,
    this.isSynced = false,
    this.hsn = '',
    this.uqc = 'PCS',
    this.gstTreatment = 'TAXABLE',
    this.gstRate = 0.0,
    this.cessRate = 0.0,
    this.gstRateConfigId,
  });

  /// The name to show wherever a person picks or reviews a product.
  ///
  /// One `Product` is one colourway — sizes are its variants — so a shirt
  /// stocked in three colours is three records sharing a product code. On
  /// screen that made them indistinguishable. Anything a user chooses from
  /// should use this, never `productName` alone.
  String get displayName =>
      color.trim().isEmpty ? productName : '$productName - ${color.trim()}';

  bool get isGstConfigured =>
      gstTreatment != 'UNCONFIGURED' &&
      (gstTreatment != 'TAXABLE' || gstRate != null);
}

@HiveType(typeId: 1)
class ProductVariant {
  @HiveField(0)
  String size;

  @HiveField(1)
  double price;

  @HiveField(2)
  int quantity;

  @HiveField(3)
  String barcode;

  @HiveField(4)
  DateTime? lastStockUpdated;

  @HiveField(5)
  int stockIn;

  @HiveField(6)
  int stockOut;

  @HiveField(7)
  int reorderLevel;

  @HiveField(8)
  String sku;

  @HiveField(9)
  double costPrice;

  ProductVariant({
    required this.size,
    required this.price,
    required this.quantity,
    required this.barcode,
    this.lastStockUpdated,
    this.stockIn = 0,
    this.stockOut = 0,
    this.reorderLevel = 5,
    this.sku = '',
    this.costPrice = 0.0,
  });
}
