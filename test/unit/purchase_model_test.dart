import 'package:flutter_test/flutter_test.dart';
import 'package:atomid/data/models/purchase_model.dart';

void main() {
  group('PurchaseItem Model Tests', () {
    test('PurchaseItem should be created correctly', () {
      final item = PurchaseItem(
        productId: 'prod-001',
        productName: 'Test T-Shirt',
        variantBarcode: 'ABC123456789',
        variantSize: 'M',
        sku: 'TST-TS-M',
        quantity: 10,
        costPrice: 150.0,
        sellingPrice: 299.0,
        lineTotal: 1500.0,
      );

      expect(item.productId, 'prod-001');
      expect(item.productName, 'Test T-Shirt');
      expect(item.variantBarcode, 'ABC123456789');
      expect(item.variantSize, 'M');
      expect(item.sku, 'TST-TS-M');
      expect(item.quantity, 10);
      expect(item.costPrice, 150.0);
      expect(item.sellingPrice, 299.0);
      expect(item.lineTotal, 1500.0);
    });

    test('PurchaseItem line total should equal costPrice * quantity', () {
      final qty = 5;
      final cost = 200.0;
      final item = PurchaseItem(
        productId: 'prod-002',
        productName: 'Test Jeans',
        variantBarcode: 'DEF123456789',
        variantSize: 'L',
        quantity: qty,
        costPrice: cost,
        sellingPrice: 500.0,
        lineTotal: cost * qty,
      );

      expect(item.lineTotal, 1000.0);
      expect(item.lineTotal, item.costPrice * item.quantity);
    });
  });

  group('Purchase Model Tests', () {
    test('Purchase should be created with all fields', () {
      final now = DateTime.now();
      final items = [
        PurchaseItem(
          productId: 'prod-001',
          productName: 'T-Shirt',
          variantBarcode: 'AAA111',
          variantSize: 'S',
          quantity: 10,
          costPrice: 100.0,
          sellingPrice: 199.0,
          lineTotal: 1000.0,
        ),
        PurchaseItem(
          productId: 'prod-001',
          productName: 'T-Shirt',
          variantBarcode: 'BBB222',
          variantSize: 'M',
          quantity: 5,
          costPrice: 100.0,
          sellingPrice: 199.0,
          lineTotal: 500.0,
        ),
      ];

      final purchase = Purchase(
        id: 'pur-001',
        purchaseNumber: 'PUR-20250624-0001',
        supplierId: 'sup-001',
        supplierName: 'Test Supplier',
        purchaseDate: now,
        items: items,
        subtotal: 1500.0,
        discount: 50.0,
        tax: 0,
        grandTotal: 1450.0,
        notes: 'First purchase order',
        createdDate: now,
      );

      expect(purchase.id, 'pur-001');
      expect(purchase.purchaseNumber, 'PUR-20250624-0001');
      expect(purchase.supplierId, 'sup-001');
      expect(purchase.supplierName, 'Test Supplier');
      expect(purchase.items.length, 2);
      expect(purchase.subtotal, 1500.0);
      expect(purchase.discount, 50.0);
      expect(purchase.grandTotal, 1450.0);
      expect(purchase.notes, 'First purchase order');
    });

    test('Purchase subtotal should equal sum of line totals', () {
      final items = [
        PurchaseItem(
          productId: 'p1',
          productName: 'Item A',
          variantBarcode: 'BAR1',
          variantSize: 'S',
          quantity: 3,
          costPrice: 50.0,
          sellingPrice: 100.0,
          lineTotal: 150.0,
        ),
        PurchaseItem(
          productId: 'p2',
          productName: 'Item B',
          variantBarcode: 'BAR2',
          variantSize: 'M',
          quantity: 2,
          costPrice: 75.0,
          sellingPrice: 150.0,
          lineTotal: 150.0,
        ),
      ];

      final subtotal = items.fold(0.0, (sum, item) => sum + item.lineTotal);
      expect(subtotal, 300.0);
    });

    test('Purchase default discount and tax should be zero', () {
      final purchase = Purchase(
        id: 'pur-002',
        purchaseNumber: 'PUR-20250624-0002',
        supplierId: 'sup-001',
        supplierName: 'Test Supplier',
        purchaseDate: DateTime.now(),
        items: [],
        subtotal: 0,
        grandTotal: 0,
        createdDate: DateTime.now(),
      );

      expect(purchase.discount, 0);
      expect(purchase.tax, 0);
      expect(purchase.notes, '');
    });
  });
}
