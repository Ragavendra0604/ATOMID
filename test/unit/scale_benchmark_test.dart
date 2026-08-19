import 'package:flutter_test/flutter_test.dart';

import 'package:atomid/data/models/customer_model.dart';
import 'package:atomid/data/models/product_model.dart';
import 'package:atomid/data/models/sale_model.dart';

import '../support/test_store.dart';

/// Measurement for P-2 and P-3, which the audit deliberately left open with
/// "profile first, do not optimise on a hunch".
///
/// The concern was that list reads rescan and re-sort whole boxes on every
/// invalidation, and that a pull fires all eleven topics at once. That is only
/// a problem if it is actually slow at the scale a shop reaches, so this
/// builds a realistically large store and puts numbers on it.
///
/// The thresholds are deliberately loose — this is a regression guard against
/// something becoming pathological (an accidental O(n²), a lost cache), not a
/// benchmark to tune against. A CI runner is slower and noisier than a
/// developer machine, so a tight bound here would just be flaky.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestStore store;

  setUp(() async => store = await TestStore.open());
  tearDown(() => store.close());

  /// Roughly two years of trading for a small shop.
  Future<void> seed({
    required int products,
    required int customers,
    required int sales,
  }) async {
    final repo = store.repository;

    for (var i = 0; i < products; i++) {
      await repo.saveProduct(
        Product(
          id: 'p$i',
          productName: 'Product $i',
          productCode: 'PC-$i',
          category: 'General',
          brand: 'Brand',
          color: 'Red',
          createdDate: DateTime(2025, 1, 1),
          updatedDate: DateTime(2025, 1, 1),
          variants: [
            ProductVariant(
              size: 'M',
              price: 100 + (i % 50),
              quantity: 25,
              barcode: 'BC-$i',
            ),
          ],
        ),
      );
    }

    for (var i = 0; i < customers; i++) {
      await repo.saveCustomer(
        Customer(
          id: 'c$i',
          code: 'C-$i',
          name: 'Customer $i',
          mobile: (9000000000 + i).toString(),
          createdDate: DateTime(2025, 1, 1),
        ),
      );
    }

    for (var i = 0; i < sales; i++) {
      await repo.saveSale(
        Sale(
          id: 's$i',
          invoiceNumber: 'INV-$i',
          date: DateTime(2025, 1, 1).add(Duration(minutes: i)),
          customerId: 'c${i % customers}',
          customerName: 'Customer ${i % customers}',
          subtotal: 250,
          discountPercent: 0,
          discountAmount: 0,
          taxAmount: 0,
          grandTotal: 250,
          paymentMethod: 'Cash',
          items: [
            SaleItem(
              productId: 'p${i % products}',
              productName: 'Product ${i % products}',
              productCode: 'PC-${i % products}',
              variantBarcode: 'BC-${i % products}',
              variantSize: 'M',
              price: 250,
              quantity: 1,
              total: 250,
            ),
          ],
        ),
      );
    }
  }

  int msOf(void Function() body) {
    final watch = Stopwatch()..start();
    body();
    watch.stop();
    return watch.elapsedMilliseconds;
  }

  test('reads stay responsive on a realistically large store', () async {
    await seed(products: 500, customers: 400, sales: 4000);
    final repo = store.repository;

    final allSales = msOf(() => repo.getAllSales());
    final allProducts = msOf(() => repo.getAllProducts());
    final search = msOf(() => repo.searchProducts('Product 4'));
    final lookup = msOf(() => repo.getCustomerByMobile('9000000123'));
    final stats = msOf(() => repo.getCustomerStats('c123'));
    final today = msOf(() => repo.getTodayRevenue());
    final valuation = msOf(() => repo.calculateInventoryValue());
    final audit = msOf(() => repo.auditDerivedState());

    // ignore: avoid_print
    print(
      'SCALE 500 products / 400 customers / 4000 sales — '
      'getAllSales=${allSales}ms getAllProducts=${allProducts}ms '
      'searchProducts=${search}ms getCustomerByMobile=${lookup}ms '
      'getCustomerStats=${stats}ms getTodayRevenue=${today}ms '
      'inventoryValue=${valuation}ms auditDerivedState=${audit}ms',
    );

    // Index-backed reads must be effectively free — they are what the till
    // does between keystrokes.
    expect(lookup, lessThan(50), reason: 'phone lookup is O(1) by design');
    expect(stats, lessThan(50), reason: 'visit stats are index-backed');

    // Full scans are allowed to cost something, but not to be pathological.
    expect(allSales, lessThan(2000));
    expect(allProducts, lessThan(2000));
    expect(search, lessThan(2000));
    expect(valuation, lessThan(2000));
  });

  test('a repeated read of the cached totals does not rescan', () async {
    await seed(products: 50, customers: 50, sales: 2000);
    final repo = store.repository;

    final first = msOf(() => repo.getTodayRevenue());
    final second = msOf(() {
      for (var i = 0; i < 200; i++) {
        repo.getTodayRevenue();
      }
    });

    // ignore: avoid_print
    print('CACHE first=${first}ms then 200 more=${second}ms');

    expect(
      second,
      lessThan(200),
      reason:
          '200 cached reads must not cost 200 scans — if this fails the '
          'derived-totals cache has been lost',
    );
  });

  test(
    'a bulk pull of many records completes in reasonable time',
    () async {
      final repo = store.repository;

      final watch = Stopwatch()..start();
      for (var i = 0; i < 1000; i++) {
        await repo.applyRemote('Customer', 'rc$i', {
          'id': 'rc$i',
          'code': 'C-$i',
          'name': 'Remote $i',
          'mobile': (9500000000 + i).toString(),
          'createdDate': DateTime(2025).toIso8601String(),
          'updatedAt': DateTime.now().toIso8601String(),
        });
      }
      await repo.reconcileAfterPull();
      watch.stop();

      // ignore: avoid_print
      print('PULL 1000 customers applied + reconciled = ${watch.elapsed}');

      expect(repo.getAllCustomers(), hasLength(1000));
      expect(
        repo.getCustomerByMobile('9500000500'),
        isNotNull,
        reason: 'the whole point of B-1: they must be findable afterwards',
      );
      expect(repo.auditDerivedState(), isEmpty);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
