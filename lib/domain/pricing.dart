import 'package:atomid/core/utils/formatters.dart';
import 'package:atomid/data/models/loyalty_settings_model.dart';
import 'package:atomid/data/models/settings_model.dart';

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

/// The fully resolved money breakdown for a sale.
///
/// Every value is rounded to two decimals at the point of calculation, so what
/// the cashier reads, what the invoice prints, and what the ledger records are
/// always the same number.
class SaleTotals {
  final double subtotal;

  /// The percentage the cashier entered, after clamping.
  final double discountPercent;

  /// What that percentage works out to in money.
  final double manualDiscount;

  final double rewardDiscount;
  final double taxAmount;
  final double grandTotal;
  final double pointsRedeemed;
  final double pointsEarned;

  const SaleTotals({
    required this.subtotal,
    required this.discountPercent,
    required this.manualDiscount,
    required this.rewardDiscount,
    required this.taxAmount,
    required this.grandTotal,
    required this.pointsRedeemed,
    required this.pointsEarned,
  });

  double get totalDiscount => Fmt.round2(manualDiscount + rewardDiscount);
}

/// Pure sale arithmetic, kept out of the widget tree so it can be tested and
/// so POS, checkout and the invoice can never disagree about a total.
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
    final cap = subtotal * (loyalty.maxRedemptionPercentage / 100.0);
    return Fmt.round2(pointsValue < cap ? pointsValue : cap);
  }

  /// Points earned on the amount the customer actually paid.
  static double pointsEarned({
    required LoyaltySettingsModel loyalty,
    required double payableAmount,
  }) {
    if (!loyalty.isLoyaltyEnabled) return 0;
    if (loyalty.spendAmountForPoint <= 0) return 0;
    final multiples = (payableAmount / loyalty.spendAmountForPoint)
        .floorToDouble();
    return multiples * loyalty.pointsEarnedPerSpend;
  }

  /// Highest discount a cashier may apply from the till.
  static const double maxDiscountPercent = 100;

  /// Resolves a cart into its final money breakdown.
  ///
  /// [requestedDiscountPercent] is what the cashier typed. It is applied to
  /// the subtotal, then capped at whatever is left after reward points, so a
  /// mistyped 100 on a part-redeemed bill cannot push the total negative.
  ///
  /// Discounts always apply before tax. Under [TaxMode.inclusive] the tax is
  /// extracted from the discounted total rather than added to it, so the
  /// customer pays exactly the shelf price.
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

    final percent = requestedDiscountPercent
        .clamp(0, maxDiscountPercent)
        .toDouble();

    // A discount can never exceed what is left to pay.
    final headroom = subtotal - rewardDiscount;
    final manualDiscount = Fmt.round2(
      (subtotal * percent / 100)
          .clamp(0, headroom < 0 ? 0 : headroom)
          .toDouble(),
    );

    // Report the percentage that was actually applied, which is what the
    // invoice must show when the cap bit.
    final appliedPercent = subtotal <= 0
        ? 0.0
        : Fmt.round2(manualDiscount / subtotal * 100);

    final discounted = Fmt.round2(subtotal - rewardDiscount - manualDiscount);
    final rate = settings.taxRate;

    double taxAmount;
    double grandTotal;

    if (rate <= 0) {
      taxAmount = 0;
      grandTotal = discounted;
    } else if (settings.taxMode == TaxMode.exclusive) {
      taxAmount = Fmt.round2(discounted * rate / 100);
      grandTotal = Fmt.round2(discounted + taxAmount);
    } else {
      // Inclusive: the discounted figure already contains the tax.
      taxAmount = Fmt.round2(discounted - (discounted / (1 + rate / 100)));
      grandTotal = discounted;
    }

    final pointsRedeemed =
        rewardDiscount > 0 && loyalty.pointRedemptionValue > 0
        ? Fmt.round2(rewardDiscount / loyalty.pointRedemptionValue)
        : 0.0;

    return SaleTotals(
      subtotal: subtotal,
      discountPercent: appliedPercent,
      manualDiscount: manualDiscount,
      rewardDiscount: rewardDiscount,
      taxAmount: taxAmount,
      grandTotal: grandTotal < 0 ? 0 : grandTotal,
      pointsRedeemed: pointsRedeemed,
      pointsEarned: pointsEarned(loyalty: loyalty, payableAmount: grandTotal),
    );
  }
}
