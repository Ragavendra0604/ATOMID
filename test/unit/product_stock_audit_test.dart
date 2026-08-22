import 'package:flutter_test/flutter_test.dart';

import 'package:atomid/data/models/product_model.dart';

import '../support/test_store.dart';

/// A stock change made from the product edit form must leave the same trail
/// as one made anywhere else.
///
/// The form rebuilds every variant from its text fields, so saving it used to
/// write `quantity` straight onto the record — no movement, no reason, no
/// record of who did it. Nothing detected it either: there is no baseline for
/// stock to disagree with, so the only evidence would have been a shopkeeper
/// noticing the number was wrong.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestStore store;

  setUp(() async => store = await TestStore.open());
  tearDown(() => store.close());

  /// Rebuilds the product the way the edit form does: a fresh object whose
  /// variants carry the typed figures.
  Product edited(Product original, {required int quantity}) => Product(
    id: original.id,
    productName: original.productName,
    productCode: original.productCode,
    category: original.category,
    brand: original.brand,
    color: original.color,
    createdDate: original.createdDate,
    updatedDate: DateTime.now(),
    variants: [
      for (final v in original.variants)
        ProductVariant(
          size: v.size,
          price: v.price,
          quantity: quantity,
          barcode: v.barcode,
          sku: v.sku,
          lastStockUpdated: DateTime.now(),
          // What a tampered or stale form would send. These are cumulative
          // counters and must not be settable.
          stockIn: 9999,
          stockOut: 9999,
          reorderLevel: v.reorderLevel,
        ),
    ],
  );

  test('raising the quantity records a stock-in movement', () async {
    final product = await store.addProduct(barcode: 'BC-1', quantity: 5);
    final barcode = product.variants.first.barcode;

    await store.repository.saveProductWithStockAudit(
      edited(product, quantity: 12),
    );

    final saved = store.repository.getProductById(product.id)!;
    expect(saved.variants.first.quantity, 12);

    final movements = store.repository.getAllMovements()
        .where((m) => m.variantBarcode == barcode)
        .toList();
    expect(movements, hasLength(1));
    expect(movements.single.type, 'Stock In');
    expect(movements.single.quantity, 7, reason: 'the delta, not the total');
  });

  test('lowering the quantity records a stock-out movement', () async {
    final product = await store.addProduct(barcode: 'BC-2', quantity: 10);

    await store.repository.saveProductWithStockAudit(
      edited(product, quantity: 4),
    );

    final saved = store.repository.getProductById(product.id)!;
    expect(saved.variants.first.quantity, 4);

    final movements = store.repository.getAllMovements()
        .where((m) => m.variantBarcode == product.variants.first.barcode)
        .toList();
    expect(movements, hasLength(1));
    expect(movements.single.type, 'Stock Out');
    expect(movements.single.quantity, 6);
  });

  test('an edit that does not touch stock records nothing', () async {
    final product = await store.addProduct(barcode: 'BC-3', quantity: 8);

    final rename = edited(product, quantity: 8);
    rename.productName = 'Renamed';
    await store.repository.saveProductWithStockAudit(rename);

    expect(store.repository.getProductById(product.id)!.productName, 'Renamed');
    expect(store.repository.getAllMovements(), isEmpty);
  });

  test('the form cannot set the cumulative counters', () async {
    final product = await store.addProduct(barcode: 'BC-4', quantity: 5);

    await store.repository.saveProductWithStockAudit(
      edited(product, quantity: 5),
    );

    final saved = store.repository.getProductById(product.id)!.variants.first;
    expect(saved.stockIn, isNot(9999));
    expect(saved.stockOut, isNot(9999));
  });
}
