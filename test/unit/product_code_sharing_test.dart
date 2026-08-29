import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:atomid/data/models/product_model.dart';
import 'package:atomid/data/repositories/storage_repository.dart';
import 'package:atomid/domain/cart_item.dart';
import 'package:atomid/domain/services/sale_service.dart';
import 'package:atomid/domain/services/session_service.dart';

import '../support/test_store.dart';

class _MockSessionService extends Mock implements SessionService {}

/// One product record is one colourway; its sizes are the variants. A style
/// stocked in three colours is therefore three records sharing one product
/// code, and the app has to treat that as normal rather than as a duplicate.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestStore store;
  late StorageRepository repo;

  setUp(() async {
    // With a shop configured, the same store also serves the checkout
    // tests below — GST refuses to price a bill for a shop with no state.
    store = await TestStore.open(configureShop: true);
    repo = store.repository;
  });
  tearDown(() => store.close());

  group('displayName', () {
    Product product(String name, String colour) => Product(
      id: 'p',
      productName: name,
      productCode: 'SH-100',
      category: 'General',
      brand: 'Brand',
      color: colour,
      createdDate: DateTime(2026),
      updatedDate: DateTime(2026),
      variants: const [],
    );

    test('carries the colour so two colourways read differently', () {
      expect(
        product('Cotton Shirt', 'Blue').displayName,
        'Cotton Shirt - Blue',
      );
      expect(
        product('Cotton Shirt', 'Navy').displayName,
        isNot(product('Cotton Shirt', 'Blue').displayName),
      );
    });

    test('falls back to the plain name when no colour is recorded', () {
      expect(product('Saree', '').displayName, 'Saree');
      expect(product('Saree', '   ').displayName, 'Saree');
    });
  });

  group('sharing a product code', () {
    test('finds the other colourways on the same code', () async {
      final blue = await store.addProduct(
        name: 'Cotton Shirt',
        code: 'SH-100',
        barcode: 'BC-BLUE',
        color: 'Blue',
      );
      await store.addProduct(
        name: 'Cotton Shirt',
        code: 'SH-100',
        barcode: 'BC-NAVY',
        color: 'Navy',
      );
      await store.addProduct(
        name: 'Mens Jeans',
        code: 'JN-200',
        barcode: 'BC-JEAN',
        color: 'Blue',
      );

      // Saving the blue one again must not count itself as a twin.
      expect(repo.productsWithCode('SH-100', excludeId: blue.id), hasLength(1));
      expect(repo.productsWithCode('SH-100'), hasLength(2));
      expect(repo.productsWithCode('JN-200'), hasLength(1));
      expect(repo.productsWithCode('NOPE'), isEmpty);
      expect(repo.productsWithCode(''), isEmpty);
    });

    test('matches the code regardless of case or padding', () async {
      await store.addProduct(code: 'SH-100', barcode: 'BC-A', color: 'Blue');

      expect(repo.productsWithCode(' sh-100 '), hasLength(1));
    });

    test('same code and same colour is the one real duplicate', () async {
      await store.addProduct(
        name: 'Cotton Shirt',
        code: 'SH-100',
        barcode: 'BC-BLUE',
        color: 'Blue',
      );

      expect(repo.productWithCodeAndColour('SH-100', 'Blue'), isNotNull);
      expect(repo.productWithCodeAndColour('SH-100', 'blue'), isNotNull);
      expect(repo.productWithCodeAndColour('SH-100', 'Navy'), isNull);
      expect(repo.productWithCodeAndColour('JN-200', 'Blue'), isNull);
    });

    test('an edit does not flag the record being edited', () async {
      final blue = await store.addProduct(
        code: 'SH-100',
        barcode: 'BC-BLUE',
        color: 'Blue',
      );

      expect(
        repo.productWithCodeAndColour('SH-100', 'Blue', excludeId: blue.id),
        isNull,
      );
    });

    test('colour is searchable, so a colourway can be found by name', () async {
      await store.addProduct(
        name: 'Cotton Shirt',
        code: 'SH-100',
        barcode: 'BC-NAVY',
        color: 'Navy',
      );

      expect(repo.searchProducts('navy'), hasLength(1));
    });
  });

  group('what the customer reads on the bill', () {
    test('the basket line names the colour and the size', () async {
      final product = await store.addProduct(
        name: 'Cotton Shirt',
        code: 'SH-100',
        barcode: 'BC-NAVY',
        color: 'Navy',
      );

      final line = CartItem(
        product: product,
        variant: product.variants.first,
        quantity: 1,
      );

      expect(line.displayName, 'Cotton Shirt - Navy (M)');
    });

    test('checkout freezes the colour onto the sale line', () async {
      final session = _MockSessionService();
      when(() => session.deviceId).thenReturn('dev_test_abcd');
      final service = SaleService(repo, session);
      final customer = await store.addCustomer();

      final product = await store.addProduct(
        name: 'Cotton Shirt',
        code: 'SH-100',
        barcode: 'BC-NAVY',
        color: 'Navy',
        price: 800,
        quantity: 5,
      );

      final sale = await service.checkout(
        CheckoutRequest(
          items: [
            CartItem(
              product: product,
              variant: product.variants.first,
              quantity: 1,
            ),
          ],
          customer: customer,
          paymentMethod: 'Cash',
        ),
      );

      // Three colourways share code SH-100. A line reading only
      // 'Cotton Shirt' would not tell the customer which one they bought.
      expect(sale.items.first.productName, 'Cotton Shirt - Navy');
      expect(sale.items.first.variantSize, 'M');
      expect(sale.items.first.productCode, 'SH-100');
    });

    test('a product with no colour recorded prints its plain name', () async {
      final session = _MockSessionService();
      when(() => session.deviceId).thenReturn('dev_test_abcd');
      final service = SaleService(repo, session);
      final customer = await store.addCustomer();

      final product = await store.addProduct(
        name: 'Saree',
        code: 'SR-1',
        barcode: 'BC-SR',
        color: '',
        price: 999,
        quantity: 2,
      );

      final sale = await service.checkout(
        CheckoutRequest(
          items: [
            CartItem(
              product: product,
              variant: product.variants.first,
              quantity: 1,
            ),
          ],
          customer: customer,
          paymentMethod: 'Cash',
        ),
      );

      expect(sale.items.first.productName, 'Saree');
    });
  });
}
