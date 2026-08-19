import 'package:flutter/material.dart';
import 'package:atomid/core/utils/formatters.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:atomid/data/models/product_model.dart';
import 'package:atomid/presentation/providers/app_providers.dart';
import 'package:atomid/core/services/export_service.dart';
import 'package:atomid/data/models/action_history_model.dart';
import 'package:uuid/uuid.dart';
import 'package:barcode_widget/barcode_widget.dart';
import 'package:printing/printing.dart';

class PriceTagScreen extends ConsumerStatefulWidget {
  final Product product;
  final ProductVariant initialVariant;

  const PriceTagScreen({
    super.key,
    required this.product,
    required this.initialVariant,
  });

  @override
  ConsumerState<PriceTagScreen> createState() => _PriceTagScreenState();
}

class _PriceTagScreenState extends ConsumerState<PriceTagScreen> {
  late ProductVariant _selectedVariant;
  bool _showQuantity = false;

  @override
  void initState() {
    super.initState();
    _selectedVariant = widget.initialVariant;
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Price Tag Preview')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                const Text('Show Quantity'),
                Switch(
                  value: _showQuantity,
                  onChanged: (val) => setState(() => _showQuantity = val),
                ),
              ],
            ),
            _buildPremiumTag(
              context,
              settings.companyName,
              settings.currencySymbol,
            ),
            const SizedBox(height: 32),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              alignment: WrapAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: () => _exportPng(settings.companyName),
                  icon: const Icon(Icons.image),
                  label: const Text('Save Image'),
                ),
                ElevatedButton.icon(
                  onPressed: () => _exportPdf(settings.companyName),
                  icon: const Icon(Icons.picture_as_pdf),
                  label: const Text('Export PDF'),
                ),
                ElevatedButton.icon(
                  onPressed: () => _shareTag(settings.companyName),
                  icon: const Icon(Icons.share),
                  label: const Text('Share'),
                ),
                ElevatedButton.icon(
                  onPressed: () => _printTag(settings.companyName),
                  icon: const Icon(Icons.print),
                  label: const Text('Print'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPremiumTag(
    BuildContext context,
    String companyName,
    String currencySymbol,
  ) {
    final sizes = widget.product.variants.map((v) => v.size).toList();

    return Center(
      child: Container(
        width: 280,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade300, width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(10),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Image.asset(
              'assets/images/logo.png',
              width: 120,
              height: 60,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) =>
                  const Icon(Icons.store, color: Colors.black, size: 48),
            ),
            const SizedBox(height: 8),
            const Divider(color: Colors.black12, height: 24, thickness: 1),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.product.productName,
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.product.productCode,
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Color: ${widget.product.color}',
                        style: const TextStyle(
                          color: Colors.black87,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Brand: ${widget.product.brand}',
                        style: const TextStyle(
                          color: Colors.black87,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  children: sizes.map((s) {
                    final isSelected = s == _selectedVariant.size;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2.0),
                      child: Row(
                        children: [
                          Text(
                            s,
                            style: TextStyle(
                              color: isSelected
                                  ? Colors.black
                                  : Colors.grey.shade500,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              fontSize: 16,
                            ),
                          ),
                          if (isSelected) const SizedBox(width: 4),
                          if (isSelected)
                            const Icon(
                              Icons.check,
                              size: 16,
                              color: Colors.black,
                            ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(8),
              color: Colors.white,
              child: BarcodeWidget(
                barcode: Barcode.code128(),
                data: _selectedVariant.barcode,
                width: 200,
                height: 60,
                drawText: true,
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 12,
                  letterSpacing: 2,
                ),
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'MRP',
                      style: TextStyle(color: Colors.black54, fontSize: 12),
                    ),
                    Text(
                      Fmt.money(_selectedVariant.price, currencySymbol),
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Text(
                      'Incl. all taxes',
                      style: TextStyle(color: Colors.black54, fontSize: 10),
                    ),
                  ],
                ),
                if (_showQuantity)
                  Text(
                    'Qty: ${_selectedVariant.quantity}',
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _getFileName() {
    final now = DateTime.now();
    final dateStr =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    return 'ATOMID_${widget.product.productCode}_${_selectedVariant.size}_$dateStr'
        .toUpperCase();
  }

  Future<void> _logAction(String action) async {
    final repo = ref.read(storageRepositoryProvider);
    await repo.saveHistory(
      ActionHistory(
        id: const Uuid().v4(),
        barcode: _selectedVariant.barcode,
        productName: widget.product.productName,
        action: action,
        date: DateTime.now(),
      ),
    );
    ref.invalidate(historyListProvider);
  }

  Future<void> _exportPng(String companyName) async {
    try {
      final settings = ref.read(settingsProvider);
      // read, not watch: a callback must not subscribe the widget that
      // happened to be building when it was created.
      final company = ref.read(companyProvider);
      final pdf = await ExportService.generateSingleTagPdf(
        widget.product,
        _selectedVariant,
        settings,
        company,
      );
      final file = await ExportService.exportPng(pdf, _getFileName());
      await _logAction('PNG Generated');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Saved to ${file.path}')));
      }
    } catch (e) {
      debugPrint('Export PNG error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to export image. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _exportPdf(String companyName) async {
    try {
      final settings = ref.read(settingsProvider);
      // read, not watch: a callback must not subscribe the widget that
      // happened to be building when it was created.
      final company = ref.read(companyProvider);
      final pdf = await ExportService.generateSingleTagPdf(
        widget.product,
        _selectedVariant,
        settings,
        company,
      );
      final file = await ExportService.exportPdf(pdf, _getFileName());
      await _logAction('PDF Generated');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Saved to ${file.path}')));
      }
    } catch (e) {
      debugPrint('Export PDF error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to generate PDF. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _shareTag(String companyName) async {
    try {
      final settings = ref.read(settingsProvider);
      // read, not watch: a callback must not subscribe the widget that
      // happened to be building when it was created.
      final company = ref.read(companyProvider);
      final pdf = await ExportService.generateSingleTagPdf(
        widget.product,
        _selectedVariant,
        settings,
        company,
      );
      final file = await ExportService.exportPng(pdf, _getFileName());
      await ExportService.shareFile(
        file,
        'Price Tag for ${widget.product.productName} Size ${_selectedVariant.size}',
      );
      await _logAction('Tag Shared');
    } catch (e) {
      debugPrint('Share tag error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to share tag. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _printTag(String companyName) async {
    try {
      final settings = ref.read(settingsProvider);
      // read, not watch: a callback must not subscribe the widget that
      // happened to be building when it was created.
      final company = ref.read(companyProvider);
      final pdf = await ExportService.generateSingleTagPdf(
        widget.product,
        _selectedVariant,
        settings,
        company,
      );
      await Printing.layoutPdf(onLayout: (format) async => pdf.save());
      await _logAction('Tag Printed');
    } catch (e) {
      debugPrint('Print tag error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to print tag. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
