import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:atomid/domain/cart_item.dart';
import 'package:atomid/domain/services/sale_service.dart';
import 'package:atomid/domain/services/session_service.dart';

import '../support/test_store.dart';

class MockSessionService extends Mock implements SessionService {}

/// Backup and restore, treated as the disaster-recovery path it is.
///
/// `BackupService` handles the file: staging write, rename, version gate,
/// pruning. Everything underneath it — what actually goes into the file and
/// what comes back out — is `exportSnapshot` / `importSnapshot`, and that is
/// where a defect costs a shop its history rather than one file. These test
/// that layer directly, so they need no `path_provider` plugin.
///
/// The invariant: `restore(backup(state))` must reproduce the state, and the
/// derived indexes must be rebuilt afterwards — a restored database with stale
/// indexes is the B-1 failure all over again, arriving by a different route.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestStore store;
  late SaleService sales;

  setUp(() async {
    store = await TestStore.open();
    final session = MockSessionService();
    when(() => session.deviceId).thenReturn('dev_test_abcd');
    sales = SaleService(store.repository, session);
  });

  tearDown(() => store.close());

  /// Builds a store with something of every kind in it.
  Future<void> seedRealisticShop() async {
    final product = await store.addProduct(
      name: 'Blue Shirt',
      barcode: 'BC-1',
      price: 499.99,
      quantity: 40,
    );
    await store.addProduct(code: 'TS-2', barcode: 'BC-2', quantity: 15);
    final customer = await store.addCustomer(
      name: 'Asha Menon',
      mobile: '9876543210',
      creditLimit: 10000,
    );
    await store.addSupplier();

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
        paymentMethod: 'Credit',
      ),
    );
  }

  group('a snapshot round trip reproduces the shop', () {
    test('every record type survives export and import', () async {
      await seedRealisticShop();
      final repo = store.repository;

      final before = {
        'products': repo.getAllProducts().length,
        'customers': repo.getAllCustomers().length,
        'suppliers': repo.getSuppliers().length,
        'sales': repo.getAllSales().length,
        'movements': repo.getAllMovements().length,
      };
      final beforeBalance = repo
          .getCustomerById(repo.getAllCustomers().first.id)!
          .currentBalance;

      final snapshot = repo.exportSnapshot();

      // Round-trip through JSON, which is what the file actually holds — a
      // value that cannot survive encoding is a corrupt backup, not a
      // working one.
      final decoded = (jsonDecode(jsonEncode(snapshot)) as Map).map(
        (k, v) => MapEntry(
          k as String,
          (v as List).map((e) => (e as Map).cast<String, dynamic>()).toList(),
        ),
      );

      final restored = await repo.importSnapshot(decoded);

      expect(restored, isNotEmpty, reason: 'nothing was restored at all');
      expect(repo.getAllProducts().length, before['products']);
      expect(repo.getAllCustomers().length, before['customers']);
      expect(repo.getSuppliers().length, before['suppliers']);
      expect(repo.getAllSales().length, before['sales']);
      expect(repo.getAllMovements().length, before['movements']);
      expect(
        repo.getCustomerById(repo.getAllCustomers().first.id)!.currentBalance,
        beforeBalance,
        reason: 'a restored ledger balance must match what was backed up',
      );
    });

    test('the restore leaves the derived indexes usable', () async {
      await seedRealisticShop();
      final repo = store.repository;

      final snapshot = repo.exportSnapshot();
      await repo.importSnapshot(snapshot);

      // This is the B-1 failure arriving by another route: records present,
      // indexes stale, phone lookup silently answering nothing.
      expect(
        repo.getCustomerByMobile('9876543210'),
        isNotNull,
        reason: 'phone lookup must work immediately after a restore',
      );
      expect(repo.getProductByBarcode('BC-1'), isNotNull);
      expect(repo.auditDerivedState(), isEmpty);
    });

    test('restoring twice is idempotent, not duplicating', () async {
      await seedRealisticShop();
      final repo = store.repository;

      final snapshot = repo.exportSnapshot();
      await repo.importSnapshot(snapshot);
      final afterFirst = repo.getAllProducts().length;
      await repo.importSnapshot(snapshot);

      expect(
        repo.getAllProducts().length,
        afterFirst,
        reason: 'restore is keyed by id, so a repeat must overwrite not append',
      );
      expect(repo.auditDerivedState(), isEmpty);
    });

    test('restoring does not delete work done since the backup', () async {
      await seedRealisticShop();
      final repo = store.repository;
      final snapshot = repo.exportSnapshot();

      final later = await store.addProduct(code: 'AFTER', barcode: 'BC-LATER');
      await repo.importSnapshot(snapshot);

      expect(
        repo.getProductById(later.id),
        isNotNull,
        reason:
            'restore is additive by id — it must not wipe newer records, '
            'which is the failure people actually fear',
      );
    });
  });

  group('a damaged snapshot is survived, not swallowed', () {
    test('an empty snapshot restores nothing and breaks nothing', () async {
      await seedRealisticShop();
      final repo = store.repository;
      final productsBefore = repo.getAllProducts().length;

      final restored = await repo.importSnapshot({});

      expect(restored, isEmpty);
      expect(repo.getAllProducts().length, productsBefore);
      expect(repo.auditDerivedState(), isEmpty);
    });

    test('records missing their id are skipped, not crashed on', () async {
      final repo = store.repository;

      final restored = await repo.importSnapshot({
        'Product': [
          <String, dynamic>{'productName': 'No Id'},
          {'_localId': '', 'productName': 'Empty Id'},
          {'_localId': 'good-1', 'id': 'good-1', 'productName': 'Fine'},
        ],
      });

      expect(restored['Product'], 1, reason: 'only the usable record counts');
      expect(repo.getProductById('good-1'), isNotNull);
      expect(repo.auditDerivedState(), isEmpty);
    });

    test('hostile field values do not abort the restore', () async {
      final repo = store.repository;

      final restored = await repo.importSnapshot({
        'Product': [
          {
            '_localId': 'p-bad',
            'id': 'p-bad',
            'productName': 42,
            'variants': 'not a list',
            'createdDate': 'not-a-date',
          },
        ],
        'Customer': [
          {
            '_localId': 'c-bad',
            'id': 'c-bad',
            'name': null,
            'mobile': ['array'],
            'currentBalance': double.nan,
          },
        ],
        'Sale': [
          {
            '_localId': 's-bad',
            'id': 's-bad',
            'items': {'not': 'a list'},
            'grandTotal': double.infinity,
          },
        ],
      });

      expect(restored.values.fold<int>(0, (a, b) => a + b), 3);
      expect(repo.auditDerivedState(), isEmpty);

      // The poisoned money value must not have reached storage.
      final sale = repo.getSaleById('s-bad');
      expect(sale, isNotNull);
      expect(
        sale!.grandTotal.isFinite,
        isTrue,
        reason: 'an infinite total would poison every report that sums it',
      );
    });

    test('an unknown entity type is ignored rather than fatal', () async {
      final repo = store.repository;

      final restored = await repo.importSnapshot({
        'SomethingFromTheFuture': [
          {'_localId': 'x', 'id': 'x'},
        ],
        'Product': [
          {'_localId': 'p1', 'id': 'p1', 'productName': 'Real'},
        ],
      });

      expect(restored.containsKey('SomethingFromTheFuture'), isFalse);
      expect(restored['Product'], 1);
    });
  });

  group('a restored store can still sync', () {
    test('restoring queues the records for upload', () async {
      await seedRealisticShop();
      final repo = store.repository;

      for (final item in repo.getPendingSyncItems()) {
        await repo.deleteSyncItem(item.id);
      }
      expect(repo.getPendingSyncItems(), isEmpty);

      await repo.importSnapshot(repo.exportSnapshot());

      expect(
        repo.getPendingSyncItems(),
        isNotEmpty,
        reason:
            'a restored device must push its recovered records to the '
            'cloud, or the restore is invisible to every other device',
      );
    });
  });
}
