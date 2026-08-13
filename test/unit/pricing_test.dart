import 'package:flutter_test/flutter_test.dart';

import 'package:atomid/data/models/loyalty_settings_model.dart';
import 'package:atomid/data/models/settings_model.dart';
import 'package:atomid/domain/pricing.dart';

void main() {
  SettingsModel settings({double rate = 0, String mode = TaxMode.inclusive}) =>
      SettingsModel(taxRate: rate, taxMode: mode);

  LoyaltySettingsModel loyalty({
    bool enabled = true,
    double spendPerPoint = 100,
    double pointsPerSpend = 1,
    double pointValue = 1,
    double maxPercent = 50,
    double minBill = 0,
  }) => LoyaltySettingsModel(
    isLoyaltyEnabled: enabled,
    spendAmountForPoint: spendPerPoint,
    pointsEarnedPerSpend: pointsPerSpend,
    pointRedemptionValue: pointValue,
    maxRedemptionPercentage: maxPercent,
    minBillAmountForRedemption: minBill,
  );

  group('tax', () {
    test('no tax leaves the subtotal untouched', () {
      final totals = SalePricing.compute(
        lineItemTotal: 1299.90,
        settings: settings(),
        loyalty: loyalty(enabled: false),
      );

      expect(totals.taxAmount, 0);
      expect(totals.grandTotal, 1299.90);
    });

    test('exclusive tax is added on top of the discounted subtotal', () {
      final totals = SalePricing.compute(
        lineItemTotal: 1000,
        settings: settings(rate: 18, mode: TaxMode.exclusive),
        loyalty: loyalty(enabled: false),
      );

      expect(totals.taxAmount, 180);
      expect(totals.grandTotal, 1180);
    });

    test(
      'inclusive tax is extracted, so the customer pays the shelf price',
      () {
        final totals = SalePricing.compute(
          lineItemTotal: 1180,
          settings: settings(rate: 18, mode: TaxMode.inclusive),
          loyalty: loyalty(enabled: false),
        );

        expect(totals.grandTotal, 1180);
        expect(totals.taxAmount, closeTo(180, 0.01));
      },
    );

    test('discount is applied before exclusive tax', () {
      final totals = SalePricing.compute(
        lineItemTotal: 1000,
        settings: settings(rate: 10, mode: TaxMode.exclusive),
        loyalty: loyalty(enabled: false),
        requestedDiscountPercent: 20,
      );

      expect(totals.manualDiscount, 200);
      expect(totals.taxAmount, 80);
      expect(totals.grandTotal, 880);
    });
  });

  group('discounts', () {
    test('a percentage becomes the matching amount', () {
      final totals = SalePricing.compute(
        lineItemTotal: 2400,
        settings: settings(),
        loyalty: loyalty(enabled: false),
        requestedDiscountPercent: 15,
      );

      expect(totals.discountPercent, 15);
      expect(totals.manualDiscount, 360);
      expect(totals.grandTotal, 2040);
    });

    test('a percentage above 100 is capped at the whole bill', () {
      final totals = SalePricing.compute(
        lineItemTotal: 500,
        settings: settings(),
        loyalty: loyalty(enabled: false),
        requestedDiscountPercent: 500,
      );

      expect(totals.manualDiscount, 500);
      expect(totals.grandTotal, 0);
    });

    test('a negative percentage is ignored', () {
      final totals = SalePricing.compute(
        lineItemTotal: 500,
        settings: settings(),
        loyalty: loyalty(enabled: false),
        requestedDiscountPercent: -10,
      );

      expect(totals.manualDiscount, 0);
      expect(totals.grandTotal, 500);
    });

    test('a percentage is capped by what reward points left to pay', () {
      // 40% of 1000 is 400, but points already cover 800.
      final totals = SalePricing.compute(
        lineItemTotal: 1000,
        settings: settings(),
        loyalty: loyalty(pointValue: 1, maxPercent: 80),
        availablePoints: 800,
        redeemPoints: true,
        requestedDiscountPercent: 40,
      );

      expect(totals.rewardDiscount, 800);
      expect(totals.manualDiscount, 200);
      expect(totals.discountPercent, 20, reason: 'reports what was applied');
      expect(totals.grandTotal, 0);
    });

    test('a fractional percentage rounds to whole paise', () {
      final totals = SalePricing.compute(
        lineItemTotal: 999,
        settings: settings(),
        loyalty: loyalty(enabled: false),
        requestedDiscountPercent: 7.5,
      );

      expect(totals.manualDiscount, 74.93);
      expect(totals.grandTotal, 924.07);
    });
  });

  group('loyalty', () {
    test('nothing is earned or redeemable while the programme is off', () {
      final totals = SalePricing.compute(
        lineItemTotal: 1000,
        settings: settings(),
        loyalty: loyalty(enabled: false),
        availablePoints: 500,
        redeemPoints: true,
      );

      expect(totals.rewardDiscount, 0);
      expect(totals.pointsEarned, 0);
    });

    test('points earned use whole multiples of the spend threshold', () {
      final totals = SalePricing.compute(
        lineItemTotal: 250,
        settings: settings(),
        loyalty: loyalty(spendPerPoint: 100, pointsPerSpend: 10),
      );

      // 250 spans two full 100s, so 20 points — not 25.
      expect(totals.pointsEarned, 20);
    });

    test('redemption is capped by the maximum share of the bill', () {
      final totals = SalePricing.compute(
        lineItemTotal: 1000,
        settings: settings(),
        loyalty: loyalty(pointValue: 1, maxPercent: 20),
        availablePoints: 900,
        redeemPoints: true,
      );

      expect(totals.rewardDiscount, 200);
      expect(totals.pointsRedeemed, 200);
      expect(totals.grandTotal, 800);
    });

    test('redemption is blocked below the minimum bill', () {
      final totals = SalePricing.compute(
        lineItemTotal: 100,
        settings: settings(),
        loyalty: loyalty(minBill: 500),
        availablePoints: 900,
        redeemPoints: true,
      );

      expect(totals.rewardDiscount, 0);
    });

    test('points are earned on what was actually paid, not the list price', () {
      final totals = SalePricing.compute(
        lineItemTotal: 1000,
        settings: settings(),
        loyalty: loyalty(spendPerPoint: 100, pointsPerSpend: 1),
        requestedDiscountPercent: 50,
      );

      expect(totals.grandTotal, 500);
      expect(totals.pointsEarned, 5);
    });
  });

  test('totals never carry floating point noise', () {
    final totals = SalePricing.compute(
      lineItemTotal: 1299.90 * 3,
      settings: settings(),
      loyalty: loyalty(enabled: false),
    );

    expect(totals.grandTotal, 3899.70);
  });
}
