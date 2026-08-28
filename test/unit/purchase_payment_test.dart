import 'package:flutter_test/flutter_test.dart';

import 'package:atomid/core/utils/ids.dart';
import 'package:atomid/data/models/purchase_model.dart';
import 'package:atomid/data/models/supplier_ledger_model.dart';
import 'package:atomid/domain/purchase_payment.dart';

/// `Purchase.paymentStatus` was declared, displayed and synced, and nothing in
/// the app ever wrote anything to it but its 'Unpaid' default — so every
/// received order showed as unpaid forever, however much had been handed over.
/// Status is derived from the supplier ledger now; this covers the derivation.
void main() {
  SupplierLedger row({
    required String reference,
    double debit = 0,
    double credit = 0,
  }) => SupplierLedger(
    id: Ids.generate(),
    supplierId: 's1',
    date: DateTime(2026, 8, 1),
    transactionType: debit > 0 ? 'Payment' : 'Purchase',
    referenceId: reference,
    debit: debit,
    credit: credit,
  );

  group('what has been paid against an order', () {
    test('sums only rows filed under that purchase number', () {
      final ledger = [
        row(reference: 'PO-1', credit: 5000), // the order itself
        row(reference: 'PO-1', debit: 2000),
        row(reference: 'PO-1', debit: 500),
        row(reference: 'PO-2', debit: 9999), // another order
        row(reference: 'PAY-77', debit: 4000), // account-level settlement
      ];

      expect(PurchasePayment.paidAgainst('PO-1', ledger), 2500);
    });

    test('an order with no payments has had nothing paid', () {
      expect(
        PurchasePayment.paidAgainst('PO-9', [
          row(reference: 'PO-1', debit: 10),
        ]),
        0,
      );
    });

    test('an empty purchase number matches nothing', () {
      // Guards against a blank reference sweeping up every account-level row.
      expect(
        PurchasePayment.paidAgainst('', [row(reference: '', debit: 500)]),
        0,
      );
    });
  });

  group('status', () {
    test('nothing paid is Unpaid', () {
      expect(
        PurchasePayment.status(grandTotal: 5000, paidSoFar: 0),
        PurchasePayment.unpaid,
      );
    });

    test('something paid is Partial', () {
      expect(
        PurchasePayment.status(grandTotal: 5000, paidSoFar: 2500),
        PurchasePayment.partial,
      );
    });

    test('paid in full is Paid', () {
      expect(
        PurchasePayment.status(grandTotal: 5000, paidSoFar: 5000),
        PurchasePayment.paid,
      );
    });

    test('a half-paisa short still counts as settled', () {
      // Every figure is rounded to two places, so a gap this small is
      // floating-point noise rather than an unpaid balance — and an order a
      // shop considers closed should not sit in Partial forever.
      expect(
        PurchasePayment.status(grandTotal: 5000, paidSoFar: 4999.999),
        PurchasePayment.paid,
      );
    });

    test('overpaying still reads as Paid', () {
      expect(
        PurchasePayment.status(grandTotal: 5000, paidSoFar: 6000),
        PurchasePayment.paid,
      );
    });

    test('an order worth nothing is not perpetually outstanding', () {
      expect(
        PurchasePayment.status(grandTotal: 0, paidSoFar: 0),
        PurchasePayment.paid,
      );
    });
  });

  group('outstanding', () {
    test('is what is left to pay', () {
      expect(
        PurchasePayment.outstanding(grandTotal: 5000, paidSoFar: 1500),
        3500,
      );
    });

    test('never goes negative on an overpayment', () {
      // The excess is real and sits on the supplier balance, which is where a
      // shopkeeper looks for it — an order showing minus one thousand due is
      // just confusing.
      expect(PurchasePayment.outstanding(grandTotal: 5000, paidSoFar: 6000), 0);
    });
  });

  group('allocating an existing shop\'s payments', () {
    Purchase order(
      String number,
      double total,
      DateTime when, {
      String status = 'Received',
    }) => Purchase(
      id: Ids.generate(),
      purchaseNumber: number,
      supplierId: 's1',
      supplierName: 'Supplier',
      purchaseDate: when,
      createdDate: when,
      status: status,
      items: const [],
      subtotal: total,
      grandTotal: total,
    );

    test('account-level payments settle the oldest order first', () {
      // This is what every existing installation looks like: real payments,
      // none of them naming an order, and every order reading Unpaid.
      final orders = [
        order('PO-1', 5000, DateTime(2026, 6, 1)),
        order('PO-2', 3000, DateTime(2026, 7, 1)),
        order('PO-3', 2000, DateTime(2026, 8, 1)),
      ];
      final ledger = [row(reference: 'PAY-01', debit: 6000)];

      final paid = PurchasePayment.allocate(
        orders: orders,
        ledger: ledger,
        isReceived: (p) => p.status == 'Received',
      );

      expect(paid['PO-1'], 5000, reason: 'oldest bill clears first');
      expect(paid['PO-2'], 1000, reason: 'the remainder part-pays the next');
      expect(paid['PO-3'], isNull, reason: 'nothing reached the newest');
    });

    test('a payment naming an order settles that order, not the oldest', () {
      final orders = [
        order('PO-1', 5000, DateTime(2026, 6, 1)),
        order('PO-2', 3000, DateTime(2026, 7, 1)),
      ];
      final ledger = [row(reference: 'PO-2', debit: 3000)];

      final paid = PurchasePayment.allocate(
        orders: orders,
        ledger: ledger,
        isReceived: (p) => p.status == 'Received',
      );

      expect(paid['PO-2'], 3000);
      expect(paid['PO-1'], isNull);
    });

    test('an unreceived order takes no part', () {
      // Nothing has been credited to the supplier for it, so there is nothing
      // to settle — and letting it absorb the pool would leave a received
      // order wrongly unpaid.
      final orders = [
        order('PO-DRAFT', 5000, DateTime(2026, 5, 1), status: 'Issued'),
        order('PO-1', 2000, DateTime(2026, 6, 1)),
      ];
      final ledger = [row(reference: 'PAY-01', debit: 2000)];

      final paid = PurchasePayment.allocate(
        orders: orders,
        ledger: ledger,
        isReceived: (p) => p.status == 'Received',
      );

      expect(paid['PO-DRAFT'], isNull);
      expect(paid['PO-1'], 2000);
    });

    test('paying more than everything owed does not invent an order', () {
      final orders = [order('PO-1', 1000, DateTime(2026, 6, 1))];
      final paid = PurchasePayment.allocate(
        orders: orders,
        ledger: [row(reference: 'PAY-01', debit: 5000)],
        isReceived: (p) => p.status == 'Received',
      );

      expect(paid['PO-1'], 1000, reason: 'capped at what the order is worth');
      expect(paid, hasLength(1));
    });

    test('credits are never mistaken for payments', () {
      final paid = PurchasePayment.allocate(
        orders: [order('PO-1', 1000, DateTime(2026, 6, 1))],
        ledger: [row(reference: 'PO-1', credit: 1000)],
        isReceived: (p) => p.status == 'Received',
      );

      expect(paid['PO-1'], isNull, reason: 'a credit is the bill, not payment');
    });
  });
}
