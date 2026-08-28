import 'package:atomid/core/utils/formatters.dart';
import 'package:atomid/data/models/purchase_model.dart';
import 'package:atomid/data/models/sale_model.dart';

/// The figures a printed document reports, computed away from the PDF layer.
class DocumentTotals {
  const DocumentTotals._();

  /// Total of a sales report: what the shop took across the listed invoices.
  static double salesRevenue(Iterable<Sale> sales) =>
      Fmt.round2(sales.fold(0.0, (sum, s) => sum + s.grandTotal));

  /// Total taxable turnover across sales.
  static double salesTaxable(Iterable<Sale> sales) =>
      Fmt.round2(sales.fold(0.0, (sum, s) => sum + s.taxableAmount));

  /// Total CGST collected across sales.
  static double salesCgst(Iterable<Sale> sales) =>
      Fmt.round2(sales.fold(0.0, (sum, s) => sum + s.cgstAmount));

  /// Total SGST collected across sales.
  static double salesSgst(Iterable<Sale> sales) =>
      Fmt.round2(sales.fold(0.0, (sum, s) => sum + s.sgstAmount));

  /// Total UTGST collected across sales.
  static double salesUtgst(Iterable<Sale> sales) =>
      Fmt.round2(sales.fold(0.0, (sum, s) => sum + s.utgstAmount));

  /// Total IGST collected across sales.
  static double salesIgst(Iterable<Sale> sales) =>
      Fmt.round2(sales.fold(0.0, (sum, s) => sum + s.igstAmount));

  /// Total Cess collected across sales.
  static double salesCess(Iterable<Sale> sales) =>
      Fmt.round2(sales.fold(0.0, (sum, s) => sum + s.cessAmount));

  /// Total GST + Cess collected across sales.
  static double salesTotalGst(Iterable<Sale> sales) => Fmt.round2(
    sales.fold(
      0.0,
      (sum, s) => sum + (s.totalGst > 0 ? s.totalGst : s.taxAmount),
    ),
  );

  /// Units sold across the listed invoices.
  static int salesUnits(Iterable<Sale> sales) => sales.fold(
    0,
    (sum, s) => sum + s.items.fold(0, (n, item) => n + item.quantity),
  );

  /// Average basket.
  static double averageBasket(Iterable<Sale> sales) {
    final count = sales.length;
    if (count == 0) return 0;
    return Fmt.round2(salesRevenue(sales) / count);
  }

  /// Total cost of the listed purchase orders.
  static double purchaseCost(Iterable<Purchase> purchases) =>
      Fmt.round2(purchases.fold(0.0, (sum, p) => sum + p.grandTotal));

  /// Total purchase taxable value.
  static double purchaseTaxable(Iterable<Purchase> purchases) =>
      Fmt.round2(purchases.fold(0.0, (sum, p) => sum + p.taxableAmount));

  /// Total purchase CGST paid.
  static double purchaseCgst(Iterable<Purchase> purchases) =>
      Fmt.round2(purchases.fold(0.0, (sum, p) => sum + p.cgstAmount));

  /// Total purchase SGST paid.
  static double purchaseSgst(Iterable<Purchase> purchases) => Fmt.round2(
    purchases.fold(0.0, (sum, p) => sum + p.sgstAmount + p.utgstAmount),
  );

  /// Total purchase IGST paid.
  static double purchaseIgst(Iterable<Purchase> purchases) =>
      Fmt.round2(purchases.fold(0.0, (sum, p) => sum + p.igstAmount));

  /// Total purchase GST paid.
  static double purchaseTotalGst(Iterable<Purchase> purchases) =>
      Fmt.round2(purchases.fold(0.0, (sum, p) => sum + p.tax));

  static int purchaseUnits(Iterable<Purchase> purchases) => purchases.fold(
    0,
    (sum, p) => sum + p.items.fold(0, (n, item) => n + item.quantity),
  );

  /// What an invoice's own lines add up to.
  static double invoiceLineTotal(Sale sale) =>
      Fmt.round2(sale.items.fold(0.0, (sum, i) => sum + i.total));

  /// True when an invoice's stored totals are internally consistent.
  static bool invoiceIsConsistent(Sale sale, {required bool taxIsExclusive}) {
    final afterDiscounts = Fmt.round2(
      sale.subtotal - sale.discountAmount - sale.rewardDiscountAmount,
    );
    final expectedPreRound = taxIsExclusive
        ? Fmt.round2(afterDiscounts + sale.taxAmount)
        : afterDiscounts;
    final expected = Fmt.round2(expectedPreRound + sale.roundOff);

    return (expected - sale.grandTotal).abs() < 0.005;
  }

  /// True when the stored discount percentage reproduces the stored discount amount.
  static bool discountPercentReproduces(Sale sale) {
    if (sale.subtotal <= 0 || sale.discountPercent <= 0) return false;
    final implied = Fmt.round2(sale.subtotal * sale.discountPercent / 100);
    return (implied - sale.discountAmount).abs() < 0.005;
  }
}
