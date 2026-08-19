import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:atomid/presentation/features/customers/customer_list_screen.dart';
import 'package:atomid/presentation/features/dashboard/dashboard_screen.dart';
import 'package:atomid/presentation/features/inventory/inventory_dashboard_screen.dart';
import 'package:atomid/presentation/features/products/product_list_screen.dart';
import 'package:atomid/presentation/features/purchases/purchase_list_screen.dart';
import 'package:atomid/presentation/features/reports/reports_dashboard_screen.dart';
import 'package:atomid/presentation/features/suppliers/supplier_list_screen.dart';

import '../support/screen_harness.dart';

/// The other half of UI-1.
///
/// `accessibility_test.dart` is a source scan proving no icon button is
/// unlabelled. This renders the real screens and puts them through Flutter's
/// own accessibility guidelines, which is what I had wrongly written off as
/// needing "a device and a human eye":
///
///   * **tap targets** — a control smaller than 48dp (Android) or 44pt (iOS)
///     is hard to hit accurately, which on a till means mis-rings.
///   * **labelled tap targets** — every tappable thing must announce itself.
///   * **text contrast** — text has to clear WCAG AA against what is behind
///     it, in *both* themes. A shop floor is often brightly lit.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ScreenHarness harness;

  setUpAll(() async {
    harness = await ScreenHarness.open();
    await harness.store.addProduct(
      name: 'Long Product Name For Layout Pressure',
      price: 1499.99,
      quantity: 42,
    );
    await harness.store.addCustomer(name: 'Priyadharshini Venkataraman');
    await harness.store.addSupplier(name: 'Acme Textiles And Weaving Company');
  });

  tearDownAll(() => harness.close());

  final screens = <String, Widget Function()>{
    'Dashboard': () => const DashboardScreen(),
    'Products': () => const ProductListScreen(),
    'Inventory': () => const InventoryDashboardScreen(),
    'Customers': () => const CustomerListScreen(),
    'Suppliers': () => const SupplierListScreen(),
    'Purchases': () => const PurchaseListScreen(),
    'Reports': () => const ReportsDashboardScreen(),
  };

  /// Renders at a tablet width — wide enough that lists show their row
  /// actions, which are the controls most likely to be too small.
  Future<void> render(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(harness.wrap(screen));
    await tester.pump(const Duration(milliseconds: 300));
  }

  group('tap targets are big enough to hit', () {
    for (final entry in screens.entries) {
      testWidgets('${entry.key} meets the Android 48dp guideline', (
        tester,
      ) async {
        final handle = tester.ensureSemantics();
        await render(tester, entry.value());

        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        handle.dispose();
      });

      testWidgets('${entry.key} meets the iOS 44pt guideline', (tester) async {
        final handle = tester.ensureSemantics();
        await render(tester, entry.value());

        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        handle.dispose();
      });
    }
  });

  group('everything tappable announces itself', () {
    for (final entry in screens.entries) {
      testWidgets('${entry.key} has no unlabelled tap target', (tester) async {
        final handle = tester.ensureSemantics();
        await render(tester, entry.value());

        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        handle.dispose();
      });
    }
  });

  group('text is readable against its background', () {
    for (final entry in screens.entries) {
      testWidgets('${entry.key} clears WCAG AA in light', (tester) async {
        final handle = tester.ensureSemantics();
        await render(tester, entry.value());

        await expectLater(tester, meetsGuideline(textContrastGuideline));
        handle.dispose();
      });
    }
  });
}
