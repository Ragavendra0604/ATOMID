import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:atomid/data/models/product_model.dart';
import 'package:atomid/presentation/providers/cart_notifier.dart';

void main() {
  group('CartNotifier Tests', () {
    late ProviderContainer container;
    late Product dummyProduct;
    late ProductVariant dummyVariant;

    setUp(() {
      container = ProviderContainer();
      dummyProduct = Product(
        id: 'p1',
        productName: 'Test Product',
        productCode: 'TP-01',
        category: 'Test',
        brand: 'Brand',
        color: 'Red',
        createdDate: DateTime.now(),
        updatedDate: DateTime.now(),
        variants: [],
      );
      dummyVariant = ProductVariant(
        barcode: '123456',
        size: 'M',
        price: 100.0,
        quantity: 5,
      );
    });

    tearDown(() {
      container.dispose();
    });

    test('should add item to cart', () {
      final cart = container.read(cartProvider.notifier);
      
      cart.addItem(dummyProduct, dummyVariant);
      
      final state = container.read(cartProvider);
      expect(state.length, 1);
      expect(state.first.quantity, 1);
      expect(cart.subtotal, 100.0);
      expect(cart.totalItems, 1);
    });

    test('should not add item if out of stock', () {
      final outOfStockVariant = ProductVariant(
        barcode: '999',
        size: 'S',
        price: 20,
        quantity: 0,
      );
      
      final cart = container.read(cartProvider.notifier);
      cart.addItem(dummyProduct, outOfStockVariant);
      
      expect(container.read(cartProvider).isEmpty, isTrue);
    });

    test('should increase quantity if adding existing item', () {
      final cart = container.read(cartProvider.notifier);
      cart.addItem(dummyProduct, dummyVariant); // Qty 1
      cart.addItem(dummyProduct, dummyVariant); // Qty 2
      
      final state = container.read(cartProvider);
      expect(state.length, 1);
      expect(state.first.quantity, 2);
    });

    test('should not increase quantity beyond stock limit', () {
      final cart = container.read(cartProvider.notifier);
      
      // Stock is 5
      for (int i = 0; i < 6; i++) {
        cart.addItem(dummyProduct, dummyVariant);
      }
      
      final state = container.read(cartProvider);
      expect(state.first.quantity, 5); // Should max out at 5
    });

    test('should remove item', () {
      final cart = container.read(cartProvider.notifier);
      cart.addItem(dummyProduct, dummyVariant);
      expect(container.read(cartProvider).length, 1);
      
      cart.removeItem(dummyVariant.barcode);
      expect(container.read(cartProvider).isEmpty, isTrue);
    });

    test('should update quantity and cap at stock', () {
      final cart = container.read(cartProvider.notifier);
      cart.addItem(dummyProduct, dummyVariant);
      
      cart.updateQuantity(dummyVariant.barcode, 3);
      expect(container.read(cartProvider).first.quantity, 3);
      
      cart.updateQuantity(dummyVariant.barcode, 10);
      expect(container.read(cartProvider).first.quantity, 3); // Unchanged because 10 > 5 (stock)
      
      cart.updateQuantity(dummyVariant.barcode, 0);
      expect(container.read(cartProvider).isEmpty, isTrue); // Removes if qty <= 0
    });

    test('validateStock should return error message if stock exceeded', () {
      final cart = container.read(cartProvider.notifier);
      cart.addItem(dummyProduct, dummyVariant);
      
      expect(cart.validateStock(), isNull);
      
      // Forcing invalid state manually to test validation function
      container.read(cartProvider).first.quantity = 10;
      
      final error = cart.validateStock();
      expect(error, contains('only 5 available'));
    });
  });
}
