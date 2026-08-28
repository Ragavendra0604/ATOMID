import 'package:atomid/domain/gst/gst_treatment.dart';

/// Single line item input for GST calculation.
class GstLineInput {
  final String productId;
  final String productName;
  final String productCode;
  final String variantBarcode;
  final String variantSize;
  final double unitPrice;
  final int quantity;
  final String hsn;
  final String uqc;
  final String gstTreatment; // From GstTreatment constants
  final double? gstRate; // e.g. 5.0, 12.0, 18.0, 0.0, null if unconfigured
  final double cessRate; // e.g. 0.0 or 12.0
  final String? gstRateConfigId;
  final double lineDiscount; // Specific discount on this line (default 0.0)

  const GstLineInput({
    required this.productId,
    required this.productName,
    this.productCode = '',
    required this.variantBarcode,
    required this.variantSize,
    required this.unitPrice,
    required this.quantity,
    this.hsn = '',
    this.uqc = 'PCS',
    this.gstTreatment = GstTreatment.taxable,
    this.gstRate,
    this.cessRate = 0.0,
    this.gstRateConfigId,
    this.lineDiscount = 0.0,
  });

  double get lineGross => unitPrice * quantity;
}

/// Fully calculated and broken-down GST result for one line item.
class GstLineResult {
  final String productId;
  final String productName;
  final String productCode;
  final String variantBarcode;
  final String variantSize;
  final double unitPrice;
  final int quantity;
  final String hsn;
  final String uqc;
  final String gstTreatment;
  final double? gstRate;
  final double cessRate;
  final String? gstRateConfigId;

  final double lineGross;
  final double discountAllocated;
  final double taxableValue;

  final double cgstRate;
  final double cgstAmount;
  final double sgstRate;
  final double sgstAmount;
  final double utgstRate;
  final double utgstAmount;
  final double igstRate;
  final double igstAmount;
  final double cessAmount;

  final double totalTax;
  final double lineTotal;

  const GstLineResult({
    required this.productId,
    required this.productName,
    required this.productCode,
    required this.variantBarcode,
    required this.variantSize,
    required this.unitPrice,
    required this.quantity,
    required this.hsn,
    required this.uqc,
    required this.gstTreatment,
    required this.gstRate,
    required this.cessRate,
    this.gstRateConfigId,
    required this.lineGross,
    required this.discountAllocated,
    required this.taxableValue,
    required this.cgstRate,
    required this.cgstAmount,
    required this.sgstRate,
    required this.sgstAmount,
    required this.utgstRate,
    required this.utgstAmount,
    required this.igstRate,
    required this.igstAmount,
    required this.cessAmount,
    required this.totalTax,
    required this.lineTotal,
  });

  double get effectiveGstRate => (gstRate ?? 0.0);
  double get totalGstAmount =>
      cgstAmount + sgstAmount + utgstAmount + igstAmount;
}

/// Top-level parameters for GST calculation.
class GstCalculationInput {
  final DateTime transactionDate;
  final String sellerState; // e.g. "Tamil Nadu" or "33"
  final String sellerStateCode; // 2-digit code e.g. "33"
  final String sellerGstin;

  final String? customerState;
  final String? customerStateCode;
  final String? customerGstin;
  final String? destinationStateCode;

  final String pricingMode; // 'inclusive' vs 'exclusive'
  final String
  walkInPosPolicy; // 'USE_SHOP_STATE', 'REQUIRE_STATE', 'ASK_AT_CHECKOUT'
  final bool isWalkIn;

  final double requestedDiscountPercent;
  final double manualDiscountAmount;
  final double rewardDiscountAmount;

  final bool roundOffEnabled;

  /// 'SHELF_PRICE' (the marked price is exact, tax is the remainder) or
  /// 'TAX_RATE' (every tax figure is rate x taxable, so the line total may
  /// land a paisa above the marked price). Only consulted for inclusive
  /// pricing, and only when the two readings disagree.
  final String inclusiveTaxRounding;

  final List<GstLineInput> lines;

  const GstCalculationInput({
    required this.transactionDate,
    required this.sellerState,
    required this.sellerStateCode,
    this.sellerGstin = '',
    this.customerState,
    this.customerStateCode,
    this.customerGstin,
    this.destinationStateCode,
    this.pricingMode = 'inclusive',
    this.walkInPosPolicy = 'USE_SHOP_STATE',
    this.isWalkIn = true,
    this.requestedDiscountPercent = 0.0,
    this.manualDiscountAmount = 0.0,
    this.rewardDiscountAmount = 0.0,
    this.roundOffEnabled = true,
    this.inclusiveTaxRounding = 'SHELF_PRICE',
    required this.lines,
  });

  bool get isInclusive => pricingMode.toLowerCase() == 'inclusive';

  /// True when inclusive tax must be derived from the rate rather than taken
  /// as the remainder of the shelf price.
  bool get isInclusiveTaxFromRate =>
      inclusiveTaxRounding.toUpperCase() == 'TAX_RATE';
}

/// Complete resolved GST calculation output for a transaction.
class GstCalculationResult {
  final bool isValid;
  final List<String> errors;

  final List<GstLineResult> lines;

  final double subtotal; // Sum of lineGross
  final double discountAmount; // Total discount allocated
  final double rewardDiscount;
  final double manualDiscount;
  final double appliedDiscountPercent;

  final double taxableAmount; // Sum of taxable values
  final double cgstAmount;
  final double sgstAmount;
  final double utgstAmount;
  final double igstAmount;
  final double cessAmount;
  final double totalGst;
  final double totalTax; // totalGst + cess

  final double preRoundTotal;
  final double roundOff;
  final double payableAmount; // Grand total after round-off

  final String pricingMode;
  final bool isInterState;
  final bool isUtgst;
  final String placeOfSupplyCode;
  final String placeOfSupplyState;
  final String placeOfSupplyBasis;

  const GstCalculationResult({
    required this.isValid,
    this.errors = const [],
    this.lines = const [],
    this.subtotal = 0.0,
    this.discountAmount = 0.0,
    this.rewardDiscount = 0.0,
    this.manualDiscount = 0.0,
    this.appliedDiscountPercent = 0.0,
    this.taxableAmount = 0.0,
    this.cgstAmount = 0.0,
    this.sgstAmount = 0.0,
    this.utgstAmount = 0.0,
    this.igstAmount = 0.0,
    this.cessAmount = 0.0,
    this.totalGst = 0.0,
    this.totalTax = 0.0,
    this.preRoundTotal = 0.0,
    this.roundOff = 0.0,
    required this.payableAmount,
    this.pricingMode = 'inclusive',
    this.isInterState = false,
    this.isUtgst = false,
    this.placeOfSupplyCode = '',
    this.placeOfSupplyState = '',
    this.placeOfSupplyBasis = '',
  });

  double get grandTotal => payableAmount;

  factory GstCalculationResult.invalid(List<String> errors) =>
      GstCalculationResult(isValid: false, errors: errors, payableAmount: 0.0);
}
