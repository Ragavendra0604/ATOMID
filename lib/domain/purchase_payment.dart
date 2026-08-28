import 'package:atomid/data/models/purchase_model.dart';
import 'package:atomid/data/models/supplier_ledger_model.dart';

/// Whether a purchase order has been paid for, derived from the ledger.
///
/// `Purchase.paymentStatus` exists on the model, is displayed and is synced —
/// and nothing in the app ever wrote anything to it but its `'Unpaid'`
/// default. Every order a shop had ever received showed as unpaid forever,
/// however much had been handed over.
///
/// It is derived here rather than fixed by writing to that field, because a
/// stored total that duplicates a ledger is the same shape as the customer
/// merge and the stock edit: it agrees with reality until something changes
/// underneath it. The supplier ledger already records every payment; this
/// just reads it.
///
/// Attribution is by `referenceId`. A purchase files its credit under the
/// purchase number when it is received, and a payment recorded against an
/// order files its debit under the same number. A payment made against the
/// supplier account as a whole carries its own reference and is deliberately
/// not counted toward any one order — it settles the balance, not a document.
class PurchasePayment {
  const PurchasePayment._();

  static const unpaid = 'Unpaid';
  static const partial = 'Partial';
  static const paid = 'Paid';

  /// Half a paisa: every figure involved is already rounded to two places, so
  /// a larger gap is a real shortfall rather than floating-point noise.
  static const double _tolerance = 0.005;

  /// Total paid against one purchase number.
  static double paidAgainst(
    String purchaseNumber,
    Iterable<SupplierLedger> ledger,
  ) {
    if (purchaseNumber.isEmpty) return 0;
    var total = 0.0;
    for (final entry in ledger) {
      if (entry.referenceId == purchaseNumber) total += entry.debit;
    }
    return total;
  }

  /// The status to show for an order, given what has been paid against it.
  ///
  /// An order that owes nothing is [paid] whatever has been paid against it —
  /// a zero-value order is not perpetually outstanding.
  static String status({
    required double grandTotal,
    required double paidSoFar,
  }) {
    if (grandTotal <= _tolerance) return paid;
    if (paidSoFar <= _tolerance) return unpaid;
    if (paidSoFar + _tolerance >= grandTotal) return paid;
    return partial;
  }

  /// Spreads a supplier's payments across their received orders.
  ///
  /// Two kinds of payment exist, and a shop that has been running for a while
  /// has only the second kind:
  ///
  /// * **Filed against an order** — the debit carries the purchase number.
  ///   These settle that order and nothing else.
  /// * **Paid to the account** — the shopkeeper hands over money for what is
  ///   owed, without naming an invoice. Until this app had a per-order payment
  ///   action, *every* payment was this kind, which is why an existing
  ///   installation has real payments that belong to no order.
  ///
  /// Whatever is not tied to an order is allocated oldest-order-first, which
  /// is how open-item settlement normally works and how a shopkeeper would
  /// describe it: money paid to a supplier clears the oldest bill first. That
  /// makes historical orders show the status they should have shown all
  /// along, rather than every one of them reading Unpaid forever.
  ///
  /// Only received orders take part. An order that has not been received has
  /// not credited the supplier, so there is nothing on it to settle.
  static Map<String, double> allocate({
    required Iterable<Purchase> orders,
    required Iterable<SupplierLedger> ledger,
    required bool Function(Purchase) isReceived,
  }) {
    final received = orders.where(isReceived).toList()
      ..sort((a, b) => a.purchaseDate.compareTo(b.purchaseDate));

    final paid = <String, double>{};
    var pool = 0.0;

    // Split the ledger's payments into "belongs to an order" and "belongs to
    // the account".
    final numbers = {for (final o in received) o.purchaseNumber};
    for (final entry in ledger) {
      if (entry.debit <= 0) continue;
      if (entry.referenceId.isNotEmpty && numbers.contains(entry.referenceId)) {
        paid.update(
          entry.referenceId,
          (v) => v + entry.debit,
          ifAbsent: () => entry.debit,
        );
      } else {
        pool += entry.debit;
      }
    }

    for (final order in received) {
      if (pool <= _tolerance) break;
      final already = paid[order.purchaseNumber] ?? 0;
      final owed = order.grandTotal - already;
      if (owed <= _tolerance) continue;

      final take = owed < pool ? owed : pool;
      paid[order.purchaseNumber] = already + take;
      pool -= take;
    }

    return paid;
  }

  /// What is still owed on an order, never negative.
  ///
  /// An overpayment shows as settled rather than as a negative amount due:
  /// the excess is real and sits on the supplier's balance, which is where a
  /// shopkeeper looks for it.
  static double outstanding({
    required double grandTotal,
    required double paidSoFar,
  }) {
    final left = grandTotal - paidSoFar;
    return left < 0 ? 0 : left;
  }
}
