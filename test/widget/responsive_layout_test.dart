import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:atomid/presentation/features/auth/auth_screen.dart';
import 'package:atomid/presentation/features/billing/checkout_screen.dart';
import 'package:atomid/presentation/features/customers/customer_list_screen.dart';
import 'package:atomid/presentation/features/dashboard/dashboard_screen.dart';
import 'package:atomid/presentation/features/expenses/expense_list_screen.dart';
import 'package:atomid/presentation/features/inventory/inventory_dashboard_screen.dart';
import 'package:atomid/presentation/features/products/product_list_screen.dart';
import 'package:atomid/presentation/features/purchases/purchase_list_screen.dart';
import 'package:atomid/presentation/features/reports/reports_dashboard_screen.dart';
import 'package:atomid/presentation/features/suppliers/supplier_list_screen.dart';
import 'package:atomid/presentation/features/system/system_console_screen.dart';

import '../support/screen_harness.dart';

/// Renders every reachable screen across the supported width range.
///
/// A till runs on whatever hardware the shop already owns, so a layout that
/// only holds together at one width is a real defect rather than a cosmetic
/// one. Overflow is raised by the framework during layout, so this catches
/// breakage that no assertion on a single size would.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ScreenHarness harness;

  // One store for the whole file. These renders never mutate it, and opening
  // twenty-one Hive boxes per case made the sweep too slow to finish.
  setUpAll(() async {
    harness = await ScreenHarness.open();
    // Enough data that lists, totals and empty states all have something to
    // lay out — an empty store hides most overflow.
    final product = await harness.store.addProduct(
      name: 'Long Product Name For Layout Pressure',
      price: 1499.99,
      quantity: 42,
    );
    await harness.store.addCustomer(name: 'Priyadharshini Venkataraman');
    await harness.store.addSupplier(name: 'Acme Textiles And Weaving Company');
    expect(product.variants, isNotEmpty);
  });

  tearDownAll(() => harness.close());

  final screens = <String, Widget Function()>{
    'Dashboard': () => const DashboardScreen(),
    'Products': () => const ProductListScreen(),
    'Inventory': () => const InventoryDashboardScreen(),
    'Customers': () => const CustomerListScreen(),
    'Suppliers': () => const SupplierListScreen(),
    'Purchases': () => const PurchaseListScreen(),
    'Expenses': () => const ExpenseListScreen(),
    'Reports': () => const ReportsDashboardScreen(),
    'Checkout': () => const CheckoutScreen(),
    'System': () => const SystemConsoleScreen(),
    'Auth': () => const AuthScreen(),
  };

  for (final entry in screens.entries) {
    group('${entry.key} layout', () {
      for (final viewport in responsiveMatrix) {
        testWidgets('renders at $viewport', (tester) async {
          final error = await renderAt(
            tester,
            harness,
            entry.value(),
            viewport,
          );

          expect(
            error,
            isNull,
            reason:
                '${entry.key} does not lay out at $viewport:\n$error',
          );
        });
      }
    });
  }
}
