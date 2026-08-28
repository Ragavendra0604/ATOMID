import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:atomid/core/utils/app_error.dart';
import 'package:atomid/data/models/customer_stats.dart';
import 'package:atomid/data/repositories/storage_repository.dart';
import 'package:atomid/domain/services/customer_service.dart';
import 'package:atomid/domain/services/sale_service.dart';
import 'package:atomid/domain/services/session_service.dart';
import 'package:atomid/presentation/providers/cart_notifier.dart';

import '../support/test_store.dart';

class MockSessionService extends Mock implements SessionService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestStore store;
  late CustomerService customers;
  late SaleService sales;

  setUp(() async {
    store = await TestStore.open(configureShop: true);
    final session = MockSessionService();
    when(() => session.deviceId).thenReturn('dev_test_abcd');
    customers = CustomerService(store.repository, session);
    sales = SaleService(store.repository, session);
  });

  tearDown(() => store.close());

  group('mobile normalisation', () {
    test('the same person is found however the number was typed', () {
      for (final written in [
        '9876543210',
        '98765 43210',
        '+91 98765 43210',
        '+91-98765-43210',
        '09876543210',
        '(98765) 43210',
      ]) {
        expect(
          StorageRepository.normaliseMobile(written),
          '9876543210',
          reason: '"$written" should resolve to the same number',
        );
      }
    });

    test('a partial number is not treated as a match', () {
      expect(store.repository.getCustomerByMobile('98765'), isNull);
    });
  });

  group('lookup', () {
    test('finds a customer by their phone number', () async {
      final saved = await store.addCustomer(name: 'Asha', mobile: '9876543210');

      expect(customers.findByMobile('9876543210')?.id, saved.id);
      expect(customers.findByMobile('+91 98765 43210')?.id, saved.id);
      expect(customers.findByMobile('9000000000'), isNull);
    });

    test('a corrected number stops matching the old one', () async {
      final customer = await store.addCustomer(mobile: '9876543210');

      customer.mobile = '9111111111';
      await store.repository.saveCustomer(customer);

      expect(customers.findByMobile('9876543210'), isNull);
      expect(customers.findByMobile('9111111111')?.id, customer.id);
    });
  });

  group('registerByMobile', () {
    test('a number alone is enough to create a customer', () async {
      final created = await customers.registerByMobile('9876543210');

      expect(created.mobile, '9876543210');
      expect(created.name, isNotEmpty);
      expect(customers.findByMobile('9876543210')?.id, created.id);
    });

    test('a name is used when the cashier has time to type one', () async {
      final created = await customers.registerByMobile(
        '9876543210',
        name: 'Asha Menon',
      );
      expect(created.name, 'Asha Menon');
    });

    test('registering a known number returns the existing record', () async {
      final first = await customers.registerByMobile('9876543210');
      final second = await customers.registerByMobile('98765 43210');

      expect(second.id, first.id);
      expect(store.repository.getAllCustomers(), hasLength(1));
    });

    test('a short number is refused', () async {
      await expectLater(
        customers.registerByMobile('98765'),
        throwsA(isA<AppException>()),
      );
    });
  });

  group('visit history', () {
    test('a new customer shows no history', () async {
      final customer = await store.addCustomer();
      final stats = customers.statsFor(customer.id);

      expect(stats.visits, 0);
      expect(stats.isReturning, isFalse);
      expect(stats.standing, 'First visit');
      expect(stats.nextVisitLabel, '1st visit');
    });

    test('counts purchases and totals what they spent', () async {
      final product = await store.addProduct(price: 200, quantity: 50);
      final customer = await store.addCustomer();

      for (var i = 0; i < 3; i++) {
        await sales.checkout(
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
      }

      final stats = customers.statsFor(customer.id);
      expect(stats.visits, 3);
      expect(stats.totalSpend, 1200);
      expect(stats.averageBasket, 400);
      expect(stats.lastVisit, isNotNull);
      expect(stats.nextVisitLabel, '4th visit');
    });

    test('a walk-in sale is not counted against anybody', () async {
      final product = await store.addProduct(quantity: 10);
      final customer = await store.addCustomer();

      await sales.checkout(
        CheckoutRequest(
          items: [CartItem(product: product, variant: product.variants.first)],
          paymentMethod: 'Cash',
        ),
      );

      expect(customers.statsFor(customer.id).visits, 0);
    });

    test('a rolled-back sale leaves no trace in the history', () async {
      final product = await store.addProduct(price: 100, quantity: 1);
      final customer = await store.addCustomer(creditLimit: 10);

      // Credit limit is breached, so nothing should commit.
      await expectLater(
        sales.checkout(
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

      expect(customers.statsFor(customer.id).visits, 0);
    });

    test('standing describes how established the customer is', () {
      expect(const CustomerVisitStats(visits: 0).standing, 'First visit');
      expect(const CustomerVisitStats(visits: 1).standing, 'Second visit');
      expect(const CustomerVisitStats(visits: 3).standing, 'Occasional');
      expect(const CustomerVisitStats(visits: 8).standing, 'Regular');
      expect(const CustomerVisitStats(visits: 40).standing, 'Loyal');
    });

    test('the ordinal reads correctly around the teens', () {
      expect(const CustomerVisitStats(visits: 1).nextVisitLabel, '2nd visit');
      expect(const CustomerVisitStats(visits: 2).nextVisitLabel, '3rd visit');
      expect(const CustomerVisitStats(visits: 10).nextVisitLabel, '11th visit');
      expect(const CustomerVisitStats(visits: 11).nextVisitLabel, '12th visit');
      expect(const CustomerVisitStats(visits: 12).nextVisitLabel, '13th visit');
      expect(const CustomerVisitStats(visits: 20).nextVisitLabel, '21st visit');
    });
  });

  group('percentage discount at checkout', () {
    test('the applied percentage and amount are both recorded', () async {
      final product = await store.addProduct(price: 500, quantity: 10);
      final customer = await store.addCustomer();

      final sale = await sales.checkout(
        CheckoutRequest(
          items: [
            CartItem(
              product: product,
              variant: product.variants.first,
              quantity: 4,
            ),
          ],
          customer: customer,
          paymentMethod: 'Cash',
          discountPercent: 10,
        ),
      );

      expect(sale.subtotal, 2000);
      expect(sale.discountPercent, 10);
      expect(sale.discountAmount, 200);
      expect(sale.grandTotal, 1800);
    });
  });
}
