import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:atomid/data/models/loyalty_settings_model.dart';
import 'package:atomid/data/models/settings_model.dart';
import 'package:atomid/domain/pricing.dart';

/// Property testing against the money engine.
///
/// `pricing_test.dart` checks worked examples. This checks the things that
/// must hold for *every* combination of basket, discount, tax mode and
/// loyalty configuration — including configurations a careless settings screen
/// could produce, like a negative tax rate or a redemption cap above 100%.
///
/// A POS that hands back a negative total, a `NaN`, or a total larger than the
/// basket is not a rounding curiosity; it is money going missing or being
/// invented.
void main() {
  SettingsModel settings({String taxMode = 'inclusive', double taxRate = 0}) =>
      SettingsModel(taxMode: taxMode, taxRate: taxRate);

  LoyaltySettingsModel loyalty({
    bool enabled = true,
    double spendPerPoint = 100,
    double pointsPerSpend = 1,
    double redemptionValue = 1,
    double maxPercent = 50,
    double minBill = 0,
  }) => LoyaltySettingsModel(
    isLoyaltyEnabled: enabled,
    spendAmountForPoint: spendPerPoint,
    pointsEarnedPerSpend: pointsPerSpend,
    pointRedemptionValue: redemptionValue,
    maxRedemptionPercentage: maxPercent,
    minBillAmountForRedemption: minBill,
  );

  /// Asserts the properties that must hold of any priced basket.
  void expectSane(SaleTotals t, {required double lineItemTotal, String? on}) {
    final where = on == null ? '' : ' [$on]';

    expect(
      t.grandTotal.isFinite,
      isTrue,
      reason: 'grand total is NaN/Inf$where',
    );
    expect(t.subtotal.isFinite, isTrue, reason: 'subtotal is NaN/Inf$where');
    expect(t.taxAmount.isFinite, isTrue, reason: 'tax is NaN/Inf$where');
    expect(
      t.manualDiscount.isFinite,
      isTrue,
      reason: 'discount is NaN/Inf$where',
    );
    expect(
      t.rewardDiscount.isFinite,
      isTrue,
      reason: 'reward discount is NaN/Inf$where',
    );
    expect(t.pointsEarned.isFinite, isTrue, reason: 'points are NaN/Inf$where');

    expect(
      t.grandTotal,
      greaterThanOrEqualTo(0),
      reason: 'a customer can never be owed money by the till$where',
    );
    expect(
      t.manualDiscount,
      greaterThanOrEqualTo(0),
      reason: 'a negative discount is a surcharge$where',
    );
    expect(
      t.rewardDiscount,
      greaterThanOrEqualTo(0),
      reason: 'a negative reward is a surcharge$where',
    );
    expect(
      t.pointsEarned,
      greaterThanOrEqualTo(0),
      reason: 'a sale cannot take points away$where',
    );

    if (lineItemTotal >= 0) {
      expect(
        t.totalDiscount,
        lessThanOrEqualTo(t.subtotal + 0.005),
        reason: 'discounts together exceed the basket$where',
      );
    }
  }

  group('fixed edge cases', () {
    final cases = <String, double>{
      'empty basket': 0,
      'one paisa': 0.01,
      'sub-rupee': 0.99,
      'one rupee': 1,
      'typical': 1499.99,
      'large': 999999.99,
      'very large': 1e9,
    };

    for (final entry in cases.entries) {
      for (final percent in [0.0, 0.01, 33.333, 50.0, 99.99, 100.0]) {
        test('${entry.key} with $percent% discount stays sane', () {
          final totals = SalePricing.compute(
            lineItemTotal: entry.value,
            settings: settings(taxMode: 'exclusive', taxRate: 18),
            loyalty: loyalty(),
            requestedDiscountPercent: percent,
          );
          expectSane(totals, lineItemTotal: entry.value, on: entry.key);
        });
      }
    }

    test('a 100% discount leaves nothing to pay', () {
      final totals = SalePricing.compute(
        lineItemTotal: 500,
        settings: settings(),
        loyalty: loyalty(enabled: false),
        requestedDiscountPercent: 100,
      );

      expect(totals.manualDiscount, 500);
      expect(totals.grandTotal, 0);
    });

    test('a discount beyond 100% is clamped, not applied', () {
      final totals = SalePricing.compute(
        lineItemTotal: 500,
        settings: settings(),
        loyalty: loyalty(enabled: false),
        requestedDiscountPercent: 5000,
      );

      expect(totals.grandTotal, 0);
      expect(totals.manualDiscount, lessThanOrEqualTo(500));
    });

    test('a negative discount is refused rather than charged', () {
      final totals = SalePricing.compute(
        lineItemTotal: 500,
        settings: settings(),
        loyalty: loyalty(enabled: false),
        requestedDiscountPercent: -50,
      );

      expect(totals.manualDiscount, 0);
      expect(totals.grandTotal, 500);
    });
  });

  group('hostile loyalty configuration', () {
    test('a zero redemption value cannot divide by zero', () {
      final totals = SalePricing.compute(
        lineItemTotal: 1000,
        settings: settings(),
        loyalty: loyalty(redemptionValue: 0),
        availablePoints: 500,
        redeemPoints: true,
      );

      expectSane(totals, lineItemTotal: 1000, on: 'zero redemption value');
      expect(totals.pointsRedeemed.isFinite, isTrue);
    });

    test('a zero spend-per-point cannot divide by zero', () {
      final totals = SalePricing.compute(
        lineItemTotal: 1000,
        settings: settings(),
        loyalty: loyalty(spendPerPoint: 0),
      );

      expectSane(totals, lineItemTotal: 1000, on: 'zero spend per point');
      expect(totals.pointsEarned, 0);
    });

    test('a redemption cap above 100% still cannot exceed the bill', () {
      final totals = SalePricing.compute(
        lineItemTotal: 1000,
        settings: settings(),
        loyalty: loyalty(maxPercent: 500, redemptionValue: 10),
        availablePoints: 100000,
        redeemPoints: true,
      );

      expectSane(totals, lineItemTotal: 1000, on: 'cap above 100%');
      expect(
        totals.rewardDiscount,
        lessThanOrEqualTo(1000.005),
        reason:
            'redeeming more than the basket is worth would pay the '
            'customer to shop',
      );
    });

    test('negative available points cannot become a discount', () {
      final totals = SalePricing.compute(
        lineItemTotal: 1000,
        settings: settings(),
        loyalty: loyalty(),
        availablePoints: -5000,
        redeemPoints: true,
      );

      expect(totals.rewardDiscount, 0);
      expectSane(totals, lineItemTotal: 1000, on: 'negative points');
    });
  });

  group('hostile tax configuration', () {
    test('a negative tax rate does not inflate the total', () {
      final totals = SalePricing.compute(
        lineItemTotal: 1000,
        settings: settings(taxMode: 'exclusive', taxRate: -18),
        loyalty: loyalty(enabled: false),
      );

      expectSane(totals, lineItemTotal: 1000, on: 'negative tax');
      expect(
        totals.grandTotal,
        lessThanOrEqualTo(1000.005),
        reason: 'a negative rate must not be charged as a positive one',
      );
    });

    test('a 100% inclusive rate does not divide by zero', () {
      final totals = SalePricing.compute(
        lineItemTotal: 1000,
        settings: settings(taxMode: 'inclusive', taxRate: 100),
        loyalty: loyalty(enabled: false),
      );

      expectSane(totals, lineItemTotal: 1000, on: 'inclusive 100%');
    });

    test('inclusive tax is contained by the total, exclusive adds to it', () {
      final inclusive = SalePricing.compute(
        lineItemTotal: 1000,
        settings: settings(taxMode: 'inclusive', taxRate: 18),
        loyalty: loyalty(enabled: false),
      );
      final exclusive = SalePricing.compute(
        lineItemTotal: 1000,
        settings: settings(taxMode: 'exclusive', taxRate: 18),
        loyalty: loyalty(enabled: false),
      );

      expect(inclusive.grandTotal, 1000, reason: 'shelf price is what is paid');
      expect(exclusive.grandTotal, greaterThan(1000));
      expect(exclusive.grandTotal, 1180);
    });
  });

  group('randomised baskets', () {
    test('ten thousand random priced baskets all stay sane', () {
      // Fixed seed so any failure is reproducible.
      final random = Random(778899);
      final amounts = [0.0, 0.01, 0.1, 0.99, 1.0, 9.99, 100.0, 1499.99, 1e6];
      final rates = [0.0, 0.5, 5.0, 12.0, 18.0, 28.0, 99.0, 100.0, -5.0];
      final modes = ['inclusive', 'exclusive'];

      for (var i = 0; i < 10000; i++) {
        final lineTotal =
            amounts[random.nextInt(amounts.length)] * (1 + random.nextInt(50));
        final percent = random.nextDouble() * 120 - 10; // includes negatives
        final points = random.nextDouble() * 5000 - 500;
        final config = loyalty(
          enabled: random.nextBool(),
          spendPerPoint: [0.0, 1.0, 50.0, 100.0][random.nextInt(4)],
          pointsPerSpend: [0.0, 1.0, 5.0][random.nextInt(3)],
          redemptionValue: [0.0, 0.25, 1.0, 10.0][random.nextInt(4)],
          maxPercent: [0.0, 25.0, 50.0, 100.0, 500.0][random.nextInt(5)],
          minBill: [0.0, 100.0, 1e6][random.nextInt(3)],
        );

        final totals = SalePricing.compute(
          lineItemTotal: lineTotal,
          settings: settings(
            taxMode: modes[random.nextInt(modes.length)],
            taxRate: rates[random.nextInt(rates.length)],
          ),
          loyalty: config,
          requestedDiscountPercent: percent,
          availablePoints: points,
          redeemPoints: random.nextBool(),
        );

        expectSane(totals, lineItemTotal: lineTotal, on: 'seed 778899 iter $i');
      }
    });
  });
}
