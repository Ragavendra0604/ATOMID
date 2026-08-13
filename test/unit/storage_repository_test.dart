import 'package:flutter_test/flutter_test.dart';

import 'package:atomid/core/utils/app_error.dart';
import 'package:atomid/data/repositories/storage_repository.dart';

import '../support/test_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestStore store;
  late StorageRepository repo;

  setUp(() async {
    store = await TestStore.open();
    repo = store.repository;
  });
  tearDown(() => store.close());

  group('customer ledger', () {
    test('entries written in the same millisecond both survive', () async {
      final customer = await store.addCustomer();

      // Regression: ledger ids were `millisecondsSinceEpoch`, so a sale's
      // debit and its matching payment credit could overwrite one another and
      // leave the balance permanently wrong.
      await repo.addLedgerEntry(
        customerId: customer.id,
        date: DateTime.now(),
        transactionType: 'Sale',
        referenceId: 'INV-1',
        debit: 500,
      );
      await repo.addLedgerEntry(
        customerId: customer.id,
        date: DateTime.now(),
        transactionType: 'Payment',
        referenceId: 'INV-1',
        credit: 500,
      );

      expect(repo.getLedgerForCustomer(customer.id), hasLength(2));
      expect(repo.getCustomerById(customer.id)!.currentBalance, 0);
    });

    test('the running balance carries forward across many entries', () async {
      final customer = await store.addCustomer();

      for (var i = 0; i < 20; i++) {
        await repo.addLedgerEntry(
          customerId: customer.id,
          date: DateTime.now(),
          transactionType: 'Sale',
          referenceId: 'INV-$i',
          debit: 10,
        );
      }

      final ledger = repo.getLedgerForCustomer(customer.id);
      expect(ledger.last.balance, 200);
      expect(repo.getCustomerById(customer.id)!.currentBalance, 200);
    });

    test('a full recalculation agrees with the incremental balance', () async {
      final customer = await store.addCustomer();

      await repo.addLedgerEntry(
        customerId: customer.id,
        date: DateTime.now(),
        transactionType: 'Sale',
        referenceId: 'A',
        debit: 199.99,
      );
      await repo.addLedgerEntry(
        customerId: customer.id,
        date: DateTime.now(),
        transactionType: 'Payment',
        referenceId: 'A',
        credit: 99.99,
      );

      final incremental = repo.getCustomerById(customer.id)!.currentBalance;
      await repo.recalculateCustomerLedger(customer.id);

      expect(repo.getCustomerById(customer.id)!.currentBalance, incremental);
      expect(incremental, 100);
    });
  });

  group('supplier ledger', () {
    test('a purchase raises what we owe and a payment lowers it', () async {
      final supplier = await store.addSupplier();

      await repo.addSupplierLedgerEntry(
        supplierId: supplier.id,
        date: DateTime.now(),
        transactionType: 'Purchase',
        referenceId: 'PO-1',
        credit: 1000,
      );
      await repo.addSupplierLedgerEntry(
        supplierId: supplier.id,
        date: DateTime.now(),
        transactionType: 'Payment',
        referenceId: 'PO-1',
        debit: 400,
      );

      expect(repo.getSupplierById(supplier.id)!.currentBalance, 600);
    });
  });

  group('stock movement', () {
    test('stock out below zero is refused with a readable message', () async {
      final product = await store.addProduct(quantity: 3);

      await expectLater(
        repo.performStockOut(
          productId: product.id,
          variantBarcode: 'BC-1',
          quantity: 5,
          reason: 'Sale',
        ),
        throwsA(
          isA<AppException>().having(
            (e) => e.message,
            'message',
            contains('Not enough stock'),
          ),
        ),
      );
    });

    test('rapid movements each get their own record', () async {
      final product = await store.addProduct(quantity: 50);

      for (var i = 0; i < 10; i++) {
        await repo.performStockOut(
          productId: product.id,
          variantBarcode: 'BC-1',
          quantity: 1,
          reason: 'Sale',
        );
      }

      expect(repo.getMovementsForProduct(product.id), hasLength(10));
      expect(repo.getProductById(product.id)!.variants.first.quantity, 40);
    });
  });

  group('document numbering', () {
    test('invoice numbers include the device tag and increment', () {
      final first = repo.getNextInvoiceNumber();
      expect(first, matches(RegExp(r'^INV-\d{8}-ABCD-0001$')));
    });

    test('purchase numbers follow the same shape', () {
      expect(
        repo.getNextPurchaseNumber(),
        matches(RegExp(r'^PUR-\d{8}-ABCD-0001$')),
      );
    });
  });

  group('sync queue', () {
    test(
      'repeated edits to one record collapse into a single upload',
      () async {
        final product = await store.addProduct();

        await repo.saveProduct(product);
        await repo.saveProduct(product);
        await repo.saveProduct(product);

        final queued = repo.getPendingSyncItems().where(
          (i) => i.entityType == 'Product' && i.entityId == product.id,
        );
        expect(queued, hasLength(1));
      },
    );

    test('items stranded mid-upload are recovered on the next start', () async {
      final product = await store.addProduct();
      final item = repo.getPendingSyncItems().firstWhere(
        (i) => i.entityId == product.id,
      );

      await repo.updateSyncItemStatus(item.id, SyncState.syncing);
      expect(
        repo.getPendingSyncItems().where((i) => i.id == item.id),
        isEmpty,
        reason: 'SYNCING is not a queryable state',
      );

      await repo.resetStuckSyncItems();
      expect(
        repo.getPendingSyncItems().where((i) => i.id == item.id),
        hasLength(1),
      );
    });

    test(
      'exhausted retries move to a terminal state, not an endless loop',
      () async {
        final product = await store.addProduct();
        final item = repo.getPendingSyncItems().firstWhere(
          (i) => i.entityId == product.id,
        );

        await repo.updateSyncItemStatus(
          item.id,
          SyncState.failed,
          retryCount: SyncState.maxRetries,
        );

        expect(repo.getDeadSyncItems(), hasLength(1));
        expect(repo.getPendingSyncItems(), isEmpty);

        await repo.retryDeadSyncItems();
        expect(repo.getDeadSyncItems(), isEmpty);
        expect(repo.getPendingSyncItems(), hasLength(1));
      },
    );

    test(
      'deleting a supplier propagates instead of vanishing locally',
      () async {
        final supplier = await store.addSupplier();
        await repo.deleteSupplier(supplier.id);

        expect(repo.getSupplierById(supplier.id)!.isDeleted, isTrue);
        expect(
          repo.getPendingSyncItems().where((i) => i.entityType == 'Supplier'),
          isNotEmpty,
        );
      },
    );
  });

  group('stock reporting', () {
    test('low stock and out of stock are reported separately', () async {
      await store.addProduct(
        name: 'Low',
        code: 'L-1',
        barcode: 'BC-LOW',
        quantity: 2,
        reorderLevel: 5,
      );
      await store.addProduct(
        name: 'Empty',
        code: 'E-1',
        barcode: 'BC-EMPTY',
        quantity: 0,
      );

      expect(repo.getLowStockItems(), hasLength(1));
      expect(repo.getOutOfStockItems(), hasLength(1));
    });
  });

  test('settings survive a save that only changes one field', () async {
    final original = repo.getSettings();
    expect(original.taxMode, 'inclusive');

    await repo.saveSettings(repo.getSettings()..taxRate = 12);
    expect(repo.getSettings().taxRate, 12);
    expect(repo.getSettings().taxMode, 'inclusive');
  });
}
