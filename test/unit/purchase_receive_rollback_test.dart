import 'package:flutter_test/flutter_test.dart';

import 'package:atomid/core/utils/app_error.dart';
import 'package:atomid/core/utils/ids.dart';
import 'package:atomid/data/models/product_model.dart';
import 'package:atomid/data/models/purchase_model.dart';
import 'package:atomid/data/models/supplier_model.dart';
import 'package:atomid/data/repositories/storage_repository.dart';
import 'package:atomid/domain/services/purchase_service.dart';

import '../support/test_store.dart';

/// Fails the *second* `performStockIn` call — the shape of failure that used
/// to leave a purchase order stuck: saved as `Received` (settled, so
/// unrecoverable through the UI) with only the first line's stock actually
/// moved and the supplier never credited.
class _SecondStockInFailsRepository extends StorageRepository {
  int _calls = 0;

  @override
  Future<void> performStockIn({
    required String productId,
    required String variantBarcode,
    required int quantity,
    required String reason,
    String movementReferenceId = '',
    String performedAt = '',
  }) async {
    _calls++;
    if (_calls == 2) {
      throw const AppException('Simulated write failure.');
    }
    return super.performStockIn(
      productId: productId,
      variantBarcode: variantBarcode,
      quantity: quantity,
      reason: reason,
      movementReferenceId: movementReferenceId,
      performedAt: performedAt,
    );
  }
}

/// Fails `savePurchase` — the step immediately *after* the supplier is
/// credited, and the only shape of failure that reaches it.
///
/// The stock reversals were always registered for undo; the supplier ledger
/// write was not. A failure here therefore unwound the stock and left the
/// credit standing, so the shop owed money for goods its own order still
/// said had never been received.
class _SavePurchaseFailsRepository extends StorageRepository {
  @override
  Future<void> savePurchase(Purchase purchase) async {
    if (purchase.status == PurchaseStatus.received) {
      throw const AppException('Simulated write failure.');
    }
    return super.savePurchase(purchase);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Purchase buildTwoItemOrder({
    required Supplier supplier,
    required Product productA,
    required Product productB,
    required String purchaseNumber,
    String status = PurchaseStatus.issued,
  }) {
    return Purchase(
      id: Ids.generate(),
      purchaseNumber: purchaseNumber,
      supplierId: supplier.id,
      supplierName: supplier.supplierName,
      purchaseDate: DateTime.now(),
      createdDate: DateTime.now(),
      subtotal: 1200,
      grandTotal: 1200,
      status: status,
      items: [
        PurchaseItem(
          productId: productA.id,
          productName: productA.productName,
          variantBarcode: productA.variants.first.barcode,
          variantSize: productA.variants.first.size,
          quantity: 10,
          costPrice: 60,
          sellingPrice: productA.variants.first.price,
          lineTotal: 600,
        ),
        PurchaseItem(
          productId: productB.id,
          productName: productB.productName,
          variantBarcode: productB.variants.first.barcode,
          variantSize: productB.variants.first.size,
          quantity: 10,
          costPrice: 60,
          sellingPrice: productB.variants.first.price,
          lineTotal: 600,
        ),
      ],
    );
  }

  group('a deleted product blocks receiving before anything is touched', () {
    late TestStore store;
    late PurchaseService service;

    setUp(() async {
      store = await TestStore.open();
      service = PurchaseService(store.repository);
    });

    tearDown(() => store.close());

    test('the order stays editable and no stock moves', () async {
      final supplier = await store.addSupplier();
      final productA = await store.addProduct(
        code: 'A',
        barcode: 'BC-A',
        quantity: 5,
      );
      final productB = await store.addProduct(
        code: 'B',
        barcode: 'BC-B',
        quantity: 5,
      );

      final order = buildTwoItemOrder(
        supplier: supplier,
        productA: productA,
        productB: productB,
        purchaseNumber: store.repository.getNextPurchaseNumber(),
      );
      await service.savePurchase(order, isNew: true);

      // The product a later line depends on is gone by the time someone
      // marks the order received — routine for an order that sat around.
      await store.repository.deleteProduct(productB.id);

      await expectLater(
        service.markAsReceived(order),
        throwsA(isA<AppException>()),
      );

      // Not stuck as "Received": still editable, still Issued.
      expect(order.status, PurchaseStatus.issued);
      expect(PurchaseStatus.isSettled(order.status), isFalse);

      // Nothing was received — not even product A, whose line was valid.
      expect(
        store.repository.getProductById(productA.id)!.variants.first.quantity,
        5,
      );
      expect(store.repository.getLedgerForSupplier(supplier.id), isEmpty);
    });
  });

  group('a write failure partway through receiving unwinds cleanly', () {
    late TestStore store;
    late PurchaseService service;

    setUp(() async {
      store = await TestStore.open(repository: _SecondStockInFailsRepository());
      service = PurchaseService(store.repository);
    });

    tearDown(() => store.close());

    test(
      'the first line\'s stock is reversed and the order is not settled',
      () async {
        final supplier = await store.addSupplier();
        final productA = await store.addProduct(
          code: 'A',
          barcode: 'BC-A',
          quantity: 5,
        );
        final productB = await store.addProduct(
          code: 'B',
          barcode: 'BC-B',
          quantity: 5,
        );

        final order = buildTwoItemOrder(
          supplier: supplier,
          productA: productA,
          productB: productB,
          purchaseNumber: store.repository.getNextPurchaseNumber(),
        );
        await service.savePurchase(order, isNew: true);

        await expectLater(
          service.markAsReceived(order),
          throwsA(isA<AppException>()),
        );

        // The order is left exactly as it was — not "Received" with half its
        // stock moved and the supplier never credited.
        expect(order.status, PurchaseStatus.issued);
        expect(PurchaseStatus.isSettled(order.status), isFalse);
        expect(order.items[0].receivedQuantity, 0);
        expect(order.items[1].receivedQuantity, 0);

        // Product A's stock-in (the one that succeeded) was unwound.
        expect(
          store.repository.getProductById(productA.id)!.variants.first.quantity,
          5,
        );
        expect(
          store.repository.getProductById(productB.id)!.variants.first.quantity,
          5,
        );

        // The supplier was never credited — that step never ran.
        expect(store.repository.getLedgerForSupplier(supplier.id), isEmpty);

        // The order can still be retried once the underlying issue is fixed.
        await expectLater(service.markAsReceived(order), completes);
        expect(order.status, PurchaseStatus.received);
      },
    );
  });

  group('a failure after the supplier is credited unwinds the credit', () {
    late TestStore store;
    late PurchaseService service;

    setUp(() async {
      store = await TestStore.open(repository: _SavePurchaseFailsRepository());
      service = PurchaseService(store.repository);
    });

    tearDown(() => store.close());

    test('the supplier is not left owed for goods never received', () async {
      final supplier = await store.addSupplier();
      final productA = await store.addProduct(
        barcode: 'BC-A',
        quantity: 5,
      );
      final productB = await store.addProduct(
        barcode: 'BC-B',
        quantity: 5,
      );

      final order = buildTwoItemOrder(
        supplier: supplier,
        productA: productA,
        productB: productB,
        purchaseNumber: 'PO-CREDIT-1',
      );

      await expectLater(
        service.markAsReceived(order),
        throwsA(isA<AppException>()),
      );

      // The credit was written, then reversed. Both the row and the balance
      // derived from it have to go — leaving the row with a corrected balance
      // would still show the shop a debt it does not have.
      expect(
        store.repository.getLedgerForSupplier(supplier.id),
        isEmpty,
        reason: 'the reversal must remove the credit, not just correct it',
      );
      expect(
        store.repository.getSupplierById(supplier.id)!.currentBalance,
        0,
        reason: 'nothing is owed for an order that was never received',
      );

      // And the stock reversal still happened, as it always did.
      expect(
        store.repository.getProductById(productA.id)!.variants.first.quantity,
        5,
      );
      expect(
        store.repository.getProductById(productB.id)!.variants.first.quantity,
        5,
      );
    });
  });

}
