import 'package:flutter/material.dart';
import 'package:atomid/core/theme/brand.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:atomid/data/models/product_model.dart';
import 'package:atomid/presentation/providers/app_providers.dart';
import 'package:atomid/presentation/features/inventory/stock_in_screen.dart';
import 'package:atomid/presentation/features/inventory/stock_out_screen.dart';
import 'package:atomid/presentation/features/inventory/inventory_movement_screen.dart';
import 'package:atomid/core/services/export_service.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:atomid/core/utils/responsive.dart';

class InventoryDashboardScreen extends ConsumerWidget {
  const InventoryDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final products = ref.watch(productsProvider);
    final totalStock = ref.watch(totalStockUnitsProvider);
    final lowStockItems = ref.watch(lowStockItemsProvider);
    final outOfStockItems = ref.watch(outOfStockItemsProvider);
    final company = ref.watch(companyProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventory'),
        actions: [
          IconButton(
            icon: const Icon(Icons.print),
            tooltip: 'Export Inventory Report',
            onPressed: () async {
              final settings = ref.read(settingsProvider);
              final pdf = await ExportService.generateInventoryReportPdf(
                products,
                settings,
                company,
              );
              await Printing.layoutPdf(
                onLayout: (PdfPageFormat format) async => pdf.save(),
                name: 'Inventory_Report',
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: ResponsivePadding.getScreenPadding(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- Stat Cards ---
            _buildStatGrid(
              context,
              products,
              totalStock,
              lowStockItems,
              outOfStockItems,
            ),
            const SizedBox(height: 24),

            // --- Quick Actions ---
            const Text(
              'Quick Actions',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildActionButton(
                    context,
                    'Stock In',
                    Icons.add_box_outlined,
                    context.successColor,
                    () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const StockInScreen()),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildActionButton(
                    context,
                    'Stock Out',
                    Icons.outbox_outlined,
                    context.dangerColor,
                    () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const StockOutScreen()),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildActionButton(
                    context,
                    'History',
                    Icons.history,
                    Theme.of(context).colorScheme.primary,
                    () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const InventoryMovementScreen(),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // --- Low Stock Alerts ---
            if (lowStockItems.isNotEmpty) ...[
              Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: context.warningColor,
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Low Stock Alerts (${lowStockItems.length})',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: context.warningColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: lowStockItems.length,
                itemBuilder: (context, index) {
                  final item = lowStockItems[index];
                  final product = item['product'] as Product;
                  final variant = item['variant'] as ProductVariant;
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.orange.withAlpha(40),
                        child: Icon(
                          Icons.warning_amber_rounded,
                          color: context.warningColor,
                        ),
                      ),
                      title: Text(
                        '${product.displayName} - ${variant.size}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        'Qty: ${variant.quantity} | Reorder Level: ${variant.reorderLevel}',
                      ),
                      trailing: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: context.successColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => StockInScreen(
                                preselectedProduct: product,
                                preselectedVariant: variant,
                              ),
                            ),
                          );
                        },
                        child: const Text('Stock In'),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
            ],

            // --- Out Of Stock ---
            if (outOfStockItems.isNotEmpty) ...[
              Row(
                children: [
                  Icon(
                    Icons.error_outline,
                    color: context.dangerColor,
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Out of Stock (${outOfStockItems.length})',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: context.dangerColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: outOfStockItems.length,
                itemBuilder: (context, index) {
                  final item = outOfStockItems[index];
                  final product = item['product'] as Product;
                  final variant = item['variant'] as ProductVariant;
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.red.withAlpha(40),
                        child: Icon(
                          Icons.error_outline,
                          color: context.dangerColor,
                        ),
                      ),
                      title: Text(
                        '${product.displayName} - ${variant.size}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text('Barcode: ${variant.barcode}'),
                      trailing: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: context.successColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => StockInScreen(
                                preselectedProduct: product,
                                preselectedVariant: variant,
                              ),
                            ),
                          );
                        },
                        child: const Text('Stock In'),
                      ),
                    ),
                  );
                },
              ),
            ],

            if (lowStockItems.isEmpty && outOfStockItems.isEmpty)
              Center(
                child: Padding(
                  padding: EdgeInsets.all(32.0),
                  child: Column(
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        size: 64,
                        color: context.successColor,
                      ),
                      SizedBox(height: 16),
                      Text(
                        'All stock levels are healthy!',
                        style: TextStyle(fontSize: 16),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(
    BuildContext context,
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 28, color: color),
              const SizedBox(height: 8),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton(
    BuildContext context,
    String title,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: color.withAlpha(30),
        foregroundColor: color,
        elevation: 0,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      icon: Icon(icon),
      label: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      onPressed: onTap,
    );
  }

  Widget _buildStatGrid(
    BuildContext context,
    List<Product> products,
    int totalStock,
    List<Map<String, dynamic>> lowStockItems,
    List<Map<String, dynamic>> outOfStockItems,
  ) {
    final isMobile = ResponsiveHelper.isMobile(context);
    final isDesktop = ResponsiveHelper.isDesktop(context);

    final children = [
      _buildStatCard(
        context,
        'Products',
        products.length.toString(),
        Icons.inventory_2,
        Theme.of(context).colorScheme.primary,
      ),
      _buildStatCard(
        context,
        'Total Stock',
        totalStock.toString(),
        Icons.all_inbox,
        Colors.teal,
      ),
      _buildStatCard(
        context,
        'Low Stock',
        lowStockItems.length.toString(),
        Icons.warning_amber_rounded,
        context.warningColor,
      ),
      _buildStatCard(
        context,
        'Out of Stock',
        outOfStockItems.length.toString(),
        Icons.error_outline,
        context.dangerColor,
      ),
    ];

    return GridView.builder(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: isMobile ? 2 : (isDesktop ? 4 : 2),
        crossAxisSpacing: isMobile ? 10 : 16,
        mainAxisSpacing: isMobile ? 10 : 16,
        childAspectRatio: isMobile ? 1.6 : 1.8,
      ),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: children.length,
      itemBuilder: (context, index) => children[index],
    );
  }
}
