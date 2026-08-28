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

  @HiveField(12)
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

  // Additive GST snapshot fields for historical immutability
  @HiveField(22)
  String sellerGstin;

  @HiveField(23)
  String sellerState;

  @HiveField(24)
  String sellerStateCode;

  @HiveField(25)
  String sellerLegalName;

  @HiveField(26)
  String sellerAddress;

  @HiveField(27)
  String customerGstin;

  @HiveField(28)
  String customerState;

  @HiveField(29)
  String customerStateCode;

  @HiveField(30)
  String customerAddress;

  @HiveField(31)
  String customerPhone;

  @HiveField(32)
  String placeOfSupply;

  @HiveField(33)
  String placeOfSupplyBasis;

  @HiveField(34)
  String pricingMode; // 'inclusive' or 'exclusive'

  @HiveField(35)
  double taxableAmount;

  @HiveField(36)
  double cgstAmount;

  @HiveField(37)
  double sgstAmount;

  @HiveField(38)
  double utgstAmount;

  @HiveField(39)
  double igstAmount;

  @HiveField(40)
  double cessAmount;

  @HiveField(41)
  double preRoundTotal;

  @HiveField(42)
  double roundOff;

  @HiveField(43)
  String documentType; // 'Tax Invoice', 'Bill of Supply', etc.

  @HiveField(44)
  bool isInterState;

  Sale({
    required this.id,
    required this.invoiceNumber,
    required this.date,
    this.customerId = '',
    this.customerName = '',
    this.items = const [],
    this.subtotal = 0.0,
    this.discountPercent = 0.0,
    this.discountAmount = 0.0,
    this.taxAmount = 0.0,
    required this.grandTotal,
    this.paymentMethod = 'Cash',
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
    this.sellerGstin = '',
    this.sellerState = '',
    this.sellerStateCode = '',
    this.sellerLegalName = '',
    this.sellerAddress = '',
    this.customerGstin = '',
    this.customerState = '',
    this.customerStateCode = '',
    this.customerAddress = '',
    this.customerPhone = '',
    this.placeOfSupply = '',
    this.placeOfSupplyBasis = '',
    this.pricingMode = 'inclusive',
    this.taxableAmount = 0.0,
    this.cgstAmount = 0.0,
    this.sgstAmount = 0.0,
    this.utgstAmount = 0.0,
    this.igstAmount = 0.0,
    this.cessAmount = 0.0,
    this.preRoundTotal = 0.0,
    this.roundOff = 0.0,
    this.documentType = 'Tax Invoice',
    this.isInterState = false,
  });

  double get totalGst => cgstAmount + sgstAmount + utgstAmount + igstAmount;
  double get totalTax => totalGst + cessAmount;
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

  // Additive GST snapshot fields for line item
  @HiveField(8)
  String hsn;

  @HiveField(9)
  String uqc;

  @HiveField(10)
  double? gstRate;

  @HiveField(11)
  String gstTreatment;

  @HiveField(12)
  double cessRate;

  @HiveField(13)
  double taxableValue;

  @HiveField(14)
  double discountAmount;

  @HiveField(15)
  double cgstAmount;

  @HiveField(16)
  double sgstAmount;

  @HiveField(17)
  double utgstAmount;

  @HiveField(18)
  double igstAmount;

  @HiveField(19)
  double cessAmount;

  @HiveField(20)
  String? gstRateConfigId;

  SaleItem({
    required this.productId,
    required this.productName,
    this.productCode = '',
    required this.variantBarcode,
    required this.variantSize,
    required this.price,
    required this.quantity,
    required this.total,
    this.hsn = '',
    this.uqc = 'PCS',
    this.gstRate,
    this.gstTreatment = 'TAXABLE',
    this.cessRate = 0.0,
    this.taxableValue = 0.0,
    this.discountAmount = 0.0,
    this.cgstAmount = 0.0,
    this.sgstAmount = 0.0,
    this.utgstAmount = 0.0,
    this.igstAmount = 0.0,
    this.cessAmount = 0.0,
    this.gstRateConfigId,
  });

  double get totalTax =>
      cgstAmount + sgstAmount + utgstAmount + igstAmount + cessAmount;
}
