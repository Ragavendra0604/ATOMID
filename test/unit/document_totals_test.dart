import 'package:flutter_test/flutter_test.dart';

import 'package:atomid/data/models/purchase_model.dart';
import 'package:atomid/data/models/sale_model.dart';
import 'package:atomid/domain/document_totals.dart';

/// Cover for T-1. `ExportService` had no tests at all, and it produces the
/// documents customers physically receive.
///
/// Asserting on rendered PDF bytes would test the `pdf` package, so the
/// arithmetic was lifted into `DocumentTotals` and is checked here. The report
/// generators now call the same functions, so a printed figure and a tested
/// figure cannot disagree.
void main() {
  Sale sale({
    String id = 's1',
    double subtotal = 1000,
    double discount = 0,
    double reward = 0,
    double tax = 0,
    double grand = 1000,
    List<SaleItem> items = const [],
  }) => Sale(
    id: id,
    invoiceNumber: 'INV-$id',
    date: DateTime(2026, 6, 15),
    customerId: '',
    customerName: 'Walk-In Customer',
    subtotal: subtotal,
    discountPercent: 0,
    discountAmount: discount,
    rewardDiscountAmount: reward,
    taxAmount: tax,
    grandTotal: grand,
    paymentMethod: 'Cash',
    items: items,
  );

  SaleItem line({double price = 100, int qty = 1, double? total}) => SaleItem(
    productId: 'p1',
    productName: 'Item',
    productCode: 'C1',
    variantBarcode: 'B1',
    variantSize: 'M',
    price: price,
    quantity: qty,
    total: total ?? price * qty,
  );

  Purchase purchase({
    double grand = 500,
    List<PurchaseItem> items = const [],
  }) => Purchase(
    id: 'po1',
    purchaseNumber: 'PUR-1',
    supplierId: 's1',
    supplierName: 'Acme',
    purchaseDate: DateTime(2026, 6, 15),
    createdDate: DateTime(2026, 6, 15),
    subtotal: grand,
    grandTotal: grand,
    items: items,
  );

  PurchaseItem poLine({int qty = 1}) => PurchaseItem(
    productId: 'p1',
    productName: 'Item',
    variantBarcode: 'B1',
    variantSize: 'M',
    quantity: qty,
    costPrice: 10,
    sellingPrice: 20,
    lineTotal: 10.0 * qty,
  );

  group('sales report totals', () {
    test('an empty report reports zero rather than dividing by zero', () {
      expect(DocumentTotals.salesRevenue(const []), 0);
      expect(DocumentTotals.salesUnits(const []), 0);
      expect(DocumentTotals.averageBasket(const []), 0);
    });

    test('revenue and units add up across invoices', () {
      final sales = [
        sale(id: 'a', grand: 300, items: [line(price: 150, qty: 2)]),
        sale(id: 'b', grand: 200, items: [line(price: 100, qty: 2)]),
      ];

      expect(DocumentTotals.salesRevenue(sales), 500);
      expect(DocumentTotals.salesUnits(sales), 4);
      expect(DocumentTotals.averageBasket(sales), 250);
    });

    test('fractional amounts do not accumulate float error', () {
      // 0.1 + 0.2 is the classic case; three of them must not drift.
      final sales = [
        sale(id: 'a', grand: 0.1),
        sale(id: 'b', grand: 0.2),
        sale(id: 'c', grand: 0.3),
      ];

      expect(DocumentTotals.salesRevenue(sales), 0.6);
    });

    test('an average that does not divide evenly is rounded to money', () {
      final sales = [
        sale(id: 'a', grand: 10),
        sale(id: 'b', grand: 10),
        sale(id: 'c', grand: 10.01),
      ];

      // 30.01 / 3 = 10.003333…
      expect(DocumentTotals.averageBasket(sales), 10.0);
    });

    test('a very large total stays exact to the cent', () {
      final sales = [sale(id: 'a', grand: 9999999.99)];
      expect(DocumentTotals.salesRevenue(sales), 9999999.99);
    });

    test('a refund-shaped negative total is not silently dropped', () {
      final sales = [sale(id: 'a', grand: 500), sale(id: 'b', grand: -200)];
      expect(DocumentTotals.salesRevenue(sales), 300);
    });

    test('an invoice with no line items still counts its value', () {
      expect(DocumentTotals.salesRevenue([sale(grand: 250)]), 250);
      expect(DocumentTotals.salesUnits([sale(grand: 250)]), 0);
    });
  });

  group('purchase report totals', () {
    test('cost and units add up', () {
      final purchases = [
        purchase(grand: 300, items: [poLine(qty: 5)]),
        purchase(grand: 450, items: [poLine(qty: 3), poLine(qty: 2)]),
      ];

      expect(DocumentTotals.purchaseCost(purchases), 750);
      expect(DocumentTotals.purchaseUnits(purchases), 10);
    });

    test('an empty purchase report is zero', () {
      expect(DocumentTotals.purchaseCost(const []), 0);
      expect(DocumentTotals.purchaseUnits(const []), 0);
    });
  });

  group('invoice line total', () {
    test('sums the stored lines rather than trusting the header', () {
      final s = sale(
        subtotal: 999, // deliberately wrong
        items: [line(price: 100, qty: 2), line(price: 50, qty: 1)],
      );

      expect(DocumentTotals.invoiceLineTotal(s), 250);
    });

    test('an invoice with no lines totals zero', () {
      expect(DocumentTotals.invoiceLineTotal(sale()), 0);
    });
  });

  group('invoice internal consistency', () {
    test('a plain untaxed sale is consistent', () {
      final s = sale(subtotal: 1000, grand: 1000);
      expect(
        DocumentTotals.invoiceIsConsistent(s, taxIsExclusive: false),
        isTrue,
      );
    });

    test('a discounted sale is consistent', () {
      final s = sale(subtotal: 1000, discount: 100, grand: 900);
      expect(
        DocumentTotals.invoiceIsConsistent(s, taxIsExclusive: false),
        isTrue,
      );
    });

    test('discount plus reward points together are consistent', () {
      final s = sale(subtotal: 1000, discount: 100, reward: 50, grand: 850);
      expect(
        DocumentTotals.invoiceIsConsistent(s, taxIsExclusive: false),
        isTrue,
      );
    });

    test('exclusive tax is added on top', () {
      final s = sale(subtotal: 1000, tax: 180, grand: 1180);
      expect(
        DocumentTotals.invoiceIsConsistent(s, taxIsExclusive: true),
        isTrue,
      );
    });

    test('inclusive tax is already inside the total, not added again', () {
      // Shelf price 1000 with 18% already inside it: tax is extracted for the
      // invoice but the customer still pays 1000.
      final s = sale(subtotal: 1000, tax: 152.54, grand: 1000);
      expect(
        DocumentTotals.invoiceIsConsistent(s, taxIsExclusive: false),
        isTrue,
      );
      expect(
        DocumentTotals.invoiceIsConsistent(s, taxIsExclusive: true),
        isFalse,
        reason: 'treating inclusive tax as exclusive would double-count it',
      );
    });

    test('a discount taking the bill to zero is consistent', () {
      final s = sale(subtotal: 500, discount: 500, grand: 0);
      expect(
        DocumentTotals.invoiceIsConsistent(s, taxIsExclusive: false),
        isTrue,
      );
    });

    test('a total that does not match its parts is caught', () {
      final s = sale(subtotal: 1000, discount: 100, grand: 950);
      expect(
        DocumentTotals.invoiceIsConsistent(s, taxIsExclusive: false),
        isFalse,
        reason: 'a document that disagrees with itself must be detectable',
      );
    });

    test('sub-cent rounding slack is tolerated, larger drift is not', () {
      expect(
        DocumentTotals.invoiceIsConsistent(
          sale(subtotal: 100, grand: 100.004),
          taxIsExclusive: false,
        ),
        isTrue,
      );
      expect(
        DocumentTotals.invoiceIsConsistent(
          sale(subtotal: 100, grand: 100.02),
          taxIsExclusive: false,
        ),
        isFalse,
      );
    });
  });
}
