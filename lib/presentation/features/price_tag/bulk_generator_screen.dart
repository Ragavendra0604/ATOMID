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
import 'package:atomid/presentation/providers/app_providers.dart';

/// Which products the sheet is being built from.
enum _BulkMode {
  /// One product at a time — the original flow.
  singleProduct('This product'),

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
  PriceTagSize _tagSize = PriceTagSize.medium;
  bool _isLoading = false;

  /// Keyed by product and barcode rather than by the variant object, because
  /// in all-products mode variants from different products sit in the same
  /// map and two of them can be equal in every field that matters here.
  final Map<String, TextEditingController> _qtyControllers = {};
  final TextEditingController _searchController = TextEditingController();
  String _search = '';

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
    final products = _mode == _BulkMode.singleProduct
        ? (_selectedProduct == null
              ? const <Product>[]
              : <Product>[_selectedProduct!])
        : ref.read(productsProvider);

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
      for (final product in ref.read(productsProvider)) {
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
      final settings = ref.read(settingsProvider);
      final company = ref.read(companyProvider);
      final name = _mode == _BulkMode.allProducts
          ? 'Bulk_Tags_All_Products'
          : 'Bulk_Tags_${_selectedProduct?.productCode ?? ''}';

      // Built inside onLayout: the tag grid divides the sheet exactly, so it
      // has to be laid out for the paper the print dialog reports rather than
      // sized for one sheet and then scaled onto another.
      await Printing.layoutPdf(
        onLayout: (format) async {
          final pdf = await ExportService.generateBulkSheetPdf(
            lines,
            settings,
            company,
            tagSize: _tagSize,
            pageFormat: format,
          );
          return pdf.save();
        },
        name: name,
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

  bool get _hasSomethingToPreview => _collectLines().isNotEmpty;

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

        if (_mode == _BulkMode.allProducts || _selectedProduct != null) ...[
          const Text('Tag Size', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          SegmentedButton<PriceTagSize>(
            segments: PriceTagSize.values
                .map(
                  (size) => ButtonSegment(value: size, label: Text(size.label)),
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
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),

          Row(
            children: [
              const Expanded(
                child: Text(
                  'Select Quantities to Print',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              if (_mode == _BulkMode.allProducts) ...[
                TextButton(
                  onPressed: _fillFromStock,
                  child: const Text('Fill from stock'),
                ),
                TextButton(onPressed: _clearAll, child: const Text('Clear')),
              ],
            ],
          ),
          if (_mode == _BulkMode.allProducts) ...[
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

          if (_mode == _BulkMode.allProducts && products.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('No products yet.'),
            )
          else if (_mode == _BulkMode.allProducts)
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
                    icon: const Icon(Icons.print),
                    label: const Text('Generate & Print Sheet'),
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
