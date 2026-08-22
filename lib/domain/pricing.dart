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

    // The cap is a share of the bill, but nothing stops the settings screen
    // storing a share above 100 — and at, say, 500% a well-stocked points
    // balance redeems five times what is owed. That turned the sale negative,
    // which the grand total then clamped to zero while the *points earned*
    // calculation still saw the negative figure and took points off the
    // customer. The bill is the hard ceiling.
    final percent = loyalty.maxRedemptionPercentage.clamp(0.0, 100.0);
    final cap = subtotal * (percent / 100.0);

    final redeemable = pointsValue < cap ? pointsValue : cap;
    if (redeemable <= 0) return 0;

    // Floored, not rounded. This figure is a ceiling on what the customer's
    // points are worth, and `compute` divides it back out to decide how many
    // points to take. Rounding up by half a paisa therefore takes
    // `0.005 / pointRedemptionValue` points that were never there — half a
    // point at 100-to-the-rupee, five points at 1000-to-the-rupee, on every
    // redemption. The stored balance is re-derived from the transaction
    // ledger and floored at zero, so the overdraft never surfaced as a
    // negative balance; it just quietly ate points.
    return Fmt.floor2(redeemable);
  }

  /// Points earned on the amount the customer actually paid.
  static double pointsEarned({
    required LoyaltySettingsModel loyalty,
    required double payableAmount,
  }) {
    if (!loyalty.isLoyaltyEnabled) return 0;
    if (loyalty.spendAmountForPoint <= 0) return 0;
    // Nothing paid, nothing earned — and never anything taken away.
    if (payableAmount <= 0) return 0;
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

    // Rounded to the precision the invoice prints at. A cashier who types
    // 79.6055 would otherwise get an amount computed from the full figure
    // beside a printed "79.61%", and a customer checking the arithmetic
    // would find the two disagree by several rupees on a large basket.
    final percent = Fmt.round2(
      requestedDiscountPercent.clamp(0, maxDiscountPercent).toDouble(),
    );

    // A discount can never exceed what is left to pay.
    final headroom = subtotal - rewardDiscount;
    final requestedAmount = Fmt.round2(subtotal * percent / 100);
    final manualDiscount = Fmt.round2(
      (subtotal * percent / 100)
          .clamp(0, headroom < 0 ? 0 : headroom)
          .toDouble(),
    );

    // When the cap did not bite, the percentage applied is the one that was
    // asked for, and reporting it verbatim keeps it reproducible from the
    // amount. Only a capped discount needs the effective rate derived, and
    // that one cannot be reproduced at two decimals — see
    // `DocumentTotals.discountPercentReproduces`, which is what stops the
    // invoice printing a percentage that does not match its own figures.
    final appliedPercent = subtotal <= 0
        ? 0.0
        : (manualDiscount == requestedAmount
              ? percent
              : Fmt.round2(manualDiscount / subtotal * 100));

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

    // Clamped once, here, so the grand total and the points earned from it
    // can never disagree about what the customer actually paid.
    final payable = grandTotal < 0 ? 0.0 : grandTotal;

    // Floored for the same reason the value above is: this is what gets
    // deducted from the customer's balance, and it must never exceed what
    // they hold.
    final pointsRedeemed =
        rewardDiscount > 0 && loyalty.pointRedemptionValue > 0
        ? Fmt.floor2(rewardDiscount / loyalty.pointRedemptionValue)
        : 0.0;

    return SaleTotals(
      subtotal: subtotal,
      discountPercent: appliedPercent,
      manualDiscount: manualDiscount,
      rewardDiscount: rewardDiscount,
      taxAmount: taxAmount,
      grandTotal: payable,
      pointsRedeemed: pointsRedeemed,
      // Earned on what was actually payable. Passing the raw `grandTotal`
      // here meant a bill driven negative produced a *negative* number of
      // points — the sale silently took points away from the customer.
      pointsEarned: pointsEarned(loyalty: loyalty, payableAmount: payable),
    );
  }
}
