import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import 'package:atomid/core/services/export_service.dart';
import 'package:atomid/core/utils/responsive.dart';
import 'package:atomid/data/models/product_model.dart';
import 'package:atomid/domain/price_tag_job.dart';
import 'package:atomid/domain/price_tag_size.dart';
import 'package:atomid/domain/price_tag_print_mode.dart';
import 'package:atomid/core/hardware/label_layout_engine.dart'
    as import_layout_engine;
import 'package:atomid/presentation/common/share_bottom_sheet.dart';
import 'package:atomid/data/models/hardware_config_model.dart';
import 'package:atomid/core/hardware/label_printer_service.dart';
import 'package:atomid/core/hardware/print_job_manager.dart';
import 'package:atomid/presentation/providers/app_providers.dart';

/// Which products the sheet is being built from.
enum _BulkMode {
  /// One product at a time — the original flow.
  singleProduct('This product'),

  /// A few selected products.
  multipleProducts('Multiple products'),

  /// Every product in the catalogue on one continuous run of sheets.
  allProducts('All products');

  const _BulkMode(this.label);
  final String label;
}

class BulkGeneratorScreen extends ConsumerStatefulWidget {
  const BulkGeneratorScreen({super.key});

  @override
  ConsumerState<BulkGeneratorScreen> createState() =>
      _BulkGeneratorScreenState();
}

class _BulkGeneratorScreenState extends ConsumerState<BulkGeneratorScreen> {
  static const int _maxTags = 1000;

  _BulkMode _mode = _BulkMode.singleProduct;
  Product? _selectedProduct;
  List<Product> _selectedProducts = [];
  PriceTagSize _tagSize = PriceTagSize.medium;
  PriceTagPrintMode? _printMode;
  HardwareConfigModel? _hardwareConfig;
  bool _isLoading = false;

  /// Keyed by product and barcode rather than by the variant object, because
  /// in all-products mode variants from different products sit in the same
  /// map and two of them can be equal in every field that matters here.
  final Map<String, TextEditingController> _qtyControllers = {};
  final TextEditingController _searchController = TextEditingController();
  String _search = '';

  @override
  void initState() {
    super.initState();
    _loadHardwareConfig();
  }

  Future<void> _loadHardwareConfig() async {
    final config = await HardwareConfigModel.load();
    if (mounted) {
      setState(() {
        _hardwareConfig = config;
        _printMode =
            (config.labelPrinterName != null &&
                config.labelPrinterName!.isNotEmpty)
            ? PriceTagPrintMode.lp46Direct
            : PriceTagPrintMode.a4Sheet;
      });
    }
  }

  @override
  void dispose() {
    for (final ctrl in _qtyControllers.values) {
      ctrl.dispose();
    }
    _searchController.dispose();
    super.dispose();
  }

  String _key(Product product, ProductVariant variant) =>
      '${product.id}|${variant.barcode}';

  TextEditingController _controllerFor(
    Product product,
    ProductVariant variant, {
    String initial = '0',
  }) {
    return _qtyControllers.putIfAbsent(
      _key(product, variant),
      () => TextEditingController(text: initial),
    );
  }

  int _qtyFor(Product product, ProductVariant variant) {
    final text = _qtyControllers[_key(product, variant)]?.text ?? '0';
    return int.tryParse(text.trim()) ?? 0;
  }

  void _onProductSelected(Product product) {
    setState(() {
      _selectedProduct = product;
      // Single-product mode still starts from stock on hand, which is what
      // someone reprinting a whole rail wants.
      for (final v in product.variants) {
        // Reused rather than replaced: disposing a controller that a mounted
        // field still holds is a crash waiting for the next rebuild.
        _controllerFor(product, v, initial: v.quantity.toString()).text = v
            .quantity
            .toString();
      }
    });
  }

  /// The products the form is currently offering, in mode order.
  List<Product> get _activeProducts {
    if (_mode == _BulkMode.singleProduct) {
      return _selectedProduct == null ? const [] : [_selectedProduct!];
    }
    if (_mode == _BulkMode.multipleProducts) {
      if (_search.isEmpty) return _selectedProducts;
      final q = _search.toLowerCase();
      return _selectedProducts
          .where(
            (p) =>
                p.productName.toLowerCase().contains(q) ||
                p.color.toLowerCase().contains(q) ||
                p.productCode.toLowerCase().contains(q),
          )
          .toList();
    }
    final products = ref.read(productsProvider);
    if (_search.isEmpty) return products;
    final q = _search.toLowerCase();
    return products
        .where(
          (p) =>
              p.productName.toLowerCase().contains(q) ||
              p.color.toLowerCase().contains(q) ||
              p.productCode.toLowerCase().contains(q),
        )
        .toList();
  }

  /// Everything with a quantity above zero, across every product — not only
  /// the ones currently visible through the search box.
  List<PriceTagLine> _collectLines() {
    final lines = <PriceTagLine>[];
    final products = switch (_mode) {
      _BulkMode.singleProduct =>
        _selectedProduct == null
            ? const <Product>[]
            : <Product>[_selectedProduct!],
      _BulkMode.multipleProducts => _selectedProducts,
      _BulkMode.allProducts => ref.read(productsProvider),
    };

    for (final product in products) {
      for (final variant in product.variants) {
        final qty = _qtyFor(product, variant);
        if (qty > 0) {
          lines.add(
            PriceTagLine(product: product, variant: variant, quantity: qty),
          );
        }
      }
    }
    return lines;
  }

  int get _totalTags =>
      _collectLines().fold(0, (sum, line) => sum + line.quantity);

  void _fillFromStock() {
    setState(() {
      final products = _mode == _BulkMode.multipleProducts
          ? _selectedProducts
          : ref.read(productsProvider);
      for (final product in products) {
        for (final variant in product.variants) {
          _controllerFor(product, variant).text = variant.quantity.toString();
        }
      }
    });
  }

  void _clearAll() {
    setState(() {
      for (final ctrl in _qtyControllers.values) {
        ctrl.text = '0';
      }
    });
  }

  /// The sheet the configured page size describes.
  ///
  /// Also what the preview is pinned to, so what is on screen is the sheet
  /// that prints.
  PdfPageFormat get _sheetFormat =>
      ref.read(settingsProvider).pdfPageSize == 'Letter'
      ? PdfPageFormat.letter
      : PdfPageFormat.a4;

  Future<Uint8List> _generatePdf(PdfPageFormat format) async {
    final lines = _collectLines();
    if (lines.isEmpty) return Uint8List(0);

    final settings = ref.read(settingsProvider);
    // read, not watch: this runs from a callback, where subscribing would
    // register a dependency outside the build that created it.
    final company = ref.read(companyProvider);

    final pdf = await ExportService.generateBulkSheetPdf(
      lines,
      settings,
      company,
      tagSize: _tagSize,
      pageFormat: format,
    );
    return pdf.save();
  }

  Future<void> _generateBulkSheet() async {
    final lines = _collectLines();

    if (lines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter at least 1 quantity to print.'),
        ),
      );
      return;
    }

    final total = lines.fold(0, (sum, line) => sum + line.quantity);
    if (total > _maxTags) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Too many tags to print at once ($total). Max is $_maxTags.',
          ),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final name = _mode == _BulkMode.allProducts
          ? 'Bulk_Tags_All_Products'
          : _mode == _BulkMode.multipleProducts
          ? 'Bulk_Tags_Multiple_Products'
          : 'Bulk_Tags_${_selectedProduct?.productCode ?? ''}';

      if (_printMode == PriceTagPrintMode.lp46Direct) {
        // --- HARDWARE DIRECT PRINTING FLOW ---
        final config = _hardwareConfig ?? await HardwareConfigModel.load();

        if (!mounted) {
          setState(() => _isLoading = false);
          return;
        }

        if (config.labelPrinterName == null ||
            config.labelPrinterName!.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('TVS LP 46 DLITE label printer is not configured.'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }

        final settings = ref.read(settingsProvider);
        final company = ref.read(companyProvider);
        final printerSvc = ref.read(labelPrinterServiceProvider);
        final profile = printerSvc.activeProfile;

        final pdfDoc = await ExportService.generateBulkLabelRollPdf(
          lines,
          settings,
          company,
          profile,
        );
        final pdfBytes = await pdfDoc.save();

        final jobMgr = ref.read(printJobManagerProvider);
        final jobId = 'bulk_tag_${DateTime.now().millisecondsSinceEpoch}';

        if (!jobMgr.startJob(
          jobId,
          'BULK_PRINT',
          'LABEL',
          config.labelPrinterName!,
        )) {
          setState(() => _isLoading = false);
          return;
        }

        final engine = import_layout_engine.LabelLayoutEngine(profile);
        final success = await printerSvc.printLabel(
          pdfBytes,
          name,
          printerName: config.labelPrinterName,
          format: engine.pdfPageFormat,
        );

        if (!mounted) return;

        if (success) {
          jobMgr.completeJob(jobId);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Sent to label printer.')),
          );
        } else {
          jobMgr.failJob(jobId, printerSvc.statusMessage ?? 'Driver error');
          throw Exception(printerSvc.statusMessage);
        }
      } else {
        // --- FALLBACK INTERACTIVE FLOW ---
        final format = _sheetFormat;
        final pdfBytes = await _generatePdf(format);

        if (!mounted) return;

        await ShareBottomSheet.show(
          context: context,
          pdfBytes: pdfBytes,
          fileName: name,
          shareText: 'Bulk Price Tags',
          printPageFormat: format,
        );
      }
    } catch (e) {
      debugPrint('Bulk PDF generation error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Unable to print tags: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showMultiSelectDialog() async {
    final products = ref.read(productsProvider);
    final selected = await showDialog<List<Product>>(
      context: context,
      builder: (context) {
        return _MultiSelectProductDialog(
          products: products,
          initialSelected: _selectedProducts,
        );
      },
    );
    if (selected != null) {
      setState(() {
        _selectedProducts = selected;
        for (final product in _selectedProducts) {
          for (final v in product.variants) {
            _controllerFor(product, v, initial: v.quantity.toString());
          }
        }
      });
    }
  }

  bool get _hasSomethingToPreview => _collectLines().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    if (_printMode == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
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
        if (_hasSomethingToPreview)
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
        if (_hasSomethingToPreview)
          Expanded(flex: 6, child: InteractiveViewer(child: _buildPreview()))
        else
          const Expanded(
            flex: 6,
            child: Center(child: Text('Enter a quantity to preview tags')),
          ),
      ],
    );
  }

  Widget _buildPreview() {
    if (_printMode == PriceTagPrintMode.lp46Direct) {
      final printerSvc = ref.read(labelPrinterServiceProvider);
      final profile = printerSvc.activeProfile;
      final engine = import_layout_engine.LabelLayoutEngine(profile);

      return PdfPreview(
        build: (f) async {
          final lines = _collectLines();
          if (lines.isEmpty) return Uint8List(0);

          final settings = ref.read(settingsProvider);
          final company = ref.read(companyProvider);

          final pdfDoc = await ExportService.generateBulkLabelRollPdf(
            lines,
            settings,
            company,
            profile,
          );
          return pdfDoc.save();
        },
        initialPageFormat: engine.pdfPageFormat,
        canChangeOrientation: false,
        canChangePageFormat: false,
        canDebug: false,
        allowPrinting:
            false, // Force them to use our controlled print dispatch button
        allowSharing: false,
      );
    } else {
      return PdfPreview(
        build: _generatePdf,
        initialPageFormat: _sheetFormat,
        canChangeOrientation: false,
        canChangePageFormat: false,
        canDebug: false,
        allowPrinting: true,
        allowSharing: true,
      );
    }
  }

  Widget _buildForm() {
    final products = ref.watch(productsProvider);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Print for', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        SegmentedButton<_BulkMode>(
          segments: _BulkMode.values
              .map((m) => ButtonSegment(value: m, label: Text(m.label)))
              .toList(),
          selected: {_mode},
          showSelectedIcon: false,
          onSelectionChanged: (values) => setState(() => _mode = values.first),
        ),
        const SizedBox(height: 6),
        Text(
          _mode == _BulkMode.allProducts
              ? 'Tags for every product are packed onto the same sheets, so a '
                    'sheet is filled before a new one is started.'
              : 'Tags for the selected product only.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),

        if (_mode == _BulkMode.singleProduct) ...[
          const Text(
            'Select Product',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<Product>(
            initialValue: _selectedProduct,
            isExpanded: true,
            hint: const Text('Choose a product'),
            items: products
                .map(
                  (p) => DropdownMenuItem(
                    value: p,
                    child: Text('${p.displayName} (${p.productCode})'),
                  ),
                )
                .toList(),
            onChanged: (p) {
              if (p != null) _onProductSelected(p);
            },
          ),
          const SizedBox(height: 24),
        ],

        if (_mode == _BulkMode.multipleProducts) ...[
          const Text(
            'Select Products',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _showMultiSelectDialog,
            icon: const Icon(Icons.add),
            label: Text('Select Products (${_selectedProducts.length})'),
          ),
          if (_selectedProducts.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Wrap(
                spacing: 8,
                children: _selectedProducts.map((p) {
                  return Chip(
                    label: Text(p.displayName),
                    onDeleted: () {
                      setState(() {
                        _selectedProducts.remove(p);
                      });
                    },
                  );
                }).toList(),
              ),
            ),
          const SizedBox(height: 24),
        ],

        if (_mode == _BulkMode.allProducts ||
            _mode == _BulkMode.multipleProducts ||
            _selectedProduct != null) ...[
          const Text(
            'Print Destination',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          SegmentedButton<PriceTagPrintMode>(
            segments: const [
              ButtonSegment(
                value: PriceTagPrintMode.a4Sheet,
                label: Text('A4 Sheet Printer'),
              ),
              ButtonSegment(
                value: PriceTagPrintMode.lp46Direct,
                label: Text('LP46 Label Printer'),
              ),
            ],
            selected: {_printMode!},
            showSelectedIcon: false,
            onSelectionChanged: (values) =>
                setState(() => _printMode = values.first),
          ),
          const SizedBox(height: 24),

          if (_printMode == PriceTagPrintMode.a4Sheet) ...[
            const Text(
              'Tag Size',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            SegmentedButton<PriceTagSize>(
              segments: PriceTagSize.values
                  .map(
                    (size) =>
                        ButtonSegment(value: size, label: Text(size.label)),
                  )
                  .toList(),
              selected: {_tagSize},
              showSelectedIcon: false,
              onSelectionChanged: (values) =>
                  setState(() => _tagSize = values.first),
            ),
            const SizedBox(height: 6),
            Text(
              '${_tagSize.description} · ${_tagSize.columns} across × '
              '${_tagSize.rows} down',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
          ] else ...[
            const Text(
              'Label Size',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: theme.colorScheme.outlineVariant),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Builder(
                builder: (context) {
                  final config = _hardwareConfig;
                  if (config?.labelPrinterName == null ||
                      config!.labelPrinterName!.isEmpty) {
                    return const Text(
                      '⚠️ TVS LP 46 DLITE label printer is not configured.',
                      style: TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.w500,
                      ),
                    );
                  }
                  final profile = ref
                      .read(labelPrinterServiceProvider)
                      .activeProfile;
                  return Text(
                    'Printer: ${config.labelPrinterName}\n'
                    'Label: ${profile.labelWidthMm} × ${profile.labelHeightMm} mm\n'
                    'Media: ${profile.mediaWidthMm} × ${profile.mediaHeightMm} mm\n'
                    'Columns: ${profile.columns} · Gap: ${profile.horizontalGapMm} mm',
                    style: TextStyle(
                      color: theme.colorScheme.onSurface,
                      fontWeight: FontWeight.w500,
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 24),
          ],

          Row(
            children: [
              const Expanded(
                child: Text(
                  'Select Quantities to Print',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              if (_mode == _BulkMode.allProducts ||
                  _mode == _BulkMode.multipleProducts) ...[
                TextButton(
                  onPressed: _fillFromStock,
                  child: const Text('Fill from stock'),
                ),
                TextButton(onPressed: _clearAll, child: const Text('Clear')),
              ],
            ],
          ),
          if (_mode == _BulkMode.allProducts ||
              _mode == _BulkMode.multipleProducts) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Filter products',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (val) => setState(() => _search = val.trim()),
            ),
            const SizedBox(height: 4),
            Text(
              'Quantities you enter are kept even while a filter hides the row.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 8),

          if ((_mode == _BulkMode.allProducts && products.isEmpty) ||
              (_mode == _BulkMode.multipleProducts &&
                  _selectedProducts.isEmpty))
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('No products selected or available.'),
            )
          else if (_mode == _BulkMode.allProducts ||
              _mode == _BulkMode.multipleProducts)
            ..._activeProducts.map(_buildProductGroup)
          else
            _buildVariantRows(_selectedProduct!),

          const SizedBox(height: 16),
          _buildSummary(context),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : ElevatedButton.icon(
                    onPressed: _generateBulkSheet,
                    icon: const Icon(Icons.ios_share),
                    label: const Text('Export or Print Sheet'),
                  ),
          ),
        ],
      ],
    );
  }

  Widget _buildProductGroup(Product product) {
    final selected = product.variants.fold<int>(
      0,
      (sum, v) => sum + _qtyFor(product, v),
    );
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        // A ValueKey, deliberately not a PageStorageKey. `ExpansionTile`
        // writes its expanded/collapsed flag into PageStorage under the
        // nearest PageStorageKey, and the Qty field inside it then reads that
        // same bucket when restoring its scroll offset — "type 'bool' is not a
        // subtype of type 'double?'", thrown while laying the field out. A
        // ValueKey identifies the tile across rebuilds without touching
        // PageStorage at all.
        key: ValueKey<String>(product.id),
        title: Text('${product.displayName} (${product.productCode})'),
        subtitle: Text(
          selected > 0
              ? '$selected tag${selected == 1 ? '' : 's'} selected'
              : '${product.variants.length} variant'
                    '${product.variants.length == 1 ? '' : 's'}',
        ),
        initiallyExpanded: selected > 0,
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        children: [_buildVariantRows(product)],
      ),
    );
  }

  Widget _buildVariantRows(Product product) {
    final theme = Theme.of(context);
    return Column(
      children: product.variants.map((variant) {
        final controller = _controllerFor(product, variant);
        final wanted = int.tryParse(controller.text.trim()) ?? 0;
        final overStock = wanted > variant.quantity;

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Size: ${variant.size}',
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    Text(
                      'Barcode: ${variant.barcode}',
                      style: theme.textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                    // Shown next to the input so the number that is being
                    // typed can be judged against the stock it is printed for.
                    Text(
                      'Available: ${variant.quantity}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: variant.quantity <= 0
                            ? theme.colorScheme.error
                            : (variant.quantity <= variant.reorderLevel
                                  ? Colors.orange.shade800
                                  : theme.colorScheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 96,
                child: TextField(
                  controller: controller,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Qty',
                    isDense: true,
                    helperText: overStock ? 'Over stock' : null,
                    helperStyle: TextStyle(color: Colors.orange.shade800),
                  ),
                  onChanged: (val) => setState(() {}),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSummary(BuildContext context) {
    final theme = Theme.of(context);
    final total = _totalTags;
    if (total == 0) {
      return Text(
        'Nothing selected yet.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    if (_printMode == PriceTagPrintMode.lp46Direct) {
      final profile = ref.read(labelPrinterServiceProvider).activeProfile;

      final rows = (total + 1) ~/ 2;
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          '$total label${total == 1 ? '' : 's'} · $rows print row${rows == 1 ? '' : 's'}\n'
          '(${profile.labelWidthMm}×${profile.labelHeightMm} mm, ${profile.columns} columns)',
          style: theme.textTheme.bodyMedium,
        ),
      );
    } else {
      final perPage = _tagSize.perPage;
      final sheets = (total / perPage).ceil();
      final free = sheets * perPage - total;

      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          '$total tag${total == 1 ? '' : 's'} · $sheets sheet'
          '${sheets == 1 ? '' : 's'}'
          '${free > 0 ? ' · $free empty slot${free == 1 ? '' : 's'} on the last sheet' : ' · sheets filled exactly'}',
          style: theme.textTheme.bodyMedium,
        ),
      );
    }
  }
}

class _MultiSelectProductDialog extends StatefulWidget {
  final List<Product> products;
  final List<Product> initialSelected;

  const _MultiSelectProductDialog({
    required this.products,
    required this.initialSelected,
  });

  @override
  State<_MultiSelectProductDialog> createState() =>
      _MultiSelectProductDialogState();
}

class _MultiSelectProductDialogState extends State<_MultiSelectProductDialog> {
  late Set<Product> _selected;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _selected = Set.from(widget.initialSelected);
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _search.isEmpty
        ? widget.products
        : widget.products
              .where(
                (p) =>
                    p.productName.toLowerCase().contains(
                      _search.toLowerCase(),
                    ) ||
                    p.productCode.toLowerCase().contains(_search.toLowerCase()),
              )
              .toList();

    return AlertDialog(
      title: const Text('Select Products'),
      content: SizedBox(
        width: double.maxFinite,
        height: MediaQuery.of(context).size.height * 0.6,
        child: Column(
          children: [
            TextField(
              decoration: const InputDecoration(
                hintText: 'Search...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (val) => setState(() => _search = val),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (context, index) {
                  final product = filtered[index];
                  final isSelected = _selected.contains(product);
                  return CheckboxListTile(
                    title: Text(
                      '${product.displayName} (${product.productCode})',
                    ),
                    value: isSelected,
                    onChanged: (val) {
                      setState(() {
                        if (val == true) {
                          _selected.add(product);
                        } else {
                          _selected.remove(product);
                        }
                      });
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, _selected.toList()),
          child: const Text('Confirm'),
        ),
      ],
    );
  }
}
