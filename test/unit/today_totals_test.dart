import 'package:flutter_test/flutter_test.dart';

import 'package:atomid/data/models/sale_model.dart';

import '../support/test_store.dart';

/// Today's figures are derived once and held until a sale changes.
///
/// The dashboard asks for the invoice list, the takings and the unit count
/// separately, and each used to scan and sort every sale ever recorded. The
/// risk in fixing that is the usual one: a cache that outlives its data. These
/// assert it does not.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestStore store;

  setUp(() async => store = await TestStore.open());
  tearDown(() => store.close());

  Future<Sale> sell({
    required String id,
    required double total,
    required int quantity,
    DateTime? at,
  }) async {
    final sale = Sale(
      id: id,
      invoiceNumber: id.toUpperCase(),
      date: at ?? DateTime.now(),
      customerId: '',
      customerName: 'Walk-In Customer',
      subtotal: total,
      discountPercent: 0,
      discountAmount: 0,
      taxAmount: 0,
      grandTotal: total,
      paymentMethod: 'Cash',
      items: [
        SaleItem(
          productId: 'p1',
          productName: 'Item',
          productCode: 'C1',
          variantBarcode: 'B1',
          variantSize: 'M',
          price: total / quantity,
          quantity: quantity,
          total: total,
        ),
      ],
    );
    await store.repository.saveSale(sale);
    return sale;
  }

  test('the three figures agree with each other', () async {
    await sell(id: 'a', total: 300, quantity: 2);
    await sell(id: 'b', total: 200, quantity: 3);

    final repo = store.repository;
    expect(repo.getTodaySales(), hasLength(2));
    expect(repo.getTodayRevenue(), 500);
    expect(repo.getTodayItemsSold(), 5);
  });

  test('a new sale is reflected immediately, not on the next launch', () async {
    final repo = store.repository;

    await sell(id: 'a', total: 300, quantity: 2);
    expect(repo.getTodayRevenue(), 300);

    // Reading first is the point: it populates the cache, so a stale one
    // would answer 300 here.
    await sell(id: 'b', total: 150, quantity: 1);

    expect(repo.getTodayRevenue(), 450);
    expect(repo.getTodayItemsSold(), 3);
    expect(repo.getTodaySales(), hasLength(2));
  });

  test('yesterday is not counted as today', () async {
    final repo = store.repository;
    await sell(id: 'a', total: 300, quantity: 2);
    await sell(
      id: 'old',
      total: 999,
      quantity: 9,
      at: DateTime.now().subtract(const Duration(days: 1)),
    );

    expect(repo.getTodayRevenue(), 300);
    expect(repo.getTodayItemsSold(), 2);
    expect(repo.getTodaySales(), hasLength(1));
  });

  test('an empty day reports zero rather than throwing', () {
    final repo = store.repository;
    expect(repo.getTodaySales(), isEmpty);
    expect(repo.getTodayRevenue(), 0);
    expect(repo.getTodayItemsSold(), 0);
  });

  test('sales pulled from the cloud show up in the totals', () async {
    final repo = store.repository;
    await sell(id: 'a', total: 100, quantity: 1);
    expect(repo.getTodayRevenue(), 100);

    // applyRemote writes straight into the box rather than through saveSale,
    // so it is a second path that has to invalidate.
    await repo.applyRemote('Sale', 'remote-1', {
      'id': 'remote-1',
      'invoiceNumber': 'INV-R1',
      'date': DateTime.now().toIso8601String(),
      'customerId': '',
      'customerName': 'Walk-In Customer',
      'subtotal': 250,
      'grandTotal': 250,
      'paymentMethod': 'Cash',
      'updatedAt': DateTime.now().toIso8601String(),
      'items': [
        {
          'productId': 'p1',
          'productName': 'Item',
          'productCode': 'C1',
          'variantBarcode': 'B1',
          'variantSize': 'M',
          'price': 250,
          'quantity': 1,
          'total': 250,
        },
      ],
    });

    expect(repo.getTodayRevenue(), 350);
    expect(repo.getTodaySales(), hasLength(2));
  });
}
