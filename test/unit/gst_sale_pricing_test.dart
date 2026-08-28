import 'package:flutter_test/flutter_test.dart';
import 'package:atomid/data/models/company_model.dart';
import 'package:atomid/data/models/customer_model.dart';
import 'package:atomid/data/models/loyalty_settings_model.dart';
import 'package:atomid/data/models/product_model.dart';
import 'package:atomid/data/models/settings_model.dart';
import 'package:atomid/domain/cart_item.dart';
import 'package:atomid/domain/gst/gst_treatment.dart';
import 'package:atomid/domain/pricing.dart';

void main() {
  final now = DateTime.now();

  final company = CompanyModel(
    name: 'Tamil Garments',
    gstNumber: '33AAAAA0000A1Z5',
    state: 'Tamil Nadu',
    stateCode: '33',
    address: '123 Cloth Bazar, Madurai',
  );

  final settings = SettingsModel(
    taxMode: TaxMode.inclusive,
    currencySymbol: '₹',
    roundOffEnabled: true,
    walkInPosPolicy: 'USE_SHOP_STATE',
  );

  final loyalty = LoyaltySettingsModel(isLoyaltyEnabled: false);

  Product makeProduct({
    required String id,
    required String name,
    required double price,
    required double gstRate,
    String hsn = '6204',
  }) {
    return Product(
      id: id,
      productName: name,
      productCode: 'PROD-$id',
      brand: 'Atom',
      color: 'Blue',
      category: 'Dresses',
      hsn: hsn,
      uqc: 'PCS',
      gstTreatment: GstTreatment.taxable,
      gstRate: gstRate,
      createdDate: now,
      updatedDate: now,
      variants: [
        ProductVariant(
          size: 'M',
          price: price,
          costPrice: price * 0.6,
          quantity: 10,
          barcode: 'BAR-$id',
          sku: 'SKU-$id',
        ),
      ],
    );
  }

  group('SalePricing.computeCart() POS calculations', () {
    test('Walk-in customer defaults to shop state (Intra-State)', () {
      final p1 = makeProduct(
        id: '1',
        name: 'Cotton Top',
        price: 1050,
        gstRate: 5.0,
      );
      final item1 = CartItem(
        product: p1,
        variant: p1.variants.first,
        quantity: 1,
      );

      final totals = SalePricing.computeCart(
        items: [item1],
        settings: settings,
        loyalty: loyalty,
        company: company,
      );

      expect(totals.isInterState, false);
      expect(totals.isUtgst, false);
      expect(totals.placeOfSupply, 'Tamil Nadu');
      expect(totals.taxableAmount, 1000.0);
      expect(totals.cgstAmount, 25.0);
      expect(totals.sgstAmount, 25.0);
      expect(totals.igstAmount, 0.0);
      expect(totals.grandTotal, 1050.0);
    });

    test('B2B customer from Karnataka triggers Inter-State IGST', () {
      final p1 = makeProduct(
        id: '1',
        name: 'Silk Kurti',
        price: 2240,
        gstRate: 12.0,
      );
      final item1 = CartItem(
        product: p1,
        variant: p1.variants.first,
        quantity: 1,
      );

      final customer = Customer(
        id: 'cust-1',
        name: 'Bengaluru Fashion Mart',
        code: 'CUST-01',
        mobile: '9876543210',
        gstNumber: '29ABCDE1234F1Z5',
        state: 'Karnataka',
        stateCode: '29',
        createdDate: now,
      );

      final totals = SalePricing.computeCart(
        items: [item1],
        settings: settings,
        loyalty: loyalty,
        company: company,
        customer: customer,
      );

      expect(totals.isInterState, true);
      expect(totals.placeOfSupply, 'Karnataka');
      expect(totals.taxableAmount, 2000.0);
      expect(totals.cgstAmount, 0.0);
      expect(totals.sgstAmount, 0.0);
      expect(totals.igstAmount, 240.0);
      expect(totals.grandTotal, 2240.0);
    });

    test(
      'Multiple items with mixed GST rates compute composite bill accurately',
      () {
        final p1 = makeProduct(
          id: '1',
          name: 'Dress 5%',
          price: 1050,
          gstRate: 5.0,
        );
        final p2 = makeProduct(
          id: '2',
          name: 'Dress 12%',
          price: 1120,
          gstRate: 12.0,
        );

        final item1 = CartItem(
          product: p1,
          variant: p1.variants.first,
          quantity: 1,
        );

        final item2 = CartItem(
          product: p2,
          variant: p2.variants.first,
          quantity: 1,
        );

        final totals = SalePricing.computeCart(
          items: [item1, item2],
          settings: settings,
          loyalty: loyalty,
          company: company,
        );

        // p1 taxable: 1000, cgst: 25, sgst: 25
        // p2 taxable: 1000, cgst: 60, sgst: 60
        expect(totals.subtotal, 2170.0);
        expect(totals.taxableAmount, 2000.0);
        expect(totals.cgstAmount, 85.0);
        expect(totals.sgstAmount, 85.0);
        expect(totals.grandTotal, 2170.0);
      },
    );
  });
}
