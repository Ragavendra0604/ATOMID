import 'package:atomid/core/utils/formatters.dart';
import 'package:atomid/data/models/company_model.dart';
import 'package:atomid/data/models/customer_model.dart';
import 'package:atomid/data/models/loyalty_settings_model.dart';
import 'package:atomid/data/models/settings_model.dart';
import 'package:atomid/domain/cart_item.dart';
import 'package:atomid/domain/gst/gst_engine.dart';
import 'package:atomid/domain/gst/gst_models.dart';
import 'package:atomid/domain/gst/gst_treatment.dart';

/// Tax handling modes.
class TaxMode {
  /// Listed prices already contain tax; tax is extracted for the invoice.
  static const inclusive = 'inclusive';

  /// Tax is calculated on the discounted subtotal and added on top.
  static const exclusive = 'exclusive';

  static const all = [inclusive, exclusive];

  static String label(String mode) => mode == exclusive
      ? 'Added to prices (exclusive)'
      : 'Included in prices (inclusive)';
}

/// The fully resolved money breakdown for a sale, including complete GST components.
class SaleTotals {
  final double subtotal;

  /// The percentage applied, after clamping.
  final double discountPercent;

  /// What that percentage works out to in money.
  final double manualDiscount;

  final double rewardDiscount;
  final double taxAmount; // Total GST + Cess
  final double grandTotal;
  final double pointsRedeemed;
  final double pointsEarned;

  // GST breakdown fields
  final double taxableAmount;
  final double cgstAmount;
  final double sgstAmount;
  final double utgstAmount;
  final double igstAmount;
  final double cessAmount;
  final double totalGst;
  final double preRoundTotal;
  final double roundOff;
  final bool isInterState;
  final bool isUtgst;
  final String placeOfSupply;
  final GstCalculationResult? gstResult;

  const SaleTotals({
    required this.subtotal,
    required this.discountPercent,
    required this.manualDiscount,
    required this.rewardDiscount,
    required this.taxAmount,
    required this.grandTotal,
    required this.pointsRedeemed,
    required this.pointsEarned,
    this.taxableAmount = 0.0,
    this.cgstAmount = 0.0,
    this.sgstAmount = 0.0,
    this.utgstAmount = 0.0,
    this.igstAmount = 0.0,
    this.cessAmount = 0.0,
    this.totalGst = 0.0,
    this.preRoundTotal = 0.0,
    this.roundOff = 0.0,
    this.isInterState = false,
    this.isUtgst = false,
    this.placeOfSupply = '',
    this.gstResult,
  });

  double get totalDiscount => Fmt.round2(manualDiscount + rewardDiscount);
  double get payableAmount => grandTotal;
}

/// Pure sale arithmetic delegating all statutory tax math to [Gst.compute].
class SalePricing {
  const SalePricing._();

  /// Value of the points a customer may redeem against this sale.
  static double maxRedeemableValue({
    required LoyaltySettingsModel loyalty,
    required double availablePoints,
    required double subtotal,
  }) {
    if (!loyalty.isLoyaltyEnabled) return 0;
    if (availablePoints <= 0) return 0;
    if (subtotal < loyalty.minBillAmountForRedemption) return 0;
    if (loyalty.pointRedemptionValue <= 0) return 0;

    final pointsValue = availablePoints * loyalty.pointRedemptionValue;
    final percent = loyalty.maxRedemptionPercentage.clamp(0.0, 100.0);
    final cap = subtotal * (percent / 100.0);

    final redeemable = pointsValue < cap ? pointsValue : cap;
    if (redeemable <= 0) return 0;

    return Fmt.floor2(redeemable);
  }

  /// Points earned on the amount the customer actually paid.
  static double pointsEarned({
    required LoyaltySettingsModel loyalty,
    required double payableAmount,
  }) {
    if (!loyalty.isLoyaltyEnabled) return 0;
    if (loyalty.spendAmountForPoint <= 0) return 0;
    if (payableAmount <= 0) return 0;
    final multiples = (payableAmount / loyalty.spendAmountForPoint)
        .floorToDouble();
    return multiples * loyalty.pointsEarnedPerSpend;
  }

  /// Highest discount a cashier may apply from the till.
  static const double maxDiscountPercent = 100;

  /// Full cart GST pricing using the central [Gst.compute] engine.
  static SaleTotals computeCart({
    required List<CartItem> items,
    required SettingsModel settings,
    required LoyaltySettingsModel loyalty,
    required CompanyModel company,
    Customer? customer,
    String? destinationStateCode,
    double requestedDiscountPercent = 0,
    double availablePoints = 0,
    bool redeemPoints = false,
    DateTime? transactionDate,
  }) {
    final subtotal = Fmt.round2(
      items.fold(0.0, (sum, i) => sum + (i.variant.price * i.quantity)),
    );

    final rewardDiscount = redeemPoints
        ? maxRedeemableValue(
            loyalty: loyalty,
            availablePoints: availablePoints,
            subtotal: subtotal,
          )
        : 0.0;

    final lines = items.map((i) {
      // The product's own GST configuration is the only source of its rate.
      //
      // `settings.taxRate` is a legacy shop-wide field and must never stand in
      // for a product's rate. Doing so broke the rule the whole engine is built
      // on — UNCONFIGURED is not 0% — in both directions: a product explicitly
      // configured at 0% inherited the shop's 18%, and a product with no rate
      // at all was silently billed at the shop rate instead of stopping the
      // sale. A null rate is passed through untouched so that
      // [GstRateResolver] raises its unresolved error and checkout blocks.
      final treatment = i.product.gstTreatment.isNotEmpty
          ? i.product.gstTreatment
          : GstTreatment.taxable;
      final rate = i.product.gstRate;

      return GstLineInput(
        productId: i.product.id,
        // Same name the sale snapshot stores, so a tax error names the line
        // the way the invoice will print it.
        productName: i.product.displayName,
        productCode: i.product.productCode,
        variantBarcode: i.variant.barcode,
        variantSize: i.variant.size,
        unitPrice: i.variant.price,
        quantity: i.quantity,
        hsn: i.product.hsn,
        uqc: i.product.uqc.isNotEmpty ? i.product.uqc : settings.defaultUqc,
        gstTreatment: treatment,
        gstRate: rate,
        cessRate: i.product.cessRate,
        gstRateConfigId: i.product.gstRateConfigId,
      );
    }).toList();

    final date = transactionDate ?? DateTime.now();

    final input = GstCalculationInput(
      transactionDate: date,
      // The shop's own configuration, with nothing standing in for it. A
      // missing state used to become Tamil Nadu / 33, so a shop anywhere else
      // that had not finished setup billed CGST + SGST against a state it had
      // never chosen — and the invoice looked entirely normal.
      sellerState: company.state,
      sellerStateCode: company.stateCode,
      sellerGstin: company.gstNumber,
      customerState: customer?.state,
      customerStateCode: customer?.stateCode,
      customerGstin: customer?.gstNumber,
      destinationStateCode: destinationStateCode,
      pricingMode: settings.taxMode,
      walkInPosPolicy: settings.walkInPosPolicy,
      isWalkIn:
          customer == null ||
          (customer.gstNumber.isEmpty && customer.state.isEmpty),
      requestedDiscountPercent: requestedDiscountPercent,
      rewardDiscountAmount: rewardDiscount,
      roundOffEnabled: settings.roundOffEnabled,
      inclusiveTaxRounding: settings.inclusiveTaxRounding,
      lines: lines,
    );

    final gstResult = Gst.compute(input);

    final payable = gstResult.payableAmount;
    final pointsRedeemed =
        rewardDiscount > 0 && loyalty.pointRedemptionValue > 0
        ? Fmt.floor2(rewardDiscount / loyalty.pointRedemptionValue)
        : 0.0;

    return SaleTotals(
      subtotal: gstResult.subtotal,
      discountPercent: gstResult.appliedDiscountPercent,
      manualDiscount: gstResult.manualDiscount,
      rewardDiscount: gstResult.rewardDiscount,
      taxAmount: gstResult.totalTax,
      grandTotal: payable,
      pointsRedeemed: pointsRedeemed,
      pointsEarned: pointsEarned(loyalty: loyalty, payableAmount: payable),
      taxableAmount: gstResult.taxableAmount,
      cgstAmount: gstResult.cgstAmount,
      sgstAmount: gstResult.sgstAmount,
      utgstAmount: gstResult.utgstAmount,
      igstAmount: gstResult.igstAmount,
      cessAmount: gstResult.cessAmount,
      totalGst: gstResult.totalGst,
      preRoundTotal: gstResult.preRoundTotal,
      roundOff: gstResult.roundOff,
      isInterState: gstResult.isInterState,
      isUtgst: gstResult.isUtgst,
      placeOfSupply: gstResult.placeOfSupplyState,
      gstResult: gstResult,
    );
  }

  /// Legacy compute helper that delegates through [Gst.compute].
  static SaleTotals compute({
    required double lineItemTotal,
    required SettingsModel settings,
    required LoyaltySettingsModel loyalty,
    double requestedDiscountPercent = 0,
    double availablePoints = 0,
    bool redeemPoints = false,
  }) {
    final subtotal = Fmt.round2(lineItemTotal);

    final rewardDiscount = redeemPoints
        ? maxRedeemableValue(
            loyalty: loyalty,
            availablePoints: availablePoints,
            subtotal: subtotal,
          )
        : 0.0;

    final line = GstLineInput(
      productId: 'item_1',
      productName: 'Item',
      variantBarcode: 'BARCODE1',
      variantSize: 'Std',
      unitPrice: subtotal,
      quantity: 1,
      gstTreatment: GstTreatment.taxable,
      gstRate: settings.taxRate,
    );

    final input = GstCalculationInput(
      transactionDate: DateTime.now(),
      sellerState: 'Tamil Nadu',
      sellerStateCode: '33',
      pricingMode: settings.taxMode,
      walkInPosPolicy: settings.walkInPosPolicy,
      isWalkIn: true,
      requestedDiscountPercent: requestedDiscountPercent,
      rewardDiscountAmount: rewardDiscount,
      roundOffEnabled: settings.roundOffEnabled,
      inclusiveTaxRounding: settings.inclusiveTaxRounding,
      lines: [line],
    );

    final res = Gst.compute(input);

    final pointsRedeemed =
        rewardDiscount > 0 && loyalty.pointRedemptionValue > 0
        ? Fmt.floor2(rewardDiscount / loyalty.pointRedemptionValue)
        : 0.0;

    return SaleTotals(
      subtotal: res.subtotal,
      discountPercent: res.appliedDiscountPercent,
      manualDiscount: res.manualDiscount,
      rewardDiscount: res.rewardDiscount,
      taxAmount: res.totalTax,
      grandTotal: res.payableAmount,
      pointsRedeemed: pointsRedeemed,
      pointsEarned: pointsEarned(
        loyalty: loyalty,
        payableAmount: res.payableAmount,
      ),
      taxableAmount: res.taxableAmount,
      cgstAmount: res.cgstAmount,
      sgstAmount: res.sgstAmount,
      utgstAmount: res.utgstAmount,
      igstAmount: res.igstAmount,
      cessAmount: res.cessAmount,
      totalGst: res.totalGst,
      preRoundTotal: res.preRoundTotal,
      roundOff: res.roundOff,
      isInterState: res.isInterState,
      isUtgst: res.isUtgst,
      placeOfSupply: res.placeOfSupplyState,
      gstResult: res,
    );
  }
}
