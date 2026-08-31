import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import 'package:atomid/core/services/export_service.dart';
import 'package:atomid/core/utils/formatters.dart';
import 'package:atomid/data/models/purchase_model.dart';
import 'package:atomid/data/models/sale_model.dart';
import 'package:atomid/domain/date_window.dart';
import 'package:atomid/domain/document_totals.dart';
import 'package:atomid/presentation/providers/app_providers.dart';

class ReportsDashboardScreen extends ConsumerStatefulWidget {
  const ReportsDashboardScreen({super.key});

  @override
  ConsumerState<ReportsDashboardScreen> createState() =>
      _ReportsDashboardScreenState();
}

class _ReportsDashboardScreenState extends ConsumerState<ReportsDashboardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _selectedTimeframe = 'Today';
  final List<String> _timeframes = [
    'Today',
    'This Week',
    'This Month',
    'All Time',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  List<Sale> _getFilteredSales(List<Sale> allSales) {
    final window = DateWindow.forTimeframe(_selectedTimeframe, DateTime.now());
    if (window == null) return allSales;
    return allSales.where((s) => window.contains(s.date)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final allSales = ref.watch(salesProvider);
    final filteredSales = _getFilteredSales(allSales);
    final symbol = ref.watch(currencySymbolProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports & GST Returns'),
        actions: [
          IconButton(
            icon: const Icon(Icons.print),
            tooltip: 'Export Report to PDF',
            onPressed: () async {
              final settings = ref.read(settingsProvider);
              final company = ref.read(companyProvider);
              final pdf = await ExportService.generateSalesReportPdf(
                filteredSales,
                _selectedTimeframe,
                settings,
                company,
              );
              await Printing.layoutPdf(
                onLayout: (PdfPageFormat format) async => pdf.save(),
                name: 'Sales_GST_Report_$_selectedTimeframe',
              );
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Overview'),
            Tab(text: 'Sales GST (GSTR-1)'),
            Tab(text: 'HSN Summary'),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: SingleChildScrollView(
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
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildOverviewTab(filteredSales, symbol),
                _buildSalesGstTab(filteredSales, symbol),
                _buildHsnSummaryTab(filteredSales, symbol),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewTab(List<Sale> sales, String symbol) {
    final revenue = DocumentTotals.salesRevenue(sales);
    final itemsSold = DocumentTotals.salesUnits(sales);
    final invoiceCount = sales.length;
    final totalGst = DocumentTotals.salesTotalGst(sales);

    final Map<String, int> productSales = {};
    for (var sale in sales) {
      for (var item in sale.items) {
        final key = '${item.productName} (${item.variantSize})';
        productSales[key] = (productSales[key] ?? 0) + item.quantity;
      }
    }
    final topSellers = productSales.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GridView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              mainAxisExtent: 120,
            ),
            children: [
              _buildMetricCard(
                'Total Revenue',
                Fmt.moneyCompact(revenue, symbol),
                Icons.payments,
                Colors.green,
              ),
              _buildMetricCard(
                'Total GST Collected',
                Fmt.moneyCompact(totalGst, symbol),
                Icons.account_balance,
                Colors.indigo,
              ),
              _buildMetricCard(
                'Dresses Sold',
                '$itemsSold',
                Icons.shopping_bag,
                Colors.blue,
              ),
              _buildMetricCard(
                'Invoices Issued',
                '$invoiceCount',
                Icons.receipt,
                Colors.orange,
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Text(
            'Top Selling Garments',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          if (topSellers.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(24.0),
                child: Center(
                  child: Text('No sales recorded in this timeframe.'),
                ),
              ),
            )
          else
            ...topSellers
                .take(5)
                .map(
                  (e) => Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: const Icon(Icons.checkroom),
                      title: Text(
                        e.key,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      trailing: Text(
                        '${e.value} pcs',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ),
        ],
      ),
    );
  }

  Widget _buildSalesGstTab(List<Sale> sales, String symbol) {
    final taxable = DocumentTotals.salesTaxable(sales);
    final cgst = DocumentTotals.salesCgst(sales);
    final sgst = DocumentTotals.salesSgst(sales);
    final utgst = DocumentTotals.salesUtgst(sales);
    final igst = DocumentTotals.salesIgst(sales);
    final cess = DocumentTotals.salesCess(sales);
    final totalTax = DocumentTotals.salesTotalGst(sales);
    final revenue = DocumentTotals.salesRevenue(sales);

    // Rate-wise aggregation
    final rateMap = <double, _RateAggregate>{};
    for (final sale in sales) {
      for (final item in sale.items) {
        final rate = item.gstRate ?? 0.0;
        final agg = rateMap.putIfAbsent(rate, () => _RateAggregate(rate: rate));
        agg.taxable += item.taxableValue;
        agg.cgst += item.cgstAmount;
        agg.sgst += item.sgstAmount;
        agg.utgst += item.utgstAmount;
        agg.igst += item.igstAmount;
        agg.cess += item.cessAmount;
        agg.totalTax +=
            (item.cgstAmount +
            item.sgstAmount +
            item.utgstAmount +
            item.igstAmount +
            item.cessAmount);
      }
    }

    final sortedRates = rateMap.values.toList()
      ..sort((a, b) => a.rate.compareTo(b.rate));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            color: Colors.blue.shade50,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Expanded(
                        child: Text(
                          'GSTR-1 Tax Summary',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Flexible too, not just the title: a Row overflows if
                      // any child insists on its natural width, and this one
                      // grows with the text scale the shop has set.
                      Flexible(
                        child: Text(
                          '${sales.length} Invoices',
                          textAlign: TextAlign.end,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.blue.shade900,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 20),
                  _tableRow(
                    'Gross Turnover',
                    Fmt.money(revenue, symbol),
                    isBold: true,
                  ),
                  _tableRow(
                    'Net Taxable Turnover',
                    Fmt.money(taxable, symbol),
                    isBold: true,
                  ),
                  const SizedBox(height: 8),
                  _tableRow('Central GST (CGST)', Fmt.money(cgst, symbol)),
                  _tableRow('State GST (SGST)', Fmt.money(sgst, symbol)),
                  if (utgst > 0)
                    _tableRow(
                      'Union Territory GST (UTGST)',
                      Fmt.money(utgst, symbol),
                    ),
                  _tableRow('Integrated GST (IGST)', Fmt.money(igst, symbol)),
                  if (cess > 0)
                    _tableRow('Compensation Cess', Fmt.money(cess, symbol)),
                  const Divider(height: 20),
                  _tableRow(
                    'Total Output GST Collected',
                    Fmt.money(totalTax, symbol),
                    isBold: true,
                    color: Colors.indigo.shade900,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Rate-Wise GST Breakdown',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          if (sortedRates.isEmpty)
            const Center(child: Text('No rate-wise transactions recorded.'))
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('GST Rate')),
                  DataColumn(label: Text('Taxable Value')),
                  DataColumn(label: Text('CGST')),
                  DataColumn(label: Text('SGST/UTGST')),
                  DataColumn(label: Text('IGST')),
                  DataColumn(label: Text('Total Tax')),
                ],
                rows: sortedRates.map((r) {
                  return DataRow(
                    cells: [
                      DataCell(Text('${Fmt.amount(r.rate)}%')),
                      DataCell(Text(Fmt.money(r.taxable, symbol))),
                      DataCell(Text(Fmt.money(r.cgst, symbol))),
                      DataCell(Text(Fmt.money(r.sgst + r.utgst, symbol))),
                      DataCell(Text(Fmt.money(r.igst, symbol))),
                      DataCell(Text(Fmt.money(r.totalTax, symbol))),
                    ],
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHsnSummaryTab(List<Sale> sales, String symbol) {
    final hsnMap = <String, _HsnAggregate>{};

    for (final sale in sales) {
      for (final item in sale.items) {
        final key = '${item.hsn}_${item.uqc}';
        final agg = hsnMap.putIfAbsent(
          key,
          () => _HsnAggregate(
            hsn: item.hsn.isNotEmpty ? item.hsn : 'Unspecified',
            uqc: item.uqc.isNotEmpty ? item.uqc : 'PCS',
            description: item.productName,
          ),
        );
        agg.qty += item.quantity;
        agg.totalValue += item.total;
        agg.taxableValue += item.taxableValue;
        agg.cgst += item.cgstAmount;
        agg.sgst += item.sgstAmount;
        agg.utgst += item.utgstAmount;
        agg.igst += item.igstAmount;
        agg.cess += item.cessAmount;
      }
    }

    final hsnList = hsnMap.values.toList()
      ..sort((a, b) => a.hsn.compareTo(b.hsn));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'HSN / SAC Summary Table',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Statutory HSN table required for annual returns and tax audits.',
            style: TextStyle(color: Colors.grey, fontSize: 13),
          ),
          const SizedBox(height: 16),
          if (hsnList.isEmpty)
            const Center(child: Text('No HSN transactions in this timeframe.'))
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('HSN')),
                  DataColumn(label: Text('UQC')),
                  DataColumn(label: Text('Total Qty')),
                  DataColumn(label: Text('Total Value')),
                  DataColumn(label: Text('Taxable Value')),
                  DataColumn(label: Text('CGST')),
                  DataColumn(label: Text('SGST')),
                  DataColumn(label: Text('IGST')),
                  DataColumn(label: Text('Cess')),
                ],
                rows: hsnList.map((h) {
                  return DataRow(
                    cells: [
                      DataCell(Text(h.hsn)),
                      DataCell(Text(h.uqc)),
                      DataCell(Text('${h.qty}')),
                      DataCell(Text(Fmt.money(h.totalValue, symbol))),
                      DataCell(Text(Fmt.money(h.taxableValue, symbol))),
                      DataCell(Text(Fmt.money(h.cgst, symbol))),
                      DataCell(Text(Fmt.money(h.sgst + h.utgst, symbol))),
                      DataCell(Text(Fmt.money(h.igst, symbol))),
                      DataCell(Text(Fmt.money(h.cess, symbol))),
                    ],
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _tableRow(
    String label,
    String value, {
    bool isBold = false,
    Color? color,
  }) {
    // Both children used to claim their natural width, so a long label beside
    // a six-figure amount overflowed the row on a phone. The label yields
    // first; the amount only shrinks once there is nothing left to give.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
                color: color,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                value,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
                  color: color,
                ),
              ),
            ),
          ),
        ],
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
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                maxLines: 1,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RateAggregate {
  final double rate;
  double taxable = 0.0;
  double cgst = 0.0;
  double sgst = 0.0;
  double utgst = 0.0;
  double igst = 0.0;
  double cess = 0.0;
  double totalTax = 0.0;

  _RateAggregate({required this.rate});
}

class _HsnAggregate {
  final String hsn;
  final String uqc;
  final String description;
  int qty = 0;
  double totalValue = 0.0;
  double taxableValue = 0.0;
  double cgst = 0.0;
  double sgst = 0.0;
  double utgst = 0.0;
  double igst = 0.0;
  double cess = 0.0;

  _HsnAggregate({
    required this.hsn,
    required this.uqc,
    required this.description,
  });
}
