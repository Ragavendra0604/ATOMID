import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:atomid/data/models/company_model.dart';
import 'package:atomid/data/models/loyalty_settings_model.dart';
import 'package:atomid/data/models/product_model.dart';
import 'package:atomid/data/models/settings_model.dart';
import 'package:atomid/domain/cart_item.dart';
import 'package:atomid/domain/gst/gst_treatment.dart';
import 'package:atomid/domain/pricing.dart';
import 'package:atomid/domain/services/sale_service.dart';
import 'package:atomid/domain/services/session_service.dart';

import '../support/test_store.dart';

class MockSessionService extends Mock implements SessionService {}

/// The shop's own state, and what happens when it has not been set.
///
/// `SalePricing.computeCart` used to substitute Tamil Nadu / 33 whenever the
/// business had no state configured. A shop anywhere else that had not
/// finished setup billed CGST + SGST against a state it had never chosen, and
/// the invoice looked completely ordinary — which is the dangerous part.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime(2026, 3, 1);
  final loyalty = LoyaltySettingsModel(isLoyaltyEnabled: false);

  // Built per call: a HiveObject remembers the box it was written to, so one
  // shared instance saved into a second test's store throws.
  SettingsModel makeSettings() => SettingsModel(
    taxMode: TaxMode.inclusive,
    currencySymbol: '₹',
    roundOffEnabled: true,
    walkInPosPolicy: 'USE_SHOP_STATE',
  );

  Product product() => Product(
    id: 'p1',
    productName: 'Cotton Kurti',
    productCode: 'PROD-1',
    brand: 'Atom',
    color: 'Blue',
    category: 'Dresses',
    hsn: '6204',
    uqc: 'PCS',
    gstTreatment: GstTreatment.taxable,
    gstRate: 5.0,
    createdDate: now,
    updatedDate: now,
    variants: [
      ProductVariant(
        size: 'M',
        price: 1050,
        costPrice: 600,
        quantity: 10,
        barcode: 'BAR-1',
        sku: 'SKU-1',
      ),
    ],
  );

  SaleTotals ring(CompanyModel company) {
    final p = product();
    return SalePricing.computeCart(
      items: [CartItem(product: p, variant: p.variants.first, quantity: 1)],
      settings: makeSettings(),
      loyalty: loyalty,
      company: company,
      transactionDate: now,
    );
  }

  group('a shop that has not been set up', () {
    test('cannot bill, and says what to do', () {
      final totals = ring(CompanyModel(name: 'Brand New Shop'));

      expect(totals.gstResult!.isValid, false);
      expect(
        totals.gstResult!.errors.any(
          (e) => e.contains('Configure your shop state before billing'),
        ),
        true,
        reason: 'the message must tell the owner what to fix',
      );
    });

    test('is never quietly treated as Tamil Nadu', () {
      final totals = ring(CompanyModel(name: 'Brand New Shop'));

      // The old fallback produced a perfectly ordinary intra-state bill.
      expect(totals.gstResult!.placeOfSupplyCode, '');
      expect(totals.placeOfSupply, '');
      expect(totals.cgstAmount, 0.0);
      expect(totals.sgstAmount, 0.0);
      expect(totals.igstAmount, 0.0);
      expect(totals.taxAmount, 0.0);
    });

    test('a state alone is enough — no GSTIN needed', () {
      // An unregistered shop under the threshold still has to say where it is.
      final totals = ring(
        CompanyModel(name: 'Small Shop', state: 'Kerala', stateCode: '32'),
      );

      expect(totals.gstResult!.isValid, true);
      expect(totals.placeOfSupply, 'Kerala');
    });
  });

  group('a configured shop bills normally', () {
    test('Tamil Nadu (33)', () {
      final totals = ring(
        CompanyModel(
          name: 'Tamil Garments',
          gstNumber: '33AAAAA0000A1Z5',
          state: 'Tamil Nadu',
          stateCode: '33',
        ),
      );

      expect(totals.gstResult!.isValid, true);
      expect(totals.placeOfSupply, 'Tamil Nadu');
      expect(totals.isInterState, false);
      expect(totals.taxableAmount, 1000.0);
      expect(totals.cgstAmount, 25.0);
      expect(totals.sgstAmount, 25.0);
      expect(totals.grandTotal, 1050.0);
    });

    test('Karnataka (29)', () {
      final totals = ring(
        CompanyModel(
          name: 'Bengaluru Silks',
          gstNumber: '29AAAAA0000A1Z5',
          state: 'Karnataka',
          stateCode: '29',
        ),
      );

      expect(totals.gstResult!.isValid, true);
      // The point of the fix: the bill follows the shop, not a constant.
      expect(totals.placeOfSupply, 'Karnataka');
      expect(totals.isInterState, false);
      expect(totals.taxableAmount, 1000.0);
      expect(totals.cgstAmount, 25.0);
      expect(totals.sgstAmount, 25.0);
      expect(totals.grandTotal, 1050.0);
    });
  });

  group('after setup, ordinary billing is unchanged', () {
    late TestStore store;
    late SaleService saleService;

    setUp(() async {
      store = await TestStore.open(configureShop: true);
      final session = MockSessionService();
      when(() => session.deviceId).thenReturn('dev_test_abcd');
      await store.repository.saveSettings(makeSettings());
      saleService = SaleService(store.repository, session);
    });
    tearDown(() => store.close());

    test('a walk-in sale needs no customer, GSTIN or state', () async {
      final p = product();
      await store.repository.saveProduct(p);

      final sale = await saleService.checkout(
        CheckoutRequest(
          items: [CartItem(product: p, variant: p.variants.first, quantity: 1)],
          paymentMethod: 'Cash',
        ),
      );

      expect(sale.placeOfSupply, 'Tamil Nadu');
      expect(sale.taxableAmount, 1000.0);
      expect(sale.cgstAmount, 25.0);
      expect(sale.sgstAmount, 25.0);
      expect(sale.grandTotal, 1050.0);
    });

    test('an old invoice does not move when the shop state changes', () async {
      final p = product();
      await store.repository.saveProduct(p);

      final sale = await saleService.checkout(
        CheckoutRequest(
          items: [CartItem(product: p, variant: p.variants.first, quantity: 1)],
          paymentMethod: 'Cash',
        ),
      );

      final frozen = {
        'sellerState': sale.sellerState,
        'pos': sale.placeOfSupply,
        'cgst': sale.cgstAmount,
        'sgst': sale.sgstAmount,
        'igst': sale.igstAmount,
        'grand': sale.grandTotal,
      };

      // The shop relocates, and its old invoices must not follow.
      await store.repository.saveCompany(
        CompanyModel(
          name: 'Relocated Store',
          gstNumber: '29AAAAA0000A1Z5',
          state: 'Karnataka',
          stateCode: '29',
        ),
      );

      final reread = store.repository.getSaleById(sale.id)!;
      expect(reread.sellerState, frozen['sellerState']);
      expect(reread.placeOfSupply, frozen['pos']);
      expect(reread.cgstAmount, frozen['cgst']);
      expect(reread.sgstAmount, frozen['sgst']);
      expect(reread.igstAmount, frozen['igst']);
      expect(reread.grandTotal, frozen['grand']);
    });
  });
}
