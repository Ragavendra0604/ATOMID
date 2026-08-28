import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:atomid/data/models/supplier_model.dart';
import 'package:atomid/presentation/features/price_tag/bulk_generator_screen.dart';
import 'package:atomid/presentation/features/reports/reports_dashboard_screen.dart';
import 'package:atomid/presentation/features/suppliers/supplier_details_screen.dart';

import '../support/screen_harness.dart';

/// Overflow regressions on the smallest phone still in use.
///
/// `responsive_layout_test.dart` already sweeps every screen across the width
/// matrix, but it only ever sees a screen's *first* tab and never opens a
/// detail screen. That is exactly where these defects lived: the Reports
/// dashboard laid out fine on Overview while the GSTR-1 and Purchase GST cards
/// overflowed, and the supplier ledger was never rendered at all because only
/// the supplier *list* is in the sweep.
///
/// Everything here runs at 320x640 — the narrowest viewport in the matrix,
/// where a long label beside a six-figure amount has nowhere to go.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Taken from the shared matrix rather than constructed: `Viewport` is also
  // a Flutter widget, so naming the type here would be an ambiguous import.
  final phone = responsiveMatrix.first;

  late ScreenHarness harness;
  late Supplier supplier;

  setUpAll(() async {
    expect(phone.width, 320);
    expect(phone.height, 640);

    harness = await ScreenHarness.open();

    await harness.store.addProduct(
      name: 'Long Product Name For Layout Pressure',
      price: 1499.99,
      quantity: 42,
      gstRate: 5,
    );

    // Long names and six-figure amounts: an empty store hides overflow, and
    // it is the width of a rendered rupee amount that breaks these rows.
    supplier = await harness.store.addSupplier(
      name: 'Acme Textiles And Weaving Company Private Limited',
    );

    await harness.repository.addSupplierLedgerEntry(
      supplierId: supplier.id,
      date: DateTime(2026, 1, 10),
      transactionType: 'Purchase',
      referenceId: 'PUR-2026-000141',
      credit: 987654.32,
      notes: 'Opening consignment of cotton and silk',
    );
    await harness.repository.addSupplierLedgerEntry(
      supplierId: supplier.id,
      date: DateTime(2026, 1, 12),
      transactionType: 'Payment',
      referenceId: 'PAY-8891234567',
      debit: 123456.78,
      notes: 'Part settlement by bank transfer',
    );
  });

  tearDownAll(() => harness.close());

  /// Opens [label]'s tab and returns any layout error it raised.
  ///
  /// The tab strip scrolls on a narrow phone, so the tab has to be brought
  /// into view before it can be tapped.
  Future<Object?> openTab(WidgetTester tester, String label) async {
    final tab = find.widgetWithText(Tab, label);
    expect(tab, findsOneWidget, reason: 'no tab labelled "$label"');
    // Only the Reports tab strip scrolls; `ensureVisible` throws when there is
    // no Scrollable above the tab, which is the case on a two-tab bar.
    try {
      await tester.ensureVisible(tab);
      await tester.pumpAndSettle();
    } catch (_) {}
    await tester.tap(tab);
    await tester.pumpAndSettle();
    return tester.takeException();
  }

  group('Reports dashboard at $phone', () {
    testWidgets('the dashboard itself lays out', (tester) async {
      final error = await renderAt(
        tester,
        harness,
        const ReportsDashboardScreen(),
        phone,
      );
      expect(error, isNull, reason: 'Reports dashboard overflows:\n$error');
    });

    testWidgets('the GSTR-1 card lays out', (tester) async {
      await renderAt(tester, harness, const ReportsDashboardScreen(), phone);
      final error = await openTab(tester, 'Sales GST (GSTR-1)');
      expect(error, isNull, reason: 'GSTR-1 card overflows:\n$error');
    });

    testWidgets('the HSN summary lays out', (tester) async {
      await renderAt(tester, harness, const ReportsDashboardScreen(), phone);
      final error = await openTab(tester, 'HSN Summary');
      expect(error, isNull, reason: 'HSN summary overflows:\n$error');
    });

    testWidgets('the Purchase GST (GSTR-3B/2B) card lays out', (tester) async {
      await renderAt(tester, harness, const ReportsDashboardScreen(), phone);
      final error = await openTab(tester, 'Purchase GST (GSTR-3B/2B)');
      expect(error, isNull, reason: 'Purchase GST card overflows:\n$error');
    });
  });

  /// Regression: the product group in All-products mode carried a
  /// `PageStorageKey`. `ExpansionTile` writes its expanded flag into
  /// PageStorage under the nearest such key, and the Qty field inside then
  /// read that bucket while restoring its scroll offset — "type 'bool' is not
  /// a subtype of type 'double?'", thrown during layout on a real device.
  ///
  /// Rendered at a normal phone width rather than 320: this is about the
  /// crash, not about overflow.
  group('Bulk price tag generator', () {
    final normalPhone = responsiveMatrix.firstWhere((v) => v.width == 390);

    testWidgets('expanding a product group does not throw', (tester) async {
      final error = await renderAt(
        tester,
        harness,
        const BulkGeneratorScreen(),
        normalPhone,
      );
      expect(error, isNull, reason: 'the generator does not open:\n$error');

      await tester.tap(find.text('All products'));
      await tester.pumpAndSettle();
      expect(
        tester.takeException(),
        isNull,
        reason: 'switching to All products threw',
      );

      final group = find.textContaining('Long Product Name');
      expect(group, findsWidgets, reason: 'the seeded product is not listed');
      // Scrolled into view first. Without this the tap lands outside the
      // render tree, misses, and the tile never expands — the test passed
      // while exercising nothing.
      await tester.ensureVisible(group.first);
      await tester.pumpAndSettle();
      await tester.tap(group.first);
      await tester.pumpAndSettle();

      // The Qty field is now mounted inside the expanded tile.
      expect(
        tester.takeException(),
        isNull,
        reason: 'expanding the product group threw',
      );
      // The Qty field only exists inside an expanded group, so finding it is
      // what proves the tile opened and the crash path ran.
      expect(
        find.widgetWithText(TextField, 'Qty'),
        findsWidgets,
        reason: 'the product group did not expand, so nothing was tested',
      );
    });
  });

  group('Supplier details at $phone', () {
    testWidgets('the details tab lays out', (tester) async {
      final error = await renderAt(
        tester,
        harness,
        SupplierDetailsScreen(supplier: supplier),
        phone,
      );
      expect(error, isNull, reason: 'Supplier details overflows:\n$error');
    });

    testWidgets('the ledger tab lays out with entries', (tester) async {
      await renderAt(
        tester,
        harness,
        SupplierDetailsScreen(supplier: supplier),
        phone,
      );
      final error = await openTab(tester, 'Ledger');
      expect(error, isNull, reason: 'Supplier ledger overflows:\n$error');

      // The balance header and at least one ledger card actually rendered —
      // an empty list would pass the overflow check for the wrong reason.
      expect(find.text('Current Balance (Owed)'), findsOneWidget);

      // Only the newest card fits on a 320x640 screen, so this asserts on the
      // one that is actually built rather than on both seeded entries.
      expect(find.text('Payment made'), findsWidgets);

      // And the raw ledger word is no longer a tile title — it reads as a
      // direction now, with the transaction type moved to the subtitle.
      expect(find.text('Payment'), findsNothing);
    });

    testWidgets('recording a payment completes without an exception', (
      tester,
    ) async {
      await renderAt(
        tester,
        harness,
        SupplierDetailsScreen(supplier: supplier),
        phone,
      );
      expect(await openTab(tester, 'Ledger'), isNull);

      final before = harness.repository
          .getLedgerForSupplier(supplier.id)
          .length;

      await tester.tap(find.widgetWithText(ElevatedButton, 'Record Payment'));
      await tester.pumpAndSettle();
      expect(
        tester.takeException(),
        isNull,
        reason: 'the payment dialog does not lay out at $phone',
      );

      // The amount field is the first in the dialog.
      await tester.enterText(find.byType(TextField).first, '45678.90');
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ElevatedButton, 'Record'));
      await tester.pumpAndSettle();

      // The whole point: confirming used to put an error screen up.
      expect(
        tester.takeException(),
        isNull,
        reason: 'confirming a payment raised an exception',
      );

      expect(
        harness.repository.getLedgerForSupplier(supplier.id).length,
        before + 1,
        reason: 'the payment was not written',
      );
    });
  });
}
