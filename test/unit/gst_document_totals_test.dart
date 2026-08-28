import 'package:flutter_test/flutter_test.dart';
import 'package:atomid/data/models/purchase_model.dart';
import 'package:atomid/data/models/sale_model.dart';
import 'package:atomid/domain/document_totals.dart';

void main() {
  test('DocumentTotals computes sales GST metrics correctly', () {
    final sale1 = Sale(
      id: 's1',
      invoiceNumber: 'INV-1',
      date: DateTime.now(),
      subtotal: 1050.0,
      taxableAmount: 1000.0,
      cgstAmount: 25.0,
      sgstAmount: 25.0,
      utgstAmount: 0.0,
      igstAmount: 0.0,
      cessAmount: 0.0,
      roundOff: 0.0,
      grandTotal: 1050.0,
      items: [
        SaleItem(
          productId: 'p1',
          productName: 'Top',
          variantBarcode: 'b1',
          variantSize: 'S',
          price: 1050.0,
          quantity: 1,
          total: 1050.0,
          hsn: '6204',
          taxableValue: 1000.0,
          cgstAmount: 25.0,
          sgstAmount: 25.0,
        ),
      ],
    );

    final sale2 = Sale(
      id: 's2',
      invoiceNumber: 'INV-2',
      date: DateTime.now(),
      subtotal: 2240.0,
      taxableAmount: 2000.0,
      cgstAmount: 0.0,
      sgstAmount: 0.0,
      utgstAmount: 0.0,
      igstAmount: 240.0,
      cessAmount: 0.0,
      roundOff: 0.0,
      grandTotal: 2240.0,
      items: [
        SaleItem(
          productId: 'p2',
          productName: 'Saree',
          variantBarcode: 'b2',
          variantSize: 'Free',
          price: 2240.0,
          quantity: 1,
          total: 2240.0,
          hsn: '5208',
          taxableValue: 2000.0,
          igstAmount: 240.0,
        ),
      ],
    );

    final sales = <Sale>[sale1, sale2];

    expect(DocumentTotals.salesRevenue(sales), 3290.0);
    expect(DocumentTotals.salesTaxable(sales), 3000.0);
    expect(DocumentTotals.salesCgst(sales), 25.0);
    expect(DocumentTotals.salesSgst(sales), 25.0);
    expect(DocumentTotals.salesIgst(sales), 240.0);
    expect(DocumentTotals.salesTotalGst(sales), 290.0);
  });

  test('DocumentTotals computes purchase GST metrics correctly', () {
    final pur1 = Purchase(
      id: 'p1',
      purchaseNumber: 'PUR-1',
      purchaseDate: DateTime.now(),
      supplierId: 's1',
      supplierName: 'Sup 1',
      subtotal: 5000.0,
      taxableAmount: 5000.0,
      cgstAmount: 125.0,
      sgstAmount: 125.0,
      tax: 250.0,
      grandTotal: 5250.0,
      items: [],
    );

    final pur2 = Purchase(
      id: 'p2',
      purchaseNumber: 'PUR-2',
      purchaseDate: DateTime.now(),
      supplierId: 's2',
      supplierName: 'Sup 2',
      subtotal: 8000.0,
      taxableAmount: 8000.0,
      igstAmount: 960.0,
      tax: 960.0,
      grandTotal: 8960.0,
      isInterState: true,
      items: [],
    );

    final purchases = <Purchase>[pur1, pur2];

    expect(DocumentTotals.purchaseCost(purchases), 14210.0);
    expect(DocumentTotals.purchaseTaxable(purchases), 13000.0);
    expect(DocumentTotals.purchaseCgst(purchases), 125.0);
    expect(DocumentTotals.purchaseSgst(purchases), 125.0);
    expect(DocumentTotals.purchaseIgst(purchases), 960.0);
    expect(DocumentTotals.purchaseTotalGst(purchases), 1210.0);
  });
}
