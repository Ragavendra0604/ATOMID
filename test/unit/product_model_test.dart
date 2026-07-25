import 'package:flutter_test/flutter_test.dart';
import 'package:atomid/data/models/product_model.dart';

void main() {
  group('Product and ProductVariant Tests', () {
    test('Product should be created correctly', () {
      final product = Product(
        id: '123',
        productName: 'Test Shirt',
        productCode: 'TS-01',
        category: 'Apparel',
        brand: 'BrandX',
        color: 'Blue',
        createdDate: DateTime(2023, 1, 1),
        updatedDate: DateTime(2023, 1, 2),
        variants: [
          ProductVariant(
            size: 'M',
            price: 19.99,
            quantity: 50,
            barcode: '1234567890',
            stockIn: 10,
            stockOut: 5,
            reorderLevel: 5,
          ),
        ],
      );

      expect(product.id, '123');
      expect(product.productName, 'Test Shirt');
      expect(product.variants.length, 1);
      expect(product.variants.first.size, 'M');
      expect(product.variants.first.price, 19.99);
      expect(product.variants.first.stockIn, 10);
      expect(product.variants.first.stockOut, 5);
      expect(product.variants.first.reorderLevel, 5);
    });
  });
}
