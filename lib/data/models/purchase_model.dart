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

  // Additive fields for supplier invoice and GST input tax
  @HiveField(22)
  String supplierInvoiceNumber;

  @HiveField(23)
  DateTime? supplierInvoiceDate;

  @HiveField(24)
  String supplierGstin;

  @HiveField(25)
  String supplierState;

  @HiveField(26)
  String supplierStateCode;

  @HiveField(27)
  String supplierAddress;

  @HiveField(28)
  String itcEligibility; // 'REQUIRES_DETERMINATION', 'ELIGIBLE', 'INELIGIBLE', 'BLOCKED'

  @HiveField(29)
  double taxableAmount;

  @HiveField(30)
  double cgstAmount;

  @HiveField(31)
  double sgstAmount;

  @HiveField(32)
  double utgstAmount;

  @HiveField(33)
  double igstAmount;

  @HiveField(34)
  double cessAmount;

  @HiveField(35)
  double roundOff;

  @HiveField(36)
  bool isInterState;

  // --- Recipient (this shop) snapshot -------------------------------------
  //
  // Frozen at calculation time, exactly as a Sale freezes its seller. A
  // purchase used to re-read `getCompany()` on every recompute, so renaming
  // the business or correcting its state silently rewrote the tax heads on
  // orders booked months earlier.

  @HiveField(37)
  String recipientName;

  @HiveField(38)
  String recipientGstin;

  @HiveField(39)
  String recipientState;

  @HiveField(40)
  String recipientStateCode;

  /// 'inclusive' or 'exclusive' — how the cost prices on this order were read.
  @HiveField(41)
  String pricingMode;

  /// The total before round-off, so the round-off line can be reproduced.
  @HiveField(42)
  double preRoundTotal;

  Purchase({
    required this.id,
    required this.purchaseNumber,
    required this.supplierId,
    required this.supplierName,
    required this.purchaseDate,
    this.items = const [],
    this.subtotal = 0.0,
    this.discount = 0,
    this.tax = 0,
    required this.grandTotal,
    this.notes = '',
    DateTime? createdDate,
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
    this.supplierInvoiceNumber = '',
    this.supplierInvoiceDate,
    this.supplierGstin = '',
    this.supplierState = '',
    this.supplierStateCode = '',
    this.supplierAddress = '',
    this.itcEligibility = 'REQUIRES_DETERMINATION',
    this.recipientName = '',
    this.recipientGstin = '',
    this.recipientState = '',
    this.recipientStateCode = '',
    this.pricingMode = 'exclusive',
    this.preRoundTotal = 0.0,
    this.taxableAmount = 0.0,
    this.cgstAmount = 0.0,
    this.sgstAmount = 0.0,
    this.utgstAmount = 0.0,
    this.igstAmount = 0.0,
    this.cessAmount = 0.0,
    this.roundOff = 0.0,
    this.isInterState = false,
  }) : createdDate = createdDate ?? DateTime.now();

  double get totalGst => cgstAmount + sgstAmount + utgstAmount + igstAmount;
  double get totalTax => totalGst + cessAmount;
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

  // Additive GST fields for purchase line item
  @HiveField(10)
  String hsn;

  @HiveField(11)
  String uqc;

  @HiveField(12)
  double? gstRate;

  @HiveField(13)
  String gstTreatment;

  @HiveField(14)
  double cessRate;

  @HiveField(15)
  double taxableValue;

  @HiveField(16)
  double discountAmount;

  @HiveField(17)
  double cgstAmount;

  @HiveField(18)
  double sgstAmount;

  @HiveField(19)
  double utgstAmount;

  @HiveField(20)
  double igstAmount;

  @HiveField(21)
  double cessAmount;

  /// Which entry in the rate book the rate came from, frozen with the line.
  @HiveField(22)
  String? gstRateConfigId;

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
