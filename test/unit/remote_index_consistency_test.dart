import 'package:flutter_test/flutter_test.dart';

import '../support/test_store.dart';

/// Regression cover for B-1: records arriving from the cloud used to land in
/// their box without touching the in-memory indexes the till reads from.
///
/// The visible failure was specific and bad — provision a second device, sign
/// in, wait for the pull, and the customer list looks complete while typing a
/// regular customer's phone number finds nobody. The cashier then creates a
/// duplicate, with a fresh ledger and no loyalty, for someone who has shopped
/// there for years. It healed on the next restart, because `init()` rebuilds
/// the indexes, which is why it survived so long.
///
/// Every test here asserts through the *index-backed* readers
/// (`getCustomerByMobile`, `getCustomerStats`, `getSalesForCustomer`,
/// `getProductByBarcode`) rather than the box readers, because the boxes were
/// never the broken part.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestStore store;

  setUp(() async => store = await TestStore.open());
  tearDown(() => store.close());

  Map<String, dynamic> customerJson({
    required String id,
    required String mobile,
    String name = 'Asha',
    bool isDeleted = false,
    double currentBalance = 0,
    DateTime? updatedAt,
  }) => {
    'id': id,
    'code': 'C-1',
    'name': name,
    'mobile': mobile,
    'createdDate': DateTime(2026, 1, 1).toIso8601String(),
    'updatedAt': (updatedAt ?? DateTime.now()).toIso8601String(),
    'currentBalance': currentBalance,
    'isDeleted': isDeleted,
  };

  Map<String, dynamic> productJson({
    required String id,
    required List<String> barcodes,
    DateTime? updatedDate,
  }) => {
    'id': id,
    'productName': 'Shirt',
    'productCode': 'TS-1',
    'category': 'General',
    'createdDate': DateTime(2026, 1, 1).toIso8601String(),
    'updatedDate': (updatedDate ?? DateTime.now()).toIso8601String(),
    'variants': [
      for (final barcode in barcodes)
        {'size': 'M', 'price': 100, 'quantity': 5, 'barcode': barcode},
    ],
  };

  Map<String, dynamic> saleJson({
    required String id,
    required String customerId,
    double total = 500,
    bool isDeleted = false,
    DateTime? updatedAt,
  }) => {
    'id': id,
    'invoiceNumber': 'INV-$id',
    'date': DateTime.now().toIso8601String(),
    'customerId': customerId,
    'customerName': customerId.isEmpty ? 'Walk-In Customer' : 'Asha',
    'subtotal': total,
    'grandTotal': total,
    'paymentMethod': 'Cash',
    'updatedAt': (updatedAt ?? DateTime.now()).toIso8601String(),
    'isDeleted': isDeleted,
    'items': const [],
  };

  group('a pulled customer is immediately findable', () {
    test('by phone number, without waiting for a restart', () async {
      final repo = store.repository;

      await repo.applyRemote(
        'Customer',
        'c1',
        customerJson(id: 'c1', mobile: '9876543210'),
      );
      await repo.reconcileAfterPull();

      expect(repo.getAllCustomers(), hasLength(1));
      expect(
        repo.getCustomerByMobile('9876543210')?.id,
        'c1',
        reason:
            'this is the till\'s primary lookup — it must not return null '
            'for a customer that is demonstrably in the box',
      );
    });

    test('however the number is typed', () async {
      final repo = store.repository;
      await repo.applyRemote(
        'Customer',
        'c1',
        customerJson(id: 'c1', mobile: '9876543210'),
      );

      for (final typed in [
        '9876543210',
        '98765 43210',
        '+91 98765 43210',
        '09876543210',
      ]) {
        expect(
          repo.getCustomerByMobile(typed)?.id,
          'c1',
          reason: '"$typed" should resolve the same way a local write does',
        );
      }
    });

    test('without a phone number, it simply is not indexed', () async {
      final repo = store.repository;
      await repo.applyRemote(
        'Customer',
        'c1',
        customerJson(id: 'c1', mobile: ''),
      );

      expect(repo.getAllCustomers(), hasLength(1));
      expect(repo.getCustomerByMobile(''), isNull);
    });
  });

  group('a remotely changed phone number does not leave a stale mapping', () {
    test('the old number stops matching and the new one starts', () async {
      final repo = store.repository;

      await repo.applyRemote(
        'Customer',
        'c1',
        customerJson(id: 'c1', mobile: '9876543210'),
      );
      expect(repo.getCustomerByMobile('9876543210')?.id, 'c1');

      await repo.applyRemote(
        'Customer',
        'c1',
        customerJson(
          id: 'c1',
          mobile: '9111111111',
          updatedAt: DateTime.now().add(const Duration(minutes: 1)),
        ),
      );

      expect(repo.getCustomerByMobile('9876543210'), isNull);
      expect(repo.getCustomerByMobile('9111111111')?.id, 'c1');
    });

    test('a remotely deleted customer stops answering lookups', () async {
      final repo = store.repository;

      await repo.applyRemote(
        'Customer',
        'c1',
        customerJson(id: 'c1', mobile: '9876543210'),
      );
      await repo.applyRemote(
        'Customer',
        'c1',
        customerJson(
          id: 'c1',
          mobile: '9876543210',
          isDeleted: true,
          updatedAt: DateTime.now().add(const Duration(minutes: 1)),
        ),
      );

      expect(repo.getCustomerByMobile('9876543210'), isNull);
      expect(repo.getAllCustomers(), isEmpty);
    });
  });

  group('pulled sales attach to their customer', () {
    test('visit stats and history reflect them straight away', () async {
      final repo = store.repository;

      await repo.applyRemote(
        'Customer',
        'c1',
        customerJson(id: 'c1', mobile: '9876543210'),
      );
      await repo.applyRemote(
        'Sale',
        's1',
        saleJson(id: 's1', customerId: 'c1'),
      );
      await repo.applyRemote(
        'Sale',
        's2',
        saleJson(id: 's2', customerId: 'c1', total: 300),
      );
      await repo.reconcileAfterPull();

      final stats = repo.getCustomerStats('c1');
      expect(stats.visits, 2, reason: 'purchase history must survive a pull');
      expect(stats.totalSpend, 800);
      expect(repo.getSalesForCustomer('c1'), hasLength(2));
    });

    test('a walk-in sale is not counted against anybody', () async {
      final repo = store.repository;
      await repo.applyRemote(
        'Customer',
        'c1',
        customerJson(id: 'c1', mobile: '9876543210'),
      );
      await repo.applyRemote('Sale', 's1', saleJson(id: 's1', customerId: ''));

      expect(repo.getCustomerStats('c1').visits, 0);
    });

    test('a sale reassigned remotely leaves the previous customer', () async {
      final repo = store.repository;

      await repo.applyRemote(
        'Customer',
        'c1',
        customerJson(id: 'c1', mobile: '9000000001'),
      );
      await repo.applyRemote(
        'Customer',
        'c2',
        customerJson(id: 'c2', mobile: '9000000002'),
      );
      await repo.applyRemote(
        'Sale',
        's1',
        saleJson(id: 's1', customerId: 'c1'),
      );
      expect(repo.getCustomerStats('c1').visits, 1);

      await repo.applyRemote(
        'Sale',
        's1',
        saleJson(
          id: 's1',
          customerId: 'c2',
          updatedAt: DateTime.now().add(const Duration(minutes: 1)),
        ),
      );

      expect(
        repo.getCustomerStats('c1').visits,
        0,
        reason: 'the sale moved away; it must not still count here',
      );
      expect(repo.getCustomerStats('c2').visits, 1);
    });

    test('a sale voided remotely stops counting as a visit', () async {
      final repo = store.repository;

      await repo.applyRemote(
        'Customer',
        'c1',
        customerJson(id: 'c1', mobile: '9000000001'),
      );
      await repo.applyRemote(
        'Sale',
        's1',
        saleJson(id: 's1', customerId: 'c1'),
      );
      await repo.applyRemote(
        'Sale',
        's1',
        saleJson(
          id: 's1',
          customerId: 'c1',
          isDeleted: true,
          updatedAt: DateTime.now().add(const Duration(minutes: 1)),
        ),
      );

      expect(repo.getCustomerStats('c1').visits, 0);
      expect(repo.getSalesForCustomer('c1'), isEmpty);
    });

    test('re-applying the same sale does not double-count it', () async {
      final repo = store.repository;
      await repo.applyRemote(
        'Customer',
        'c1',
        customerJson(id: 'c1', mobile: '9000000001'),
      );

      final json = saleJson(id: 's1', customerId: 'c1');
      await repo.applyRemote('Sale', 's1', json);
      await repo.applyRemote('Sale', 's1', json);
      await repo.applyRemote('Sale', 's1', json);
      await repo.reconcileAfterPull();

      expect(
        repo.getCustomerStats('c1').visits,
        1,
        reason: 'applyRemote must be idempotent — a retried pull is normal',
      );
      expect(repo.getSalesForCustomer('c1'), hasLength(1));
    });
  });

  group('pulled products answer barcode scans', () {
    test('a pulled product is scannable', () async {
      final repo = store.repository;
      await repo.applyRemote(
        'Product',
        'p1',
        productJson(id: 'p1', barcodes: ['BC-1', 'BC-2']),
      );

      expect(repo.getProductByBarcode('BC-1')?.id, 'p1');
      expect(repo.getProductByBarcode('BC-2')?.id, 'p1');
    });

    test(
      'a variant removed remotely stops answering its old barcode',
      () async {
        final repo = store.repository;
        await repo.applyRemote(
          'Product',
          'p1',
          productJson(id: 'p1', barcodes: ['BC-1', 'BC-2']),
        );
        await repo.applyRemote(
          'Product',
          'p1',
          productJson(
            id: 'p1',
            barcodes: ['BC-1'],
            updatedDate: DateTime.now().add(const Duration(minutes: 1)),
          ),
        );

        expect(repo.getProductByBarcode('BC-1')?.id, 'p1');
        expect(
          repo.getProductByBarcode('BC-2'),
          isNull,
          reason: 'a removed variant must not keep answering scans',
        );
      },
    );
  });

  group('local pending work still wins over a pull', () {
    test('an unsent local customer edit is not overwritten', () async {
      final repo = store.repository;

      final local = await store.addCustomer(
        name: 'Local',
        mobile: '9876543210',
      );
      // The local save queued an unsent change; the cloud must not win.
      final applied = await repo.applyRemote(
        'Customer',
        local.id,
        customerJson(
          id: local.id,
          mobile: '9111111111',
          name: 'Remote',
          updatedAt: DateTime.now().add(const Duration(days: 1)),
        ),
      );

      expect(applied, isFalse);
      expect(repo.getCustomerById(local.id)!.name, 'Local');
      expect(
        repo.getCustomerByMobile('9876543210')?.id,
        local.id,
        reason: 'the index must still reflect the local record that won',
      );
    });
  });

  group('a restart agrees with what the indexes already said', () {
    test('index-backed reads match a full rebuild', () async {
      final repo = store.repository;

      await repo.applyRemote(
        'Customer',
        'c1',
        customerJson(id: 'c1', mobile: '9876543210'),
      );
      await repo.applyRemote(
        'Sale',
        's1',
        saleJson(id: 's1', customerId: 'c1'),
      );
      await repo.applyRemote(
        'Product',
        'p1',
        productJson(id: 'p1', barcodes: ['BC-9']),
      );

      final beforeLookup = repo.getCustomerByMobile('9876543210')?.id;
      final beforeVisits = repo.getCustomerStats('c1').visits;
      final beforeScan = repo.getProductByBarcode('BC-9')?.id;

      // Rebuilding from the boxes is what a restart does. The incremental
      // maintenance above must already agree with it.
      await repo.reconcileAfterPull();

      expect(repo.getCustomerByMobile('9876543210')?.id, beforeLookup);
      expect(repo.getCustomerStats('c1').visits, beforeVisits);
      expect(repo.getProductByBarcode('BC-9')?.id, beforeScan);
      expect(beforeLookup, 'c1');
      expect(beforeVisits, 1);
      expect(beforeScan, 'p1');
    });
  });
}
