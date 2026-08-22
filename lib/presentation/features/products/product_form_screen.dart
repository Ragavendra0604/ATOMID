import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:atomid/data/models/product_model.dart';
import 'package:atomid/data/models/action_history_model.dart';
import 'package:atomid/presentation/widgets/adaptive_dialog.dart';
import 'package:atomid/presentation/providers/app_providers.dart';
import 'package:atomid/core/utils/responsive.dart';
import 'package:uuid/uuid.dart';

class ProductFormScreen extends ConsumerStatefulWidget {
  final Product? existingProduct;
  final String? initialCode;
  final String? initialPrice;
  final String? initialSize;

  const ProductFormScreen({
    super.key,
    this.existingProduct,
    this.initialCode,
    this.initialPrice,
    this.initialSize,
  });

  @override
  ConsumerState<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends ConsumerState<ProductFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameCtrl;
  late TextEditingController _codeCtrl;
  late TextEditingController _brandCtrl;
  late TextEditingController _colorCtrl;
  late TextEditingController _categoryCtrl;

  final List<String> _availableSizes = ['S', 'M', 'L', 'XL', 'XXL'];
  final Map<String, bool> _selectedSizes = {};
  final Map<String, TextEditingController> _priceCtrls = {};
  final Map<String, TextEditingController> _qtyCtrls = {};
  final Map<String, TextEditingController> _barcodeCtrls = {};
  final Map<String, TextEditingController> _skuCtrls = {};
  final Map<String, TextEditingController> _stockInCtrls = {};
  final Map<String, TextEditingController> _stockOutCtrls = {};
  final Map<String, TextEditingController> _reorderLevelCtrls = {};

  final Uuid _uuid = const Uuid();

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(
      text: widget.existingProduct?.productName ?? '',
    );
    _codeCtrl = TextEditingController(
      text: widget.existingProduct?.productCode ?? widget.initialCode ?? '',
    );
    _brandCtrl = TextEditingController(
      text: widget.existingProduct?.brand ?? '',
    );
    _colorCtrl = TextEditingController(
      text: widget.existingProduct?.color ?? '',
    );
    _categoryCtrl = TextEditingController(
      text: widget.existingProduct?.category ?? 'General',
    );

    for (var s in _availableSizes) {
      _selectedSizes[s] = false;
      _priceCtrls[s] = TextEditingController(text: widget.initialPrice ?? '0');
      _qtyCtrls[s] = TextEditingController(text: '10');
      _barcodeCtrls[s] = TextEditingController(text: _generateMockBarcode());
      _skuCtrls[s] = TextEditingController();
      _stockInCtrls[s] = TextEditingController(text: '0');
      _stockOutCtrls[s] = TextEditingController(text: '0');
      _reorderLevelCtrls[s] = TextEditingController(text: '5');
    }

    if (widget.existingProduct != null) {
      for (var variant in widget.existingProduct!.variants) {
        if (!_availableSizes.contains(variant.size)) {
          _availableSizes.add(variant.size);
          _selectedSizes[variant.size] = false;
          _priceCtrls[variant.size] = TextEditingController();
          _qtyCtrls[variant.size] = TextEditingController();
          _barcodeCtrls[variant.size] = TextEditingController();
          _skuCtrls[variant.size] = TextEditingController();
          _stockInCtrls[variant.size] = TextEditingController();
          _stockOutCtrls[variant.size] = TextEditingController();
          _reorderLevelCtrls[variant.size] = TextEditingController();
        }
        _selectedSizes[variant.size] = true;
        _priceCtrls[variant.size]!.text = variant.price.toString();
        _qtyCtrls[variant.size]!.text = variant.quantity.toString();
        _barcodeCtrls[variant.size]!.text = variant.barcode;
        _skuCtrls[variant.size]!.text = variant.sku;
        _stockInCtrls[variant.size]!.text = variant.stockIn.toString();
        _stockOutCtrls[variant.size]!.text = variant.stockOut.toString();
        _reorderLevelCtrls[variant.size]!.text = variant.reorderLevel
            .toString();
      }
    } else if (widget.initialSize != null) {
      final s = widget.initialSize!;
      if (!_availableSizes.contains(s)) {
        _availableSizes.add(s);
        _selectedSizes[s] = false;
        _priceCtrls[s] = TextEditingController(
          text: widget.initialPrice ?? '0',
        );
        _qtyCtrls[s] = TextEditingController(text: '10');
        _barcodeCtrls[s] = TextEditingController(text: _generateMockBarcode());
        _skuCtrls[s] = TextEditingController();
        _stockInCtrls[s] = TextEditingController(text: '0');
        _stockOutCtrls[s] = TextEditingController(text: '0');
        _reorderLevelCtrls[s] = TextEditingController(text: '5');
      }
      _selectedSizes[s] = true;
    }
  }

  String _generateMockBarcode() {
    return _uuid.v4().replaceAll('-', '').substring(0, 12).toUpperCase();
  }

  String _generateSku(String size) {
    final settings = ref.read(settingsProvider);
    final storeCode = settings.companyName
        .replaceAll(' ', '')
        .substring(
          0,
          settings.companyName.replaceAll(' ', '').length.clamp(0, 3),
        )
        .toUpperCase();
    final code = _codeCtrl.text.trim().toUpperCase();
    final color = _colorCtrl.text.trim().toUpperCase();
    final colorPart = color.isEmpty ? '' : '-$color';
    return '$storeCode-$code$colorPart-$size';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _codeCtrl.dispose();
    _brandCtrl.dispose();
    _colorCtrl.dispose();
    _categoryCtrl.dispose();
    for (var c in _priceCtrls.values) {
      c.dispose();
    }
    for (var c in _qtyCtrls.values) {
      c.dispose();
    }
    for (var c in _barcodeCtrls.values) {
      c.dispose();
    }
    for (var c in _skuCtrls.values) {
      c.dispose();
    }
    for (var c in _stockInCtrls.values) {
      c.dispose();
    }
    for (var c in _stockOutCtrls.values) {
      c.dispose();
    }
    for (var c in _reorderLevelCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.existingProduct != null ? 'Edit Product' : 'Create Product',
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            tooltip: 'Save Product',
            onPressed: _saveProduct,
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: ResponsivePadding.getScreenPadding(context),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: ResponsiveBreakpoints.maxFormWidth,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Basic Information',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _nameCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Product Name',
                              prefixIcon: Icon(Icons.inventory_2),
                            ),
                            validator: (val) =>
                                val == null || val.trim().isEmpty
                                ? 'Name is required'
                                : null,
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _codeCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Product Code',
                              prefixIcon: Icon(Icons.qr_code),
                            ),
                            validator: (val) {
                              if (val == null || val.trim().isEmpty) {
                                return 'Code is required';
                              }
                              // Check for duplicate code
                              final repo = ref.read(storageRepositoryProvider);
                              final existing = repo.getAllProducts().where(
                                (p) =>
                                    p.productCode == val.trim() &&
                                    p.id != widget.existingProduct?.id,
                              );
                              if (existing.isNotEmpty) {
                                return 'Product Code already exists';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: _brandCtrl,
                                  decoration: const InputDecoration(
                                    labelText: 'Brand',
                                    prefixIcon: Icon(Icons.branding_watermark),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: TextFormField(
                                  controller: _colorCtrl,
                                  decoration: const InputDecoration(
                                    labelText: 'Color',
                                    prefixIcon: Icon(Icons.color_lens),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _categoryCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Category',
                              prefixIcon: Icon(Icons.category),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Variants (Sizes & Inventory)',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  ..._availableSizes.map((s) => _buildVariantCard(s)),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () => _showAddSizeDialog(),
                    icon: const Icon(Icons.add),
                    label: const Text('Add Custom Size'),
                  ),
                  const SizedBox(height: 48),
                ],
              ),
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _saveProduct,
        label: const Text('Save Product'),
        icon: const Icon(Icons.save),
      ),
    );
  }

  Widget _buildVariantCard(String size) {
    final isSelected = _selectedSizes[size] ?? false;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: isSelected
              ? Theme.of(context).colorScheme.primary
              : Colors.transparent,
          width: 2,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ExpansionTile(
        initiallyExpanded: isSelected,
        onExpansionChanged: (val) {
          setState(() => _selectedSizes[size] = val);
        },
        leading: Checkbox(
          value: isSelected,
          onChanged: (val) {
            setState(() => _selectedSizes[size] = val ?? false);
          },
        ),
        title: Text(
          'Size: $size',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        children: [
          if (isSelected)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _priceCtrls[size],
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Price',
                            prefixIcon: Icon(Icons.attach_money),
                          ),
                          validator: (val) {
                            if (!isSelected) return null;
                            final price = double.tryParse(val ?? '');
                            if (price == null || price < 0) {
                              return 'Invalid price';
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextFormField(
                          controller: _qtyCtrls[size],
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Available Qty',
                            prefixIcon: Icon(Icons.production_quantity_limits),
                          ),
                          validator: (val) {
                            if (!isSelected) return null;
                            final qty = int.tryParse(val ?? '');
                            if (qty == null || qty < 0) return 'Invalid qty';
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _barcodeCtrls[size],
                    decoration: InputDecoration(
                      labelText: 'Barcode',
                      prefixIcon: const Icon(Icons.barcode_reader),
                      suffixIcon: IconButton(
                        tooltip: 'Generate a new barcode',
                        icon: const Icon(Icons.refresh),
                        onPressed: () {
                          setState(() {
                            _barcodeCtrls[size]!.text = _generateMockBarcode();
                          });
                        },
                      ),
                    ),
                    validator: (val) {
                      if (!isSelected) return null;
                      if (val == null || val.trim().isEmpty) {
                        return 'Barcode is required';
                      }
                      // Check for duplicate barcode across all products
                      final repo = ref.read(storageRepositoryProvider);
                      final existingProduct = repo.getProductByBarcode(
                        val.trim(),
                      );
                      if (existingProduct != null &&
                          existingProduct.id != widget.existingProduct?.id) {
                        return 'Barcode already in use by ${existingProduct.productName}';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _skuCtrls[size],
                    decoration: InputDecoration(
                      labelText: 'SKU',
                      prefixIcon: const Icon(Icons.label_outline),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.auto_fix_high),
                        tooltip: 'Auto-generate SKU',
                        onPressed: () {
                          setState(() {
                            _skuCtrls[size]!.text = _generateSku(size);
                          });
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _stockInCtrls[size],
                          readOnly: widget.existingProduct != null,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Total Stock In',
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextFormField(
                          controller: _stockOutCtrls[size],
                          readOnly: widget.existingProduct != null,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Total Stock Out',
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextFormField(
                          controller: _reorderLevelCtrls[size],
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Reorder Lvl',
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _showAddSizeDialog() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AdaptiveDialog(
        title: const Text('Add Custom Size'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            labelText: 'Size Label (e.g. 32, 34, OS)',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final newSize = ctrl.text.trim().toUpperCase();
              if (newSize.isNotEmpty && !_availableSizes.contains(newSize)) {
                setState(() {
                  _availableSizes.add(newSize);
                  _selectedSizes[newSize] = true;
                  _priceCtrls[newSize] = TextEditingController(text: '0');
                  _qtyCtrls[newSize] = TextEditingController(text: '10');
                  _barcodeCtrls[newSize] = TextEditingController(
                    text: _generateMockBarcode(),
                  );
                  _skuCtrls[newSize] = TextEditingController(
                    text: _generateSku(newSize),
                  );
                  _stockInCtrls[newSize] = TextEditingController(text: '0');
                  _stockOutCtrls[newSize] = TextEditingController(text: '0');
                  _reorderLevelCtrls[newSize] = TextEditingController(
                    text: '5',
                  );
                });
                Navigator.pop(ctx);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveProduct() async {
    if (!_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fix the errors in the form')),
      );
      return;
    }

    final variants = <ProductVariant>[];

    // Validate that barcodes are unique among the selected variants
    final currentBarcodes = <String>{};

    for (var s in _availableSizes) {
      if (_selectedSizes[s] == true) {
        final barcode = _barcodeCtrls[s]!.text.trim();
        if (currentBarcodes.contains(barcode)) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Duplicate barcode detected in form: $barcode'),
            ),
          );
          return;
        }
        currentBarcodes.add(barcode);

        variants.add(
          ProductVariant(
            size: s,
            price: double.tryParse(_priceCtrls[s]!.text) ?? 0.0,
            quantity: int.tryParse(_qtyCtrls[s]!.text) ?? 0,
            barcode: barcode,
            sku: _skuCtrls[s]?.text.trim() ?? '',
            lastStockUpdated: DateTime.now(),
            stockIn: int.tryParse(_stockInCtrls[s]!.text) ?? 0,
            stockOut: int.tryParse(_stockOutCtrls[s]!.text) ?? 0,
            reorderLevel: int.tryParse(_reorderLevelCtrls[s]!.text) ?? 5,
          ),
        );
      }
    }

    if (variants.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select at least one size variant'),
        ),
      );
      return;
    }

    final isNew = widget.existingProduct == null;
    final productId = widget.existingProduct?.id ?? _uuid.v4();

    final product = Product(
      id: productId,
      productName: _nameCtrl.text.trim(),
      productCode: _codeCtrl.text.trim(),
      category: _categoryCtrl.text.trim().isEmpty
          ? 'General'
          : _categoryCtrl.text.trim(),
      brand: _brandCtrl.text.trim(),
      color: _colorCtrl.text.trim(),
      createdDate: widget.existingProduct?.createdDate ?? DateTime.now(),
      updatedDate: DateTime.now(),
      variants: variants,
    );

    final repo = ref.read(storageRepositoryProvider);
    // Edits go through the audited path so a stock correction made here
    // leaves the same movement trail as one made from the stock-in screen.
    if (isNew) {
      await repo.saveProduct(product);
    } else {
      await repo.saveProductWithStockAudit(product);
    }

    if (isNew) {
      await repo.saveHistory(
        ActionHistory(
          id: _uuid.v4(),
          barcode: variants.first.barcode,
          productName: product.productName,
          action: 'Product Created',
          date: DateTime.now(),
        ),
      );
    } else {
      await repo.saveHistory(
        ActionHistory(
          id: _uuid.v4(),
          barcode: variants.first.barcode,
          productName: product.productName,
          action: 'Product Updated',
          date: DateTime.now(),
        ),
      );
    }

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Product saved successfully')));
      Navigator.pop(context);
    }
  }
}
