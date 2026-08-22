import 'package:atomid/core/utils/formatters.dart';
import 'package:atomid/data/models/purchase_model.dart';
import 'package:atomid/data/models/sale_model.dart';

/// The figures a printed document reports, computed away from the PDF layer.
///
/// `ExportService` is 1,300 lines of `pdf` package widgets, which makes the
/// arithmetic inside it effectively untestable — asserting on rendered bytes
/// tests the renderer, not the maths. These are the numbers a shop owner
/// reconciles against the cash drawer, so they are pulled out here where they
/// can be checked directly.
class DocumentTotals {
  const DocumentTotals._();

  /// Total of a sales report: what the shop took across the listed invoices.
  static double salesRevenue(Iterable<Sale> sales) =>
      Fmt.round2(sales.fold(0.0, (sum, s) => sum + s.grandTotal));

  /// Units sold across the listed invoices.
  static int salesUnits(Iterable<Sale> sales) => sales.fold(
    0,
    (sum, s) => sum + s.items.fold(0, (n, item) => n + item.quantity),
  );

  /// Average basket. Zero rather than a division by zero on an empty report —
  /// a report for a day with no trade is a normal thing to print.
  static double averageBasket(Iterable<Sale> sales) {
    final count = sales.length;
    if (count == 0) return 0;
    return Fmt.round2(salesRevenue(sales) / count);
  }

  /// Total cost of the listed purchase orders.
  static double purchaseCost(Iterable<Purchase> purchases) =>
      Fmt.round2(purchases.fold(0.0, (sum, p) => sum + p.grandTotal));

  static int purchaseUnits(Iterable<Purchase> purchases) => purchases.fold(
    0,
    (sum, p) => sum + p.items.fold(0, (n, item) => n + item.quantity),
  );

  /// What an invoice's own lines add up to.
  ///
  /// Deliberately recomputed from the stored line items rather than read from
  /// `sale.subtotal`, so a document that disagrees with itself is detectable
  /// rather than merely printed.
  static double invoiceLineTotal(Sale sale) =>
      Fmt.round2(sale.items.fold(0.0, (sum, i) => sum + i.total));

  /// True when an invoice's stored totals are internally consistent:
  /// lines − discounts (+ or containing tax) == grand total.
  ///
  /// Tax mode matters here. Under `exclusive` the tax was added on top, so it
  /// forms part of the grand total; under `inclusive` it was extracted from a
  /// figure the customer already paid, so adding it again would double-count.
  static bool invoiceIsConsistent(Sale sale, {required bool taxIsExclusive}) {
    final afterDiscounts = Fmt.round2(
      sale.subtotal - sale.discountAmount - sale.rewardDiscountAmount,
    );
    final expected = taxIsExclusive
        ? Fmt.round2(afterDiscounts + sale.taxAmount)
        : afterDiscounts;
    // A hundredth of a currency unit of slack: every input is already rounded
    // to two places, so anything larger is a real disagreement.
    return (expected - sale.grandTotal).abs() < 0.005;
  }

  /// True when the stored discount percentage reproduces the stored discount
  /// amount at the two decimals an invoice prints.
  ///
  /// It usually does. It cannot when the percentage is an *effective* rate —
  /// the cashier asked for more than the basket had left after reward points,
  /// so the discount was capped and the rate back-derived from the capped
  /// amount. Two decimals of a percentage is worth 0.005% of the basket,
  /// which on a large sale is rupees, so a customer recomputing the printed
  /// rate lands somewhere the invoice does not.
  ///
  /// The document uses this to decide whether to name a rate at all: better a
  /// bare "Discount" line than a percentage that does not survive being
  /// checked.
  static bool discountPercentReproduces(Sale sale) {
    if (sale.subtotal <= 0 || sale.discountPercent <= 0) return false;
    final implied = Fmt.round2(sale.subtotal * sale.discountPercent / 100);
    return (implied - sale.discountAmount).abs() < 0.005;
  }
}
