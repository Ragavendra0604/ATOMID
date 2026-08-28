import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:atomid/core/utils/app_error.dart';
import 'package:atomid/data/models/company_model.dart';
import 'package:atomid/data/models/customer_model.dart';
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

/// Cover for Place of Supply derived from a customer's GSTIN, and for the
/// guarantees that must survive it: walk-in billing stays customer-free, and a
/// finalized invoice never moves.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime.now();

  // Built fresh on each call. A HiveObject remembers the box it was put in,
  // so one shared instance saved into a second test's store fails with
  // "the same instance of a HiveObject cannot be stored in two different
  // boxes".
  CompanyModel makeCompany() => CompanyModel(
    name: 'Tamil Garments',
    gstNumber: '33AAAAA0000A1Z5',
    state: 'Tamil Nadu',
    stateCode: '33',
    address: '123 Cloth Bazar, Madurai',
  );

  SettingsModel makeSettings() => SettingsModel(
    taxMode: TaxMode.inclusive,
    currencySymbol: '₹',
    roundOffEnabled: true,
    walkInPosPolicy: 'USE_SHOP_STATE',
  );

  final company = makeCompany();
  final settings = makeSettings();

  final loyalty = LoyaltySettingsModel(isLoyaltyEnabled: false);

  Product makeProduct({
    String id = 'p1',
    double price = 2240,
    double? gstRate = 12.0,
    String treatment = GstTreatment.taxable,
  }) {
    return Product(
      id: id,
      productName: 'Silk Kurti',
      productCode: 'PROD-$id',
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
          quantity: 20,
          barcode: 'BAR-$id',
          sku: 'SKU-$id',
        ),
      ],
    );
  }

  Customer makeCustomer({
    String gstin = '',
    String state = '',
    String stateCode = '',
  }) {
    return Customer(
      id: 'cust-1',
      name: 'Bengaluru Fashion Mart',
      code: 'CUST-01',
      mobile: '9876543210',
      gstNumber: gstin,
      state: state,
      stateCode: stateCode,
      createdDate: now,
    );
  }

  SaleTotals cartOf({Customer? customer, Product? product}) {
    final p = product ?? makeProduct();
    return SalePricing.computeCart(
      items: [CartItem(product: p, variant: p.variants.first, quantity: 1)],
      settings: settings,
      loyalty: loyalty,
      company: company,
      customer: customer,
    );
  }

  group('Place of Supply from the customer GSTIN', () {
    test('A — a valid GSTIN supplies the state when none is recorded', () {
      final totals = cartOf(customer: makeCustomer(gstin: '29ABCDE1234F1Z5'));

      expect(totals.gstResult!.isValid, true);
      expect(totals.gstResult!.placeOfSupplyCode, '29');
      expect(totals.placeOfSupply, 'Karnataka');
      expect(
        totals.gstResult!.placeOfSupplyBasis,
        'Customer GSTIN State Prefix',
      );
      expect(totals.isInterState, true);
      expect(totals.taxableAmount, 2000.0);
      expect(totals.igstAmount, 240.0);
      expect(totals.cgstAmount, 0.0);
      expect(totals.sgstAmount, 0.0);
    });

    test('B — a GSTIN agreeing with the recorded state resolves cleanly', () {
      final totals = cartOf(
        customer: makeCustomer(
          gstin: '33AAAAA0000A1Z5',
          state: 'Tamil Nadu',
          stateCode: '33',
        ),
      );

      expect(totals.gstResult!.isValid, true);
      expect(totals.gstResult!.errors, isEmpty);
      expect(totals.gstResult!.placeOfSupplyCode, '33');
      expect(totals.isInterState, false);
      expect(totals.cgstAmount, 120.0);
      expect(totals.sgstAmount, 120.0);
      expect(totals.igstAmount, 0.0);
    });

    test('C — a GSTIN conflicting with the recorded state blocks the bill', () {
      final totals = cartOf(
        customer: makeCustomer(
          gstin: '33AAAAA0000A1Z5',
          state: 'Karnataka',
          stateCode: '29',
        ),
      );

      expect(totals.gstResult!.isValid, false);
      expect(
        totals.gstResult!.errors.any((e) => e.contains('do not agree')),
        true,
      );
      // Neither side was silently chosen.
      expect(totals.gstResult!.placeOfSupplyCode, '');
    });

    test('C2 — a state NAME conflicting with the GSTIN also blocks', () {
      final totals = cartOf(
        customer: makeCustomer(gstin: '33AAAAA0000A1Z5', state: 'Karnataka'),
      );

      expect(totals.gstResult!.isValid, false);
      expect(
        totals.gstResult!.errors.any((e) => e.contains('do not agree')),
        true,
      );
    });

    test('D — an invalid GSTIN yields no state and an actionable error', () {
      final totals = cartOf(customer: makeCustomer(gstin: 'NOTAGSTIN123'));

      expect(totals.gstResult!.isValid, false);
      expect(
        totals.gstResult!.errors.any((e) => e.contains('not a valid GSTIN')),
        true,
      );
      expect(totals.gstResult!.placeOfSupplyCode, '');
    });

    test('D2 — an invalid GSTIN does not block a customer with a state', () {
      final totals = cartOf(
        customer: makeCustomer(
          gstin: 'NOTAGSTIN123',
          state: 'Karnataka',
          stateCode: '29',
        ),
      );

      // Nothing is derived from the bad number, but the recorded state still
      // answers the question, so the sale is not held up.
      expect(totals.gstResult!.isValid, true);
      expect(totals.gstResult!.placeOfSupplyCode, '29');
      expect(totals.isInterState, true);
    });

    test('an explicit destination still outranks the GSTIN', () {
      final p = makeProduct();
      final totals = SalePricing.computeCart(
        items: [CartItem(product: p, variant: p.variants.first, quantity: 1)],
        settings: settings,
        loyalty: loyalty,
        company: company,
        customer: makeCustomer(gstin: '29ABCDE1234F1Z5'),
        destinationStateCode: '27',
      );

      expect(totals.gstResult!.isValid, true);
      expect(totals.gstResult!.placeOfSupplyCode, '27');
    });
  });

  group('walk-in billing is untouched', () {
    test('no customer at all still bills at the shop state', () {
      final p = makeProduct(price: 1050, gstRate: 5.0);
      final totals = SalePricing.computeCart(
        items: [CartItem(product: p, variant: p.variants.first, quantity: 1)],
        settings: settings,
        loyalty: loyalty,
        company: company,
      );

      expect(totals.gstResult!.isValid, true);
      expect(totals.isInterState, false);
      expect(totals.placeOfSupply, 'Tamil Nadu');
      expect(totals.cgstAmount, 25.0);
      expect(totals.sgstAmount, 25.0);
      expect(totals.grandTotal, 1050.0);
    });

    test('a named customer with no GSTIN and no state still bills', () {
      final p = makeProduct(price: 1050, gstRate: 5.0);
      final totals = SalePricing.computeCart(
        items: [CartItem(product: p, variant: p.variants.first, quantity: 1)],
        settings: settings,
        loyalty: loyalty,
        company: company,
        customer: makeCustomer(),
      );

      expect(totals.gstResult!.isValid, true);
      expect(totals.placeOfSupply, 'Tamil Nadu');
      expect(totals.grandTotal, 1050.0);
    });
  });

  group('checkout and history', () {
    late TestStore store;
    late SaleService saleService;
    late MockSessionService session;

    setUp(() async {
      store = await TestStore.open();
      session = MockSessionService();
      when(() => session.deviceId).thenReturn('dev_test_abcd');
      await store.repository.saveCompany(makeCompany());
      await store.repository.saveSettings(makeSettings());
      saleService = SaleService(store.repository, session);
    });
    tearDown(() => store.close());

    test('E — an unconfigured product blocks preview and checkout', () async {
      final product = makeProduct(
        id: 'unconf',
        price: 500,
        gstRate: null,
        treatment: GstTreatment.unconfigured,
      );
      await store.repository.saveProduct(product);

      final req = CheckoutRequest(
        items: [
          CartItem(
            product: product,
            variant: product.variants.first,
            quantity: 1,
          ),
        ],
        paymentMethod: 'Cash',
      );

      // Preview — what the cashier sees — is already blocked.
      final preview = saleService.preview(req);
      expect(preview.gstResult!.isValid, false);
      expect(
        preview.gstResult!.errors.any(
          (e) => e.contains('tax treatment is unconfigured'),
        ),
        true,
      );

      // And the sale cannot be committed at 0% or at any shop-wide rate.
      await expectLater(
        saleService.checkout(req),
        throwsA(isA<AppException>()),
      );
      expect(store.repository.getAllSales(), isEmpty);
    });

    test('a finalized invoice does not move when the world changes', () async {
      final product = makeProduct(id: 'hist', price: 1050, gstRate: 5.0);
      await store.repository.saveProduct(product);

      final customer = makeCustomer(
        gstin: '32AABCK9999P1Z1',
        state: 'Kerala',
        stateCode: '32',
      );
      await store.repository.saveCustomer(customer);

      final sale = await saleService.checkout(
        CheckoutRequest(
          items: [
            CartItem(
              product: product,
              variant: product.variants.first,
              quantity: 1,
            ),
          ],
          customer: customer,
          paymentMethod: 'Cash',
        ),
      );

      final frozen = {
        'taxable': sale.taxableAmount,
        'cgst': sale.cgstAmount,
        'sgst': sale.sgstAmount,
        'utgst': sale.utgstAmount,
        'igst': sale.igstAmount,
        'cess': sale.cessAmount,
        'preRound': sale.preRoundTotal,
        'roundOff': sale.roundOff,
        'grand': sale.grandTotal,
        'pos': sale.placeOfSupply,
        'sellerState': sale.sellerState,
        'lineRate': sale.items.first.gstRate,
        'lineTaxable': sale.items.first.taxableValue,
      };

      // Everything the invoice was derived from now changes.
      final stored = store.repository.getProductById(product.id)!;
      stored.gstRate = 28.0;
      stored.gstTreatment = GstTreatment.taxable;
      stored.variants.first.price = 5000.0;
      await store.repository.saveProduct(stored);

      await store.repository.saveSettings(
        SettingsModel(
          taxMode: TaxMode.exclusive,
          currencySymbol: r'$',
          roundOffEnabled: false,
          taxRate: 18.0,
          walkInPosPolicy: 'REQUIRE_STATE',
        ),
      );

      await store.repository.saveCompany(
        CompanyModel(
          name: 'Renamed Traders',
          gstNumber: '29AAAAA0000A1Z5',
          state: 'Karnataka',
          stateCode: '29',
        ),
      );

      final storedCustomer = store.repository.getCustomerById(customer.id)!;
      storedCustomer.state = 'Maharashtra';
      storedCustomer.stateCode = '27';
      storedCustomer.gstNumber = '27ABCDE1234F1Z5';
      await store.repository.saveCustomer(storedCustomer);

      final reread = store.repository.getSaleById(sale.id)!;
      expect(reread.taxableAmount, frozen['taxable']);
      expect(reread.cgstAmount, frozen['cgst']);
      expect(reread.sgstAmount, frozen['sgst']);
      expect(reread.utgstAmount, frozen['utgst']);
      expect(reread.igstAmount, frozen['igst']);
      expect(reread.cessAmount, frozen['cess']);
      expect(reread.preRoundTotal, frozen['preRound']);
      expect(reread.roundOff, frozen['roundOff']);
      expect(reread.grandTotal, frozen['grand']);
      expect(reread.placeOfSupply, frozen['pos']);
      expect(reread.sellerState, frozen['sellerState']);
      expect(reread.items.first.gstRate, frozen['lineRate']);
      expect(reread.items.first.taxableValue, frozen['lineTaxable']);
    });
  });
}
