import 'package:flutter_test/flutter_test.dart';

import 'package:atomid/core/utils/app_error.dart';
import 'package:atomid/core/utils/ids.dart';
import 'package:atomid/data/models/product_model.dart';
import 'package:atomid/data/models/company_model.dart';
import 'package:atomid/data/models/purchase_model.dart';
import 'package:atomid/domain/gst/gst_treatment.dart';
import 'package:atomid/data/models/supplier_model.dart';
import 'package:atomid/domain/services/purchase_service.dart';

import '../support/test_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestStore store;
  late PurchaseService service;

  setUp(() async {
    store = await TestStore.open();
    service = PurchaseService(store.repository);
    // The engine refuses to guess a shop state, so the business has to be
    // configured before a purchase can be taxed.
    await store.repository.saveCompany(
      CompanyModel(
        name: 'Atomid Store',
        gstNumber: '33AAAAA0000A1Z5',
        state: 'Tamil Nadu',
        stateCode: '33',
      ),
    );
  });

  tearDown(() => store.close());

  Purchase buildOrder({
    required Supplier supplier,
    required Product product,
    required ProductVariant variant,
    int quantity = 10,
    double cost = 60,
    String status = PurchaseStatus.draft,
  }) {
    return Purchase(
      id: Ids.generate(),
      purchaseNumber: store.repository.getNextPurchaseNumber(),
      supplierId: supplier.id,
      supplierName: supplier.supplierName,
      purchaseDate: DateTime.now(),
      createdDate: DateTime.now(),
      subtotal: cost * quantity,
      grandTotal: cost * quantity,
      status: status,
      items: [
        PurchaseItem(
          productId: product.id,
          productName: product.productName,
          variantBarcode: variant.barcode,
          variantSize: variant.size,
          quantity: quantity,
          costPrice: cost,
          sellingPrice: variant.price,
          lineTotal: cost * quantity,
          // Explicitly nil-rated: these cases exercise stock and ledger
          // mechanics, and GST must now be configured rather than defaulted.
          gstTreatment: GstTreatment.nilRated,
        ),
      ],
    );
  }

  test('receiving an order adds stock and credits the supplier', () async {
    final supplier = await store.addSupplier();
    final product = await store.addProduct(quantity: 5);
    final variant = product.variants.first;

    final order = buildOrder(
      supplier: supplier,
      product: product,
      variant: variant,
      quantity: 10,
      status: PurchaseStatus.issued,
    );
    await service.savePurchase(order, isNew: true);

    // Regression: `markAsReceived` mutates the record, and Hive hands back the
    // same instance — so re-reading it to detect the transition saw
    // "Received" already and skipped the stock-in entirely.
    await service.markAsReceived(order);

    expect(
      store.repository.getProductById(product.id)!.variants.first.quantity,
      15,
      reason: 'ten units should have been received into stock',
    );
    expect(store.repository.getSupplierById(supplier.id)!.currentBalance, 600);
    expect(
      store.repository.getPurchaseById(order.id)!.items.first.receivedQuantity,
      10,
    );
  });

  test('an order created as Received stocks in immediately', () async {
    final supplier = await store.addSupplier();
    final product = await store.addProduct(quantity: 0);

    final order = buildOrder(
      supplier: supplier,
      product: product,
      variant: product.variants.first,
      quantity: 4,
      status: PurchaseStatus.received,
    );
    await service.savePurchase(order, isNew: true);

    expect(
      store.repository.getProductById(product.id)!.variants.first.quantity,
      4,
    );
  });

  test('re-saving a received order does not stock it in twice', () async {
    final supplier = await store.addSupplier();
    final product = await store.addProduct(quantity: 0);

    final order = buildOrder(
      supplier: supplier,
      product: product,
      variant: product.variants.first,
      quantity: 6,
      status: PurchaseStatus.issued,
    );
    await service.savePurchase(order, isNew: true);
    await service.markAsReceived(order);

    order.notes = 'Checked by the manager';
    await service.savePurchase(order, previousStatus: PurchaseStatus.received);

    expect(
      store.repository.getProductById(product.id)!.variants.first.quantity,
      6,
      reason: 'an edit after receipt must not add the stock again',
    );
    expect(store.repository.getSupplierById(supplier.id)!.currentBalance, 360);
  });

  test('a received order cannot be received again', () async {
    final supplier = await store.addSupplier();
    final product = await store.addProduct();

    final order = buildOrder(
      supplier: supplier,
      product: product,
      variant: product.variants.first,
      status: PurchaseStatus.received,
    );
    await service.savePurchase(order, isNew: true);

    await expectLater(
      service.markAsReceived(order),
      throwsA(isA<AppException>()),
    );
  });

  test('only a draft can be issued', () async {
    final supplier = await store.addSupplier();
    final product = await store.addProduct();

    final order = buildOrder(
      supplier: supplier,
      product: product,
      variant: product.variants.first,
      status: PurchaseStatus.issued,
    );
    await service.savePurchase(order, isNew: true);

    await expectLater(
      service.markAsIssued(order),
      throwsA(isA<AppException>()),
    );
  });

  test('an order with no items is rejected', () async {
    final supplier = await store.addSupplier();

    final empty = Purchase(
      id: Ids.generate(),
      purchaseNumber: 'PUR-EMPTY',
      supplierId: supplier.id,
      supplierName: supplier.supplierName,
      purchaseDate: DateTime.now(),
      createdDate: DateTime.now(),
      subtotal: 0,
      grandTotal: 0,
      items: const [],
    );

    await expectLater(
      service.savePurchase(empty, isNew: true),
      throwsA(isA<AppException>()),
    );
  });
}
