import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:atomid/data/models/product_model.dart';
import 'package:atomid/presentation/providers/cart_notifier.dart';

void main() {
  late ProviderContainer container;
  late Product product;
  late ProductVariant variant;

  Product buildProduct(ProductVariant v) => Product(
    id: 'p1',
    productName: 'Test Product',
    productCode: 'TP-01',
    category: 'Test',
    brand: 'Brand',
    color: 'Red',
    createdDate: DateTime.now(),
    updatedDate: DateTime.now(),
    variants: [v],
  );

  setUp(() {
    container = ProviderContainer();
    variant = ProductVariant(
      barcode: '123456',
      size: 'M',
      price: 100,
      quantity: 5,
    );
    product = buildProduct(variant);
  });

  tearDown(() => container.dispose());

  CartNotifier cart() => container.read(cartProvider.notifier);

  test('adding an item puts one unit in the basket', () {
    expect(cart().addItem(product, variant), isTrue);

    final items = container.read(cartProvider);
    expect(items, hasLength(1));
    expect(items.single.quantity, 1);
    expect(items.single.total, 100);
  });

  test('adding the same variant twice increases the quantity', () {
    cart().addItem(product, variant);
    cart().addItem(product, variant);

    final items = container.read(cartProvider);
    expect(items, hasLength(1));
    expect(items.single.quantity, 2);
    expect(items.single.total, 200);
  });

  test('adding beyond available stock is refused, not silently ignored', () {
    for (var i = 0; i < 5; i++) {
      expect(cart().addItem(product, variant), isTrue);
    }
    expect(cart().addItem(product, variant), isFalse);
    expect(container.read(cartProvider).single.quantity, 5);
  });

  test('an out-of-stock variant cannot be added at all', () {
    final empty = ProductVariant(
      barcode: 'EMPTY',
      size: 'S',
      price: 50,
      quantity: 0,
    );
    expect(cart().addItem(buildProduct(empty), empty), isFalse);
    expect(container.read(cartProvider), isEmpty);
  });

  test('setting quantity to zero removes the line', () {
    cart().addItem(product, variant);
    cart().updateQuantity('123456', 0);
    expect(container.read(cartProvider), isEmpty);
  });

  test('quantity cannot be raised past the shelf', () {
    cart().addItem(product, variant);
    expect(cart().updateQuantity('123456', 6), isFalse);
    expect(container.read(cartProvider).single.quantity, 1);
  });

  test('subtotal and item count reflect the basket', () {
    cart().addItem(product, variant);
    cart().updateQuantity('123456', 3);

    expect(cart().subtotal, 300);
    expect(cart().totalItems, 3);
  });

  test('subtotal is free of floating point noise', () {
    final priced = ProductVariant(
      barcode: 'P99',
      size: 'M',
      price: 1299.90,
      quantity: 10,
    );
    cart().addItem(buildProduct(priced), priced);
    cart().updateQuantity('P99', 3);

    expect(cart().subtotal, 3899.70);
  });

  test('validateStock reports a line that outran its stock', () {
    cart().addItem(product, variant);
    cart().updateQuantity('123456', 5);

    expect(cart().validateStock(), isNull);

    // Stock moves underneath an open basket.
    variant.quantity = 2;
    expect(cart().validateStock(), contains('only 2 available'));
  });

  test('clearing empties the basket', () {
    cart().addItem(product, variant);
    cart().clearCart();
    expect(container.read(cartProvider), isEmpty);
  });
}
