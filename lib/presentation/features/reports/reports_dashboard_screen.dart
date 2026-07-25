import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:atomid/presentation/providers/app_providers.dart';
import 'package:atomid/data/models/sale_model.dart';
import 'package:atomid/core/services/export_service.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';

class ReportsDashboardScreen extends ConsumerStatefulWidget {
  const ReportsDashboardScreen({super.key});

  @override
  ConsumerState<ReportsDashboardScreen> createState() =>
      _ReportsDashboardScreenState();
}

class _ReportsDashboardScreenState
    extends ConsumerState<ReportsDashboardScreen> {
  String _selectedTimeframe = 'Today';
  final List<String> _timeframes = [
    'Today',
    'This Week',
    'This Month',
    'All Time',
  ];

  List<Sale> _getFilteredSales(List<Sale> allSales) {
    final now = DateTime.now();
    return allSales.where((sale) {
      switch (_selectedTimeframe) {
        case 'Today':
          return sale.date.year == now.year &&
              sale.date.month == now.month &&
              sale.date.day == now.day;
        case 'This Week':
          final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
          return sale.date.isAfter(
            startOfWeek.subtract(const Duration(days: 1)),
          );
        case 'This Month':
          return sale.date.year == now.year && sale.date.month == now.month;
        case 'All Time':
        default:
          return true;
      }
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final allSales = ref.watch(salesProvider);
    final filteredSales = _getFilteredSales(allSales);

    // Calculate metrics
    final double revenue = filteredSales.fold(
      0,
      (sum, s) => sum + s.grandTotal,
    );
    final int itemsSold = filteredSales.fold(
      0,
      (sum, s) => sum + s.items.fold(0, (iSum, item) => iSum + item.quantity),
    );
    final int invoiceCount = filteredSales.length;

    // Top Selling Calculation
    final Map<String, int> productSales = {};
    for (var sale in filteredSales) {
      for (var item in sale.items) {
        final key = '${item.productName} (${item.variantSize})';
        productSales[key] = (productSales[key] ?? 0) + item.quantity;
      }
    }
    final sortedTopSellers = productSales.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topSellers = sortedTopSellers.take(5).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports & Analytics'),
        actions: [
          IconButton(
            icon: const Icon(Icons.print),
            tooltip: 'Export Sales Report',
            onPressed: () async {
              final settings = ref.read(settingsProvider);
              final company = ref.watch(companyProvider);
              final pdf = await ExportService.generateSalesReportPdf(
                filteredSales,
                _selectedTimeframe,
                settings,
                company,
              );
              await Printing.layoutPdf(
                onLayout: (PdfPageFormat format) async => pdf.save(),
                name: 'Sales_Report_$_selectedTimeframe',
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Timeframe Selector
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _timeframes.map((tf) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: ChoiceChip(
                      label: Text(tf),
                      selected: _selectedTimeframe == tf,
                      onSelected: (selected) {
                        if (selected) setState(() => _selectedTimeframe = tf);
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 24),

            // Metrics Grid
            const Text(
              'Sales Overview',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 1.3,
              children: [
                _buildMetricCard(
                  'Revenue',
                  '₹${revenue.toStringAsFixed(0)}',
                  Icons.payments,
                  Colors.green,
                ),
                _buildMetricCard(
                  'Items Sold',
                  '$itemsSold',
                  Icons.shopping_bag,
                  Colors.blue,
                ),
                _buildMetricCard(
                  'Invoices',
                  '$invoiceCount',
                  Icons.receipt,
                  Colors.orange,
                ),
                _buildMetricCard(
                  'Avg Sale',
                  invoiceCount > 0
                      ? '₹${(revenue / invoiceCount).toStringAsFixed(0)}'
                      : '₹0',
                  Icons.analytics,
                  Colors.purple,
                ),
              ],
            ),
            const SizedBox(height: 32),

            // Top Selling Products
            const Text(
              'Top Selling Items',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            topSellers.isEmpty
                ? const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Center(
                        child: Text('No sales data for this period.'),
                      ),
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: topSellers.length,
                    itemBuilder: (context, index) {
                      final item = topSellers[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Theme.of(
                              context,
                            ).colorScheme.primary.withAlpha(40),
                            child: Text(
                              '#${index + 1}',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          title: Text(
                            item.key,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          trailing: Text(
                            '${item.value} sold',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
