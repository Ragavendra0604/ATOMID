import 'package:flutter_test/flutter_test.dart';

import 'package:atomid/data/models/company_model.dart';
import 'package:atomid/data/models/loyalty_settings_model.dart';
import 'package:atomid/data/models/product_model.dart';
import 'package:atomid/data/models/settings_model.dart';
import 'package:atomid/domain/cart_item.dart';
import 'package:atomid/domain/gst/gst_treatment.dart';
import 'package:atomid/domain/pricing.dart';

/// Regression cover for the product GST rate fallback.
///
/// `SalePricing.computeCart` used to fall back to the shop-wide
/// `settings.taxRate` whenever a product's own rate was null or zero. That
/// broke the rule the engine is built on — UNCONFIGURED is not 0% — in both
/// directions: a product deliberately configured at 0% was billed at the shop
/// rate, and a product with no rate at all was billed at the shop rate instead
/// of stopping the sale.
void main() {
  final now = DateTime.now();

  final company = CompanyModel(
    name: 'Tamil Garments',
    gstNumber: '33AAAAA0000A1Z5',
    state: 'Tamil Nadu',
    stateCode: '33',
    address: '123 Cloth Bazar, Madurai',
  );

  final loyalty = LoyaltySettingsModel(isLoyaltyEnabled: false);

  SettingsModel shopWith(double globalTaxRate) => SettingsModel(
    taxMode: TaxMode.inclusive,
    currencySymbol: '₹',
    roundOffEnabled: true,
    walkInPosPolicy: 'USE_SHOP_STATE',
    taxRate: globalTaxRate,
  );

  Product makeProduct({
    required double price,
    required double? gstRate,
    String treatment = GstTreatment.taxable,
  }) {
    return Product(
      id: 'p1',
      productName: 'Cotton Kurti',
      productCode: 'PROD-1',
      brand: 'Atom',
      color: 'Blue',
      category: 'Dresses',
      hsn: '6204',
      uqc: 'PCS',
      gstTreatment: treatment,
      gstRate: gstRate,
      createdDate: now,
      updatedDate: now,
      variants: [
        ProductVariant(
          size: 'M',
          price: price,
          costPrice: price * 0.6,
          quantity: 10,
          barcode: 'BAR-1',
          sku: 'SKU-1',
        ),
      ],
    );
  }

  SaleTotals cartOf(Product product, SettingsModel settings) {
    return SalePricing.computeCart(
      items: [
        CartItem(
          product: product,
          variant: product.variants.first,
          quantity: 1,
        ),
      ],
      settings: settings,
      loyalty: loyalty,
      company: company,
    );
  }

  group('product GST rate is never taken from the shop-wide tax rate', () {
    test('A — an explicit 0% product does not inherit the shop 18%', () {
      final totals = cartOf(
        makeProduct(price: 1000, gstRate: 0.0),
        shopWith(18.0),
      );

      expect(totals.gstResult!.isValid, true);
      expect(totals.gstResult!.lines.first.gstRate, 0.0);
      expect(totals.cgstAmount, 0.0);
      expect(totals.sgstAmount, 0.0);
      expect(totals.igstAmount, 0.0);
      expect(totals.taxAmount, 0.0);
      expect(totals.taxableAmount, 1000.0);
      // The whole point: an 18% shop rate would have made this 1000/1.18.
      expect(totals.grandTotal, 1000.0);
    });

    test('B — a product with no rate is unresolved, not billed at 18%', () {
      final totals = cartOf(
        makeProduct(price: 1000, gstRate: null),
        shopWith(18.0),
      );

      expect(totals.gstResult!.isValid, false);
      expect(
        totals.gstResult!.errors.any(
          (e) => e.contains('no GST rate configured'),
        ),
        true,
      );
      // No tax was invented from the shop rate.
      expect(totals.cgstAmount, 0.0);
      expect(totals.sgstAmount, 0.0);
      expect(totals.taxAmount, 0.0);
    });

    test('C — an explicit 5% product overrides a shop rate of 18%', () {
      final totals = cartOf(
        makeProduct(price: 1050, gstRate: 5.0),
        shopWith(18.0),
      );

      expect(totals.gstResult!.isValid, true);
      expect(totals.gstResult!.lines.first.gstRate, 5.0);
      expect(totals.taxableAmount, 1000.0);
      expect(totals.cgstAmount, 25.0);
      expect(totals.sgstAmount, 25.0);
      expect(totals.grandTotal, 1050.0);
    });

    test('D — an explicit 18% product overrides a shop rate of 5%', () {
      final totals = cartOf(
        makeProduct(price: 1180, gstRate: 18.0),
        shopWith(5.0),
      );

      expect(totals.gstResult!.isValid, true);
      expect(totals.gstResult!.lines.first.gstRate, 18.0);
      expect(totals.taxableAmount, 1000.0);
      expect(totals.cgstAmount, 90.0);
      expect(totals.sgstAmount, 90.0);
      expect(totals.grandTotal, 1180.0);
    });

    test('a zero shop rate changes nothing for a configured product', () {
      final totals = cartOf(
        makeProduct(price: 1050, gstRate: 5.0),
        shopWith(0.0),
      );

      expect(totals.gstResult!.isValid, true);
      expect(totals.cgstAmount, 25.0);
      expect(totals.sgstAmount, 25.0);
      expect(totals.grandTotal, 1050.0);
    });

    test('an UNCONFIGURED product is unresolved whatever the shop rate', () {
      final totals = cartOf(
        makeProduct(
          price: 500,
          gstRate: null,
          treatment: GstTreatment.unconfigured,
        ),
        shopWith(18.0),
      );

      expect(totals.gstResult!.isValid, false);
      expect(
        totals.gstResult!.errors.any(
          (e) => e.contains('tax treatment is unconfigured'),
        ),
        true,
      );
    });

    test('exempt and nil-rated products stay untaxed under a shop rate', () {
      for (final treatment in [
        GstTreatment.exempt,
        GstTreatment.nilRated,
        GstTreatment.nonGst,
      ]) {
        final totals = cartOf(
          makeProduct(price: 1000, gstRate: 18.0, treatment: treatment),
          shopWith(18.0),
        );

        expect(totals.gstResult!.isValid, true, reason: treatment);
        expect(totals.taxAmount, 0.0, reason: treatment);
        expect(totals.grandTotal, 1000.0, reason: treatment);
      }
    });
  });
}
