import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:atomid/presentation/providers/app_providers.dart';
import 'package:atomid/data/models/product_model.dart';
import 'package:atomid/core/services/export_service.dart';
import 'package:atomid/domain/price_tag_size.dart';
import 'package:printing/printing.dart';
import 'package:atomid/core/utils/responsive.dart';
import 'dart:typed_data';

class BulkGeneratorScreen extends ConsumerStatefulWidget {
  const BulkGeneratorScreen({super.key});

  @override
  ConsumerState<BulkGeneratorScreen> createState() =>
      _BulkGeneratorScreenState();
}

class _BulkGeneratorScreenState extends ConsumerState<BulkGeneratorScreen> {
  Product? _selectedProduct;
  final Map<ProductVariant, TextEditingController> _qtyControllers = {};
  bool _isLoading = false;
  PriceTagSize _tagSize = PriceTagSize.medium;

  @override
  void dispose() {
    for (var ctrl in _qtyControllers.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  void _onProductSelected(Product product) {
    setState(() {
      _selectedProduct = product;
      _qtyControllers.clear();
      for (var v in product.variants) {
        _qtyControllers[v] = TextEditingController(text: v.quantity.toString());
      }
    });
  }

  Future<Uint8List> _generatePdf(BuildContext context) async {
    if (_selectedProduct == null) return Uint8List(0);

    final variantsToPrint = <ProductVariant>[];
    for (var v in _selectedProduct!.variants) {
      final qty = int.tryParse(_qtyControllers[v]?.text ?? '0') ?? 0;
      for (int i = 0; i < qty; i++) {
        variantsToPrint.add(v);
      }
    }

    if (variantsToPrint.isEmpty) return Uint8List(0);

    final settings = ref.read(settingsProvider);
    final company = ref.watch(companyProvider);

    final pdf = await ExportService.generateBulkSheetPdf(
      _selectedProduct!,
      variantsToPrint,
      settings,
      company,
      tagSize: _tagSize,
    );
    return pdf.save();
  }

  Future<void> _generateBulkSheet() async {
    if (_selectedProduct == null) return;

    final variantsToPrint = <ProductVariant>[];
    for (var v in _selectedProduct!.variants) {
      final qty = int.tryParse(_qtyControllers[v]?.text ?? '0') ?? 0;
      if (qty < 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Quantities cannot be negative.')),
        );
        return;
      }
      for (int i = 0; i < qty; i++) {
        variantsToPrint.add(v);
      }
    }

    if (variantsToPrint.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select at least 1 quantity to print.'),
        ),
      );
      return;
    }

    if (variantsToPrint.length > 1000) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Too many tags to print at once. Max is 1000.'),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final settings = ref.read(settingsProvider);
      final company = ref.watch(companyProvider);
      final pdf = await ExportService.generateBulkSheetPdf(
        _selectedProduct!,
        variantsToPrint,
        settings,
        company,
        tagSize: _tagSize,
      );

      // Preview and Print using printing package
      await Printing.layoutPdf(
        onLayout: (format) async => pdf.save(),
        name: 'Bulk_Tags_${_selectedProduct!.productCode}',
      );
    } catch (e) {
      debugPrint('Bulk PDF generation error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to generate PDF. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bulk Price Tag Generator')),
      body: ResponsiveBuilder(
        mobileBuilder: (context) => _buildMobileLayout(context),
        desktopBuilder: (context) => _buildDesktopLayout(context),
      ),
    );
  }

  Widget _buildMobileLayout(BuildContext context) {
    return Column(
      children: [
        Expanded(
          flex: 1,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: _buildForm(),
          ),
        ),
        if (_selectedProduct != null)
          Expanded(flex: 1, child: InteractiveViewer(child: _buildPreview())),
      ],
    );
  }

  Widget _buildDesktopLayout(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 4,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: _buildForm(),
          ),
        ),
        const VerticalDivider(width: 1),
        if (_selectedProduct != null)
          Expanded(flex: 6, child: InteractiveViewer(child: _buildPreview()))
        else
          const Expanded(
            flex: 6,
            child: Center(child: Text('Select a product to preview tags')),
          ),
      ],
    );
  }

  Widget _buildPreview() {
    return PdfPreview(
      build: (format) => _generatePdf(context),
      canChangeOrientation: false,
      canChangePageFormat: false,
      canDebug: false,
      allowPrinting: true,
      allowSharing: true,
    );
  }

  Widget _buildForm() {
    final products = ref.watch(productsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Select Product',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<Product>(
          initialValue: _selectedProduct,
          isExpanded: true,
          hint: const Text('Choose a product'),
          items: products.map((p) {
            return DropdownMenuItem(
              value: p,
              child: Text('${p.productName} (${p.productCode})'),
            );
          }).toList(),
          onChanged: (p) {
            if (p != null) _onProductSelected(p);
          },
        ),
        const SizedBox(height: 24),
        if (_selectedProduct != null) ...[
          const Text(
            'Tag Size',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          SegmentedButton<PriceTagSize>(
            segments: PriceTagSize.values
                .map(
                  (size) => ButtonSegment(
                    value: size,
                    label: Text(size.label),
                  ),
                )
                .toList(),
            selected: {_tagSize},
            showSelectedIcon: false,
            // The preview rebuilds from _tagSize, so the sheet on screen is
            // always the sheet that will print.
            onSelectionChanged: (values) =>
                setState(() => _tagSize = values.first),
          ),
          const SizedBox(height: 6),
          Text(
            '${_tagSize.description} · ${_tagSize.columns} across × '
            '${_tagSize.rows} down',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Select Quantities to Print',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _selectedProduct!.variants.length,
            itemBuilder: (context, index) {
              final variant = _selectedProduct!.variants[index];
              return Row(
                children: [
                  Expanded(child: Text('Size: ${variant.size}')),
                  Expanded(child: Text('Barcode: ${variant.barcode}')),
                  SizedBox(
                    width: 80,
                    child: TextField(
                      controller: _qtyControllers[variant],
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Qty',
                        isDense: true,
                      ),
                      onChanged: (val) {
                        setState(() {}); // Trigger preview update
                      },
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : ElevatedButton.icon(
                    onPressed: _generateBulkSheet,
                    icon: const Icon(Icons.print),
                    label: const Text('Generate & Print Sheet'),
                  ),
          ),
        ],
      ],
    );
  }
}
