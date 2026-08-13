import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:atomid/core/utils/app_error.dart';
import 'package:atomid/data/models/loyalty_settings_model.dart';
import 'package:atomid/data/models/settings_model.dart';
import 'package:atomid/domain/pricing.dart';
import 'package:atomid/domain/services/sale_service.dart';
import 'package:atomid/domain/services/session_service.dart';
import 'package:atomid/presentation/providers/cart_notifier.dart';

import '../support/test_store.dart';

class MockSessionService extends Mock implements SessionService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestStore store;
  late SaleService service;
  late MockSessionService session;

  setUp(() async {
    store = await TestStore.open();
    session = MockSessionService();
    when(() => session.deviceId).thenReturn('dev_test_abcd');
    service = SaleService(store.repository, session);
  });

  tearDown(() => store.close());

  group('checkout', () {
    test(
      'records the sale, deducts stock and settles the customer ledger',
      () async {
        final product = await store.addProduct(price: 250, quantity: 10);
        final customer = await store.addCustomer();

        final sale = await service.checkout(
          CheckoutRequest(
            items: [
              CartItem(
                product: product,
                variant: product.variants.first,
                quantity: 2,
              ),
            ],
            customer: customer,
            paymentMethod: 'Cash',
          ),
        );

        expect(sale.grandTotal, 500);
        expect(store.repository.getAllSales(), hasLength(1));

        final stored = store.repository.getProductById(product.id)!;
        expect(stored.variants.first.quantity, 8);

        // Cash sale: debited then credited, so the customer owes nothing.
        final ledger = store.repository.getLedgerForCustomer(customer.id);
        expect(ledger, hasLength(2));
        expect(
          store.repository.getCustomerById(customer.id)!.currentBalance,
          0,
        );
      },
    );

    test('a credit sale leaves the balance outstanding', () async {
      final product = await store.addProduct(price: 300, quantity: 5);
      final customer = await store.addCustomer(creditLimit: 5000);

      await service.checkout(
        CheckoutRequest(
          items: [CartItem(product: product, variant: product.variants.first)],
          customer: customer,
          paymentMethod: 'Credit',
        ),
      );

      expect(
        store.repository.getCustomerById(customer.id)!.currentBalance,
        300,
      );
    });

    test('refuses a credit sale that would breach the credit limit', () async {
      final product = await store.addProduct(price: 900, quantity: 5);
      final customer = await store.addCustomer(creditLimit: 500);

      await expectLater(
        service.checkout(
          CheckoutRequest(
            items: [
              CartItem(product: product, variant: product.variants.first),
            ],
            customer: customer,
            paymentMethod: 'Credit',
          ),
        ),
        throwsA(isA<AppException>()),
      );

      expect(store.repository.getAllSales(), isEmpty);
    });

    test('refuses to sell more than is on the shelf', () async {
      final product = await store.addProduct(quantity: 2);

      await expectLater(
        service.checkout(
          CheckoutRequest(
            items: [
              CartItem(
                product: product,
                variant: product.variants.first,
                quantity: 5,
              ),
            ],
            paymentMethod: 'Cash',
          ),
        ),
        throwsA(isA<AppException>()),
      );

      expect(store.repository.getAllSales(), isEmpty);
      expect(
        store.repository.getProductById(product.id)!.variants.first.quantity,
        2,
      );
    });

    test('unwinds completely when a later line fails', () async {
      // First line is fine; the second has been emptied since it was scanned,
      // so the whole basket must roll back rather than half-commit.
      final good = await store.addProduct(
        name: 'Good',
        code: 'G-1',
        barcode: 'BC-GOOD',
        quantity: 10,
      );
      final scarce = await store.addProduct(
        name: 'Scarce',
        code: 'S-1',
        barcode: 'BC-SCARCE',
        quantity: 1,
      );

      final basket = [
        CartItem(product: good, variant: good.variants.first, quantity: 1),
        CartItem(product: scarce, variant: scarce.variants.first, quantity: 1),
      ];

      // Drain the scarce line behind the basket's back.
      await store.repository.performStockOut(
        productId: scarce.id,
        variantBarcode: 'BC-SCARCE',
        quantity: 1,
        reason: 'Sold elsewhere',
      );

      await expectLater(
        service.checkout(CheckoutRequest(items: basket, paymentMethod: 'Cash')),
        throwsA(isA<AppException>()),
      );

      expect(store.repository.getAllSales(), isEmpty);
      expect(
        store.repository.getProductById(good.id)!.variants.first.quantity,
        10,
        reason: 'the successful line must be put back',
      );
    });

    test('rejects an empty basket', () async {
      await expectLater(
        service.checkout(
          const CheckoutRequest(items: [], paymentMethod: 'Cash'),
        ),
        throwsA(isA<AppException>()),
      );
    });

    test('awards loyalty points once the programme is switched on', () async {
      await store.repository.saveLoyaltySettings(
        LoyaltySettingsModel(
          isLoyaltyEnabled: true,
          spendAmountForPoint: 100,
          pointsEarnedPerSpend: 5,
        ),
      );

      final product = await store.addProduct(price: 500, quantity: 5);
      final customer = await store.addCustomer();

      await service.checkout(
        CheckoutRequest(
          items: [CartItem(product: product, variant: product.variants.first)],
          customer: customer,
          paymentMethod: 'Cash',
        ),
      );

      expect(
        store.repository.getCustomerById(customer.id)!.totalRewardPoints,
        25,
      );
    });

    test('invoice numbers advance and carry the device tag', () async {
      final product = await store.addProduct(quantity: 20);

      final first = await service.checkout(
        CheckoutRequest(
          items: [CartItem(product: product, variant: product.variants.first)],
          paymentMethod: 'Cash',
        ),
      );
      final second = await service.checkout(
        CheckoutRequest(
          items: [CartItem(product: product, variant: product.variants.first)],
          paymentMethod: 'Cash',
        ),
      );

      expect(first.invoiceNumber, contains('ABCD'));
      expect(first.invoiceNumber, endsWith('0001'));
      expect(second.invoiceNumber, endsWith('0002'));
    });
  });

  group('preview', () {
    test('matches what checkout ultimately charges', () async {
      await store.repository.saveSettings(
        SettingsModel(taxRate: 5, taxMode: TaxMode.exclusive),
      );

      final product = await store.addProduct(price: 200, quantity: 10);
      final request = CheckoutRequest(
        items: [
          CartItem(
            product: product,
            variant: product.variants.first,
            quantity: 3,
          ),
        ],
        paymentMethod: 'Cash',
        discountPercent: 12.5,
      );

      final preview = service.preview(request);
      final sale = await service.checkout(request);

      expect(preview.grandTotal, sale.grandTotal);
      // 600 subtotal, 12.5% off = 75, then 5% tax added on 525.
      expect(sale.discountAmount, 75);
      expect(sale.grandTotal, 551.25);
    });
  });
}
