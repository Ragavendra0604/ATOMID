import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:atomid/core/utils/app_error.dart';
import 'package:atomid/data/models/loyalty_settings_model.dart';
import 'package:atomid/domain/cart_item.dart';
import 'package:atomid/domain/services/customer_service.dart';
import 'package:atomid/domain/services/sale_service.dart';
import 'package:atomid/domain/services/session_service.dart';

import '../support/test_store.dart';

class MockSessionService extends Mock implements SessionService {}

/// Invariants, rather than examples.
///
/// Each of these states something that must hold after *any* sequence of
/// operations, and is asserted through [StorageRepository.auditDerivedState]
/// or by recomputing the value from its source. A test that only checks one
/// worked example passes right up until someone adds the seventh cache; a
/// test that checks "the derived state agrees with the boxes" keeps working.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestStore store;
  late SaleService sales;
  late CustomerService customers;

  setUp(() async {
    store = await TestStore.open();
    final session = MockSessionService();
    when(() => session.deviceId).thenReturn('dev_test_abcd');
    sales = SaleService(store.repository, session);
    customers = CustomerService(store.repository, session);
  });

  tearDown(() => store.close());

  /// The invariant every other test in this file leans on.
  void expectCoherent({String? after}) {
    expect(
      store.repository.auditDerivedState(),
      isEmpty,
      reason: after == null ? null : 'store became incoherent after $after',
    );
  }

  group('derived state agrees with stored records', () {
    test('after a plain sequence of local writes', () async {
      final product = await store.addProduct(price: 200, quantity: 20);
      final customer = await store.addCustomer(mobile: '9876543210');

      await sales.checkout(
        CheckoutRequest(
          items: [
            CartItem(
              product: product,
              variant: product.variants.first,
              quantity: 3,
            ),
          ],
          customer: customer,
          paymentMethod: 'Cash',
        ),
      );

      expectCoherent(after: 'a cash sale');
    });

    test('after a credit sale, which moves the ledger', () async {
      final product = await store.addProduct(price: 100, quantity: 10);
      final customer = await store.addCustomer(creditLimit: 5000);

      await sales.checkout(
        CheckoutRequest(
          items: [CartItem(product: product, variant: product.variants.first)],
          customer: customer,
          paymentMethod: 'Credit',
        ),
      );

      expectCoherent(after: 'a credit sale');
    });

    test('after a rolled-back checkout', () async {
      final product = await store.addProduct(price: 100, quantity: 1);
      final customer = await store.addCustomer(creditLimit: 10);

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

      expectCoherent(after: 'a checkout that was refused');
    });

    test('after a customer merge', () async {
      final a = await store.addCustomer(name: 'A', mobile: '9000000001');
      final b = await store.addCustomer(name: 'B', mobile: '9000000002');

      await store.repository.addLedgerEntry(
        customerId: b.id,
        date: DateTime.now(),
        transactionType: 'Sale',
        referenceId: 'INV-1',
        debit: 250,
      );

      await customers.mergeCustomers(a.id, b.id);

      expectCoherent(after: 'a customer merge');
    });

    test('after a customer merge that carried reward points', () async {
      final a = await store.addCustomer(name: 'A', mobile: '9000000003');
      final b = await store.addCustomer(name: 'B', mobile: '9000000004');

      await store.repository.addLoyaltyTransaction(
        customerId: b.id,
        transactionType: 'Earn',
        points: 30,
        monetaryValue: 0,
        reference: 'INV-2',
        createdBy: 'test',
      );

      await customers.mergeCustomers(a.id, b.id);

      // The merge used to add the secondary's points onto the primary as a
      // number while leaving its loyalty rows filed under the old id — a
      // stored total that disagrees with its own detail, which is the exact
      // class of corruption this audit exists to catch. It did not catch it
      // only because no test here had ever put points on either account.
      expectCoherent(after: 'a customer merge carrying reward points');
    });

    test('after products are edited and deleted', () async {
      final product = await store.addProduct(barcode: 'BC-1', quantity: 5);

      product.variants.first.price = 999;
      await store.repository.saveProduct(product);
      expectCoherent(after: 'editing a product');

      await store.repository.deleteProduct(product.id);
      expectCoherent(after: 'deleting a product');
    });

    test('after records arrive from the cloud', () async {
      final repo = store.repository;

      await repo.applyRemote('Customer', 'c1', {
        'id': 'c1',
        'code': 'C-1',
        'name': 'Remote',
        'mobile': '9111111111',
        'createdDate': DateTime(2026).toIso8601String(),
        'updatedAt': DateTime.now().toIso8601String(),
      });
      await repo.applyRemote('Sale', 's1', {
        'id': 's1',
        'invoiceNumber': 'INV-R1',
        'date': DateTime.now().toIso8601String(),
        'customerId': 'c1',
        'customerName': 'Remote',
        'subtotal': 400,
        'grandTotal': 400,
        'paymentMethod': 'Cash',
        'updatedAt': DateTime.now().toIso8601String(),
        'items': const [],
      });
      await repo.reconcileAfterPull();

      expectCoherent(after: 'a cloud pull');
    });
  });

  group('the audit actually detects incoherence', () {
    test('it is not just returning an empty list', () async {
      final customer = await store.addCustomer();

      // Corrupt the record behind the ledger's back: set a balance no ledger
      // entry explains. If the audit cannot see this, it proves nothing
      // anywhere else in this file.
      await store.repository.addLedgerEntry(
        customerId: customer.id,
        date: DateTime.now(),
        transactionType: 'Sale',
        referenceId: 'INV-1',
        debit: 100,
      );
      final stored = store.repository.getCustomerById(customer.id)!;
      stored.currentBalance = 999999;
      await store.repository.saveCustomer(stored);

      expect(
        store.repository.auditDerivedState(),
        isNotEmpty,
        reason: 'a balance its ledger cannot explain must be reported',
      );
    });
  });

  group('inventory is conserved', () {
    test('a refused checkout leaves stock exactly as it was', () async {
      final product = await store.addProduct(price: 100, quantity: 7);
      final customer = await store.addCustomer(creditLimit: 10);

      final before = store.repository
          .getProductById(product.id)!
          .variants
          .first
          .quantity;

      await expectLater(
        sales.checkout(
          CheckoutRequest(
            items: [
              CartItem(
                product: product,
                variant: product.variants.first,
                quantity: 2,
              ),
            ],
            customer: customer,
            paymentMethod: 'Credit',
          ),
        ),
        throwsA(isA<AppException>()),
      );

      expect(
        store.repository.getProductById(product.id)!.variants.first.quantity,
        before,
      );
    });

    test('stock out then stock in returns to the starting quantity', () async {
      final product = await store.addProduct(barcode: 'BC-1', quantity: 12);

      await store.repository.performStockOut(
        productId: product.id,
        variantBarcode: 'BC-1',
        quantity: 5,
        reason: 'test',
      );
      await store.repository.performStockIn(
        productId: product.id,
        variantBarcode: 'BC-1',
        quantity: 5,
        reason: 'test reversal',
      );

      expect(
        store.repository.getProductById(product.id)!.variants.first.quantity,
        12,
      );
      expectCoherent(after: 'a stock movement round trip');
    });
  });

  group('money is conserved', () {
    test('a customer balance always equals its ledger', () async {
      final customer = await store.addCustomer();

      for (var i = 0; i < 12; i++) {
        await store.repository.addLedgerEntry(
          customerId: customer.id,
          date: DateTime.now(),
          transactionType: i.isEven ? 'Sale' : 'Payment',
          referenceId: 'REF-$i',
          debit: i.isEven ? 33.33 : 0,
          credit: i.isEven ? 0 : 11.11,
        );
      }

      // Twelve entries of repeating decimals is where float drift would show
      // up if rounding were not applied at every step.
      expectCoherent(after: 'twelve fractional ledger entries');
    });

    test('loyalty points always equal their transactions', () async {
      await store.repository.saveLoyaltySettings(
        LoyaltySettingsModel(
          isLoyaltyEnabled: true,
          spendAmountForPoint: 100,
          pointsEarnedPerSpend: 5,
        ),
      );
      final product = await store.addProduct(price: 250, quantity: 50);
      final customer = await store.addCustomer();

      for (var i = 0; i < 4; i++) {
        await sales.checkout(
          CheckoutRequest(
            items: [
              CartItem(product: product, variant: product.variants.first),
            ],
            customer: customer,
            paymentMethod: 'Cash',
          ),
        );
      }

      expectCoherent(after: 'four point-earning sales');
    });
  });
}
