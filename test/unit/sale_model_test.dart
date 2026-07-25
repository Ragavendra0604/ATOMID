import 'package:flutter_test/flutter_test.dart';
import 'package:atomid/data/models/sale_model.dart';

void main() {
  group('SaleItem Model Tests', () {
    test('should create SaleItem with default values', () {
      final item = SaleItem(
        productId: 'prod1',
        productName: 'T-Shirt',
        productCode: 'TSHIRT01',
        variantBarcode: 'BARCODE123',
        variantSize: 'L',
        price: 20.0,
        quantity: 2,
        total: 40.0,
      );

      expect(item.productId, 'prod1');
      expect(item.productName, 'T-Shirt');
      expect(item.quantity, 2);
    });
  });

  group('Sale Model Tests', () {
    test('should calculate total items correctly', () {
      final sale = Sale(
        id: 'sale1',
        invoiceNumber: 'INV001',
        date: DateTime.now(),
        customerId: 'cust1',
        customerName: 'John Doe',
        subtotal: 100.0,
        discountPercent: 0,
        discountAmount: 10.0,
        taxAmount: 5.0,
        grandTotal: 95.0,
        paymentMethod: 'Cash',
        items: [
          SaleItem(
            productId: 'p1',
            productName: 'Item 1',
            productCode: 'c1',
            variantBarcode: 'b1',
            variantSize: 'M',
            price: 50.0,
            quantity: 1,
            total: 50.0,
          ),
          SaleItem(
            productId: 'p2',
            productName: 'Item 2',
            productCode: 'c2',
            variantBarcode: 'b2',
            variantSize: 'S',
            price: 25.0,
            quantity: 2,
            total: 50.0,
          ),
        ],
      );

      expect(sale.id, 'sale1');
      expect(sale.items.length, 2);
      expect(sale.items.fold<int>(0, (sum, item) => sum + item.quantity), 3);
      expect(sale.grandTotal, 95.0);
      expect(sale.rewardDiscountAmount, 0.0);
      expect(sale.rewardPointsEarned, 0.0);
    });
  });
}
