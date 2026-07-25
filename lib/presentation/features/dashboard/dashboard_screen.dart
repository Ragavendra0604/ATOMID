import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:atomid/data/models/product_model.dart';
import 'package:atomid/presentation/providers/app_providers.dart';
import 'package:atomid/presentation/features/products/product_list_screen.dart';
import 'package:atomid/presentation/features/scanner/barcode_scanner_screen.dart';
import 'package:atomid/presentation/features/price_tag/bulk_generator_screen.dart';
import 'package:atomid/presentation/features/history/history_screen.dart';
import 'package:atomid/presentation/features/inventory/inventory_dashboard_screen.dart';
import 'package:atomid/presentation/features/billing/pos_screen.dart';
import 'package:atomid/presentation/features/billing/sales_history_screen.dart';
import 'package:atomid/presentation/features/reports/reports_dashboard_screen.dart';
import 'package:atomid/presentation/features/suppliers/supplier_list_screen.dart';
import 'package:atomid/presentation/features/purchases/purchase_list_screen.dart';
import 'package:atomid/presentation/features/customers/customer_list_screen.dart';
import 'package:atomid/presentation/features/expenses/expense_list_screen.dart';
import 'package:atomid/presentation/features/sync/sync_status_widget.dart';
import 'package:atomid/presentation/features/admin/admin_dashboard_screen.dart';
import 'package:atomid/core/services/rbac_service.dart';
import 'package:atomid/core/utils/responsive.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final products = ref.watch(productsProvider);
    final history = ref.watch(historyListProvider);
    final totalStock = ref.watch(totalStockUnitsProvider);
    final lowStockItems = ref.watch(lowStockItemsProvider);
    final todayRevenue = ref.watch(todayRevenueProvider);
    final settings = ref.watch(settingsProvider);
    final suppliers = ref.watch(suppliersProvider);
    final todayPurchases = ref.watch(todayPurchasesProvider);
    final valuation = ref.watch(inventoryValuationProvider);

    int todayScans = history
        .where((h) => h.action == 'Scanned' && h.date.day == DateTime.now().day)
        .length;

    final isMobile = ResponsiveHelper.isMobile(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: const [SyncStatusWidget()],
      ),
      body: SingleChildScrollView(
        padding: ResponsivePadding.getScreenPadding(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Overview',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _buildStatGrid(
              context,
              isMobile,
              products,
              totalStock,
              lowStockItems,
              todayRevenue,
              todayScans,
              suppliers,
              todayPurchases,
              valuation,
              settings,
            ),

            const SizedBox(height: 24),
            const Text(
              'Quick Actions',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _buildActionGrid(context, isMobile, ref),

            // --- Low Stock Warning ---
            if (lowStockItems.isNotEmpty) ...[
              const SizedBox(height: 24),
              Row(
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.orange,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Low Stock (${lowStockItems.length})',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.orange,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 80,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: lowStockItems.length,
                  itemBuilder: (context, index) {
                    final item = lowStockItems[index];
                    final product = item['product'] as Product;
                    final variant = item['variant'] as ProductVariant;
                    return Card(
                      margin: const EdgeInsets.only(right: 8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              '${product.productName} (${variant.size})',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            Text(
                              'Qty: ${variant.quantity}',
                              style: const TextStyle(
                                color: Colors.orange,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
            const SizedBox(height: 24),
            const Text(
              'Recent Products',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            products.isEmpty
                ? const Center(child: Text('No products found.'))
                : ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: products.length > 5 ? 5 : products.length,
                    itemBuilder: (context, index) {
                      final product = products[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          title: Text(product.productName),
                          subtitle: Text(product.productCode),
                          trailing: Text('${product.variants.length} Variants'),
                        ),
                      );
                    },
                  ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatGrid(
    BuildContext context,
    bool isMobile,
    List<Product> products,
    int totalStock,
    List<Map<String, dynamic>> lowStockItems,
    double todayRevenue,
    int todayScans,
    List<dynamic> suppliers,
    List<dynamic> todayPurchases,
    Map<String, double> valuation,
    dynamic settings,
  ) {
    final children = [
      _buildStatCard(
        context,
        'Products',
        products.length.toString(),
        Icons.inventory,
      ),
      _buildStatCard(
        context,
        'Inventory',
        totalStock.toString(),
        Icons.all_inbox,
      ),
      _buildStatCard(
        context,
        'Low Stock',
        lowStockItems.length.toString(),
        Icons.warning_amber_rounded,
      ),
      _buildStatCard(
        context,
        'Revenue',
        '${settings.currencySymbol}${todayRevenue.toStringAsFixed(0)}',
        Icons.payments,
      ),
      _buildStatCard(
        context,
        'Scans',
        todayScans.toString(),
        Icons.document_scanner,
      ),
      _buildStatCard(
        context,
        'Suppliers',
        suppliers.length.toString(),
        Icons.business,
      ),
      _buildStatCard(
        context,
        'Purchases',
        todayPurchases.length.toString(),
        Icons.shopping_cart,
      ),
      _buildStatCard(
        context,
        'Value',
        '${settings.currencySymbol}${valuation['retailValue']?.toStringAsFixed(0) ?? '0'}',
        Icons.account_balance_wallet,
      ),
    ];

    if (isMobile) {
      // Mobile: 2 columns, compact cards
      return GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 1.6,
        ),
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: children.length,
        itemBuilder: (context, index) => children[index],
      );
    }

    // Tablet/Desktop
    final isDesktop = ResponsiveHelper.isDesktop(context);
    return GridView.builder(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: isDesktop ? 4 : 3,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 1.8,
      ),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: children.length,
      itemBuilder: (context, index) => children[index],
    );
  }

  Widget _buildActionGrid(BuildContext context, bool isMobile, WidgetRef ref) {
    final currentEmployee = ref.watch(currentEmployeeProvider);
    final isOwner =
        currentEmployee != null && RbacService.isOwner(currentEmployee);

    final actions = [
      if (isOwner)
        _buildActionCard(
          context,
          'Admin Panel',
          Icons.admin_panel_settings,
          () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AdminDashboardScreen()),
            );
          },
        ),
      _buildActionCard(context, 'POS Billing', Icons.point_of_sale, () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const PosScreen()),
        );
      }),
      _buildActionCard(context, 'Sales', Icons.receipt_long, () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SalesHistoryScreen()),
        );
      }),
      _buildActionCard(context, 'Customers', Icons.people, () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CustomerListScreen()),
        );
      }),
      _buildActionCard(context, 'Products', Icons.inventory_2, () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ProductListScreen()),
        );
      }),
      _buildActionCard(context, 'Inventory', Icons.storefront, () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const InventoryDashboardScreen()),
        );
      }),
      _buildActionCard(context, 'Scanner', Icons.qr_code_scanner, () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()),
        );
      }),
      _buildActionCard(context, 'Price Tags', Icons.sell, () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const BulkGeneratorScreen()),
        );
      }),
      _buildActionCard(context, 'Reports', Icons.bar_chart, () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ReportsDashboardScreen()),
        );
      }),
      _buildActionCard(context, 'History', Icons.history, () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const HistoryScreen()),
        );
      }),
      _buildActionCard(context, 'Suppliers', Icons.business, () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SupplierListScreen()),
        );
      }),
      _buildActionCard(context, 'Purchases', Icons.shopping_cart, () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const PurchaseListScreen()),
        );
      }),
      _buildActionCard(context, 'Expenses', Icons.receipt_long, () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ExpenseListScreen()),
        );
      }),
    ];

    if (isMobile) {
      // Mobile: horizontal scrollable row of action chips
      return SizedBox(
        height: 90,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: actions.length,
          separatorBuilder: (_, _) => const SizedBox(width: 10),
          itemBuilder: (context, index) =>
              SizedBox(width: 80, child: actions[index]),
        ),
      );
    }

    // Tablet/Desktop: grid
    final isDesktop = ResponsiveHelper.isDesktop(context);
    return GridView.builder(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: isDesktop ? 6 : 4,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.0,
      ),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: actions.length,
      itemBuilder: (context, index) => actions[index],
    );
  }

  Widget _buildStatCard(
    BuildContext context,
    String title,
    String value,
    IconData icon,
  ) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 22, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 1,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionCard(
    BuildContext context,
    String title,
    IconData icon,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Card(
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 28,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 6),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
