import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'package:atomid/core/utils/formatters.dart';
import 'package:atomid/core/utils/ids.dart';
import 'package:atomid/core/utils/responsive.dart';
import 'package:atomid/data/models/action_history_model.dart';
import 'package:atomid/data/models/product_model.dart';
import 'package:atomid/domain/gst/gst_treatment.dart';
import 'package:atomid/presentation/providers/app_providers.dart';
import 'package:atomid/presentation/widgets/adaptive_dialog.dart';

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
  late TextEditingController _hsnCtrl;
  late TextEditingController _cessCtrl;
  late TextEditingController _customRateCtrl;

  late String _gstTreatment;
  double? _selectedGstRate;
  late String _uqc;
  String? _selectedRateConfigId;
  bool _isCustomRate = false;

  final List<String> _availableSizes = ['S', 'M', 'L', 'XL', 'XXL'];
  final Map<String, bool> _selectedSizes = {};
  final Map<String, TextEditingController> _priceCtrls = {};
  final Map<String, TextEditingController> _costPriceCtrls = {};
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
    final p = widget.existingProduct;
    final settings = ref.read(settingsProvider);

    _nameCtrl = TextEditingController(text: p?.productName ?? '');
    _codeCtrl = TextEditingController(
      text: p?.productCode ?? widget.initialCode ?? '',
    );
    _brandCtrl = TextEditingController(text: p?.brand ?? '');
    _colorCtrl = TextEditingController(text: p?.color ?? '');
    _categoryCtrl = TextEditingController(text: p?.category ?? 'Dresses');
    _hsnCtrl = TextEditingController(text: p?.hsn ?? '');
    _cessCtrl = TextEditingController(
      text: p != null ? Fmt.amount(p.cessRate) : '0',
    );
    _gstTreatment = p?.gstTreatment.isNotEmpty == true
        ? p!.gstTreatment
        : GstTreatment.taxable;
    _uqc = p?.uqc.isNotEmpty == true
        ? p!.uqc
        : (settings.defaultUqc.isNotEmpty ? settings.defaultUqc : 'PCS');
    _selectedGstRate =
        p?.gstRate ?? (settings.taxRate > 0 ? settings.taxRate : 5.0);
    _selectedRateConfigId = p?.gstRateConfigId;

    _customRateCtrl = TextEditingController(
      text: _selectedGstRate != null ? Fmt.amount(_selectedGstRate!) : '5',
    );

    for (var s in _availableSizes) {
      _selectedSizes[s] = false;
      _priceCtrls[s] = TextEditingController(text: widget.initialPrice ?? '0');
      _costPriceCtrls[s] = TextEditingController(text: '0');
      _qtyCtrls[s] = TextEditingController(text: '10');
      _barcodeCtrls[s] = TextEditingController(text: _generateMockBarcode());
      _skuCtrls[s] = TextEditingController();
      _stockInCtrls[s] = TextEditingController(text: '0');
      _stockOutCtrls[s] = TextEditingController(text: '0');
      _reorderLevelCtrls[s] = TextEditingController(text: '5');
    }

    if (p != null) {
      for (var variant in p.variants) {
        if (!_availableSizes.contains(variant.size)) {
          _availableSizes.add(variant.size);
          _selectedSizes[variant.size] = false;
          _priceCtrls[variant.size] = TextEditingController();
          _costPriceCtrls[variant.size] = TextEditingController();
          _qtyCtrls[variant.size] = TextEditingController();
          _barcodeCtrls[variant.size] = TextEditingController();
          _skuCtrls[variant.size] = TextEditingController();
          _stockInCtrls[variant.size] = TextEditingController();
          _stockOutCtrls[variant.size] = TextEditingController();
          _reorderLevelCtrls[variant.size] = TextEditingController();
        }
        _selectedSizes[variant.size] = true;
        _priceCtrls[variant.size]!.text = variant.price.toString();
        _costPriceCtrls[variant.size]!.text = variant.costPrice.toString();
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
        _costPriceCtrls[s] = TextEditingController(text: '0');
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

  /// The other colourways already filed under the code being typed.
  ///
  /// Empty is the ordinary case. When it is not, the form says so rather
  /// than treating the shared code as a mistake — one code is one style, and
  /// each colour of that style is its own product record.
  List<String> get _codeSharedWith {
    final code = _codeCtrl.text.trim();
    if (code.isEmpty) return const [];
    final twins = ref
        .read(storageRepositoryProvider)
        .productsWithCode(code, excludeId: widget.existingProduct?.id);
    final labels = <String>[];
    for (final twin in twins) {
      final colour = twin.color.trim();
      final label = colour.isEmpty ? twin.productName : colour;
      if (!labels.contains(label)) labels.add(label);
    }
    if (labels.length <= 3) return labels;
    return [...labels.take(3), 'and ${labels.length - 3} more'];
  }

  /// True when the save should go ahead.
  ///
  /// Sharing a code is expected, so nothing here blocks it. What is worth
  /// stopping for is a code shared with **no colour to tell the records
  /// apart**, and a code plus colour that already exists — the one
  /// combination that is a double entry rather than a second colourway.
  Future<bool> _confirmSharedCode() async {
    final repo = ref.read(storageRepositoryProvider);
    final code = _codeCtrl.text.trim();
    final colour = _colorCtrl.text.trim();
    if (code.isEmpty) return true;

    final twins = repo.productsWithCode(
      code,
      excludeId: widget.existingProduct?.id,
    );
    if (twins.isEmpty) return true;

    if (colour.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Code $code is already used by ${twins.length} other '
            'product(s). Enter the colour so they can be told apart.',
          ),
        ),
      );
      return false;
    }

    final twin = repo.productWithCodeAndColour(
      code,
      colour,
      excludeId: widget.existingProduct?.id,
    );
    if (twin == null) return true;

    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AdaptiveDialog(
        title: const Text('Already stocked?'),
        content: Text(
          '${twin.displayName} is already filed under code $code with '
          '${twin.variants.length} size(s).\n\n'
          'Saving this creates a second record for the same colour. Stock '
          'counts for the two will be kept separately.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Go back'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save anyway'),
          ),
        ],
      ),
    );
    return proceed ?? false;
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
    _hsnCtrl.dispose();
    _cessCtrl.dispose();
    _customRateCtrl.dispose();
    for (var c in _priceCtrls.values) {
      c.dispose();
    }
    for (var c in _costPriceCtrls.values) {
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
    final settings = ref.watch(settingsProvider);
    final rateConfigs = ref
        .watch(storageRepositoryProvider)
        .getGstRateConfigs();

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
                          Text(
                            'Basic Information',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _nameCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Product Name *',
                              prefixIcon: Icon(Icons.shopping_bag_outlined),
                            ),
                            validator: (val) {
                              if (val == null || val.trim().isEmpty) {
                                return 'Product name is required';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: _codeCtrl,
                                  onChanged: (_) => setState(() {}),
                                  decoration: InputDecoration(
                                    labelText: 'Product Code / Style #',
                                    prefixIcon: const Icon(Icons.qr_code_2),
                                    helperMaxLines: 2,
                                    helperText: _codeSharedWith.isEmpty
                                        ? 'One code per style. Reuse it for '
                                              'the same style in another '
                                              'colour.'
                                        : 'Also used by '
                                              '${_codeSharedWith.join(", ")}',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: TextFormField(
                                  controller: _categoryCtrl,
                                  decoration: const InputDecoration(
                                    labelText: 'Category',
                                    prefixIcon: Icon(Icons.category_outlined),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: _brandCtrl,
                                  decoration: const InputDecoration(
                                    labelText: 'Brand',
                                    prefixIcon: Icon(
                                      Icons.branding_watermark_outlined,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: TextFormField(
                                  controller: _colorCtrl,
                                  decoration: InputDecoration(
                                    labelText: _codeSharedWith.isEmpty
                                        ? 'Color / Pattern'
                                        : 'Color / Pattern *',
                                    prefixIcon: const Icon(
                                      Icons.palette_outlined,
                                    ),
                                    helperMaxLines: 2,
                                    helperText: _codeSharedWith.isEmpty
                                        ? null
                                        : 'Needed to tell this apart from '
                                              'the other products on this '
                                              'code.',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // GST & Statutory Tax Configuration Card
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.account_balance_outlined,
                                color: Colors.blue,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'GST & Tax Configuration',
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  initialValue: _gstTreatment,
                                  isExpanded: true,
                                  decoration: const InputDecoration(
                                    labelText: 'GST Tax Treatment *',
                                    border: OutlineInputBorder(),
                                  ),
                                  items: const [
                                    DropdownMenuItem(
                                      value: GstTreatment.taxable,
                                      child: Text(
                                        'TAXABLE (Standard GST)',
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    DropdownMenuItem(
                                      value: GstTreatment.nilRated,
                                      child: Text(
                                        'NIL RATED (0% Statutory)',
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    DropdownMenuItem(
                                      value: GstTreatment.exempt,
                                      child: Text(
                                        'EXEMPT (Non-taxable goods)',
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    DropdownMenuItem(
                                      value: GstTreatment.nonGst,
                                      child: Text(
                                        'NON-GST (Outside GST scope)',
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    DropdownMenuItem(
                                      value: GstTreatment.zeroRated,
                                      child: Text(
                                        'ZERO RATED (Export / SEZ)',
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                  onChanged: (val) {
                                    if (val != null) {
                                      setState(() {
                                        _gstTreatment = val;
                                        if (!GstTreatment.attractsTax(val)) {
                                          _selectedGstRate = 0.0;
                                        }
                                      });
                                    }
                                  },
                                ),
                              ),
                            ],
                          ),
                          if (GstTreatment.attractsTax(_gstTreatment)) ...[
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: DropdownButtonFormField<double?>(
                                    initialValue: _isCustomRate
                                        ? null
                                        : _selectedGstRate,
                                    isExpanded: true,
                                    decoration: const InputDecoration(
                                      labelText: 'GST Rate % *',
                                      border: OutlineInputBorder(),
                                    ),
                                    items: [
                                      for (final config in rateConfigs)
                                        DropdownMenuItem<double?>(
                                          value: config.rate,
                                          child: Text(
                                            '${config.rateName} (${Fmt.amount(config.rate)}%)',
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      const DropdownMenuItem<double?>(
                                        value: -1.0,
                                        child: Text(
                                          'Custom Rate %',
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                    onChanged: (val) {
                                      if (val == -1.0) {
                                        setState(() {
                                          _isCustomRate = true;
                                          _selectedRateConfigId = null;
                                        });
                                      } else {
                                        setState(() {
                                          _isCustomRate = false;
                                          _selectedGstRate = val;
                                          final found = rateConfigs
                                              .where((r) => r.rate == val)
                                              .firstOrNull;
                                          _selectedRateConfigId = found?.id;
                                        });
                                      }
                                    },
                                  ),
                                ),
                                if (_isCustomRate) ...[
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: TextFormField(
                                      controller: _customRateCtrl,
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                            decimal: true,
                                          ),
                                      decoration: const InputDecoration(
                                        labelText: 'Custom GST %',
                                        suffixText: '%',
                                        border: OutlineInputBorder(),
                                      ),
                                      validator: (val) {
                                        final rate = double.tryParse(val ?? '');
                                        if (rate == null ||
                                            rate < 0 ||
                                            rate > 100) {
                                          return 'Enter 0 to 100';
                                        }
                                        return null;
                                      },
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: _cessCtrl,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                    decoration: const InputDecoration(
                                      labelText:
                                          'Compensation Cess % (Optional)',
                                      suffixText: '%',
                                      border: OutlineInputBorder(),
                                      helperText:
                                          'Usually 0% for retail garments.',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: TextFormField(
                                  controller: _hsnCtrl,
                                  keyboardType: TextInputType.number,
                                  decoration: InputDecoration(
                                    labelText: settings.hsnRequired
                                        ? 'HSN Code *'
                                        : 'HSN Code',
                                    border: const OutlineInputBorder(),
                                    helperText:
                                        'Statutory 2, 4, 6, or 8-digit HSN code (e.g. 6204 for Women Suits/Dresses)',
                                  ),
                                  validator: (val) {
                                    final trimmed = val?.trim() ?? '';
                                    if (settings.hsnRequired &&
                                        trimmed.isEmpty) {
                                      return 'HSN Code is required by store policy';
                                    }
                                    if (trimmed.isNotEmpty &&
                                        !RegExp(
                                          r'^\d{2,8}$',
                                        ).hasMatch(trimmed)) {
                                      return 'HSN must be 2 to 8 digits';
                                    }
                                    return null;
                                  },
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                flex: 2,
                                child: DropdownButtonFormField<String>(
                                  initialValue: _uqc,
                                  isExpanded: true,
                                  decoration: const InputDecoration(
                                    labelText: 'UQC Unit',
                                    border: OutlineInputBorder(),
                                  ),
                                  items: const [
                                    DropdownMenuItem(
                                      value: 'PCS',
                                      child: Text(
                                        'PCS (Pieces)',
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    DropdownMenuItem(
                                      value: 'NOS',
                                      child: Text(
                                        'NOS (Numbers)',
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    DropdownMenuItem(
                                      value: 'SET',
                                      child: Text(
                                        'SET (Sets)',
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    DropdownMenuItem(
                                      value: 'MTR',
                                      child: Text(
                                        'MTR (Meters)',
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    DropdownMenuItem(
                                      value: 'KGS',
                                      child: Text(
                                        'KGS (Kilograms)',
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                  onChanged: (val) {
                                    if (val != null) setState(() => _uqc = val);
                                  },
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Variants (Size & Pricing)',
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              TextButton.icon(
                                onPressed: _showAddSizeDialog,
                                icon: const Icon(Icons.add),
                                label: const Text('Add Size'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Select size variants available for this garment. Each variant tracks independent stock, cost price, and barcodes.',
                            style: TextStyle(color: Colors.grey, fontSize: 13),
                          ),
                          const SizedBox(height: 16),
                          ..._availableSizes.map((s) => _buildVariantCard(s)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 80),
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
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: isSelected ? theme.colorScheme.primary : Colors.transparent,
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
        subtitle: isSelected
            ? Text(
                'MRP / Selling: ₹${_priceCtrls[size]?.text ?? "0"} • Stock: ${_qtyCtrls[size]?.text ?? "0"}',
                style: TextStyle(
                  color: theme.colorScheme.primary,
                  fontSize: 13,
                ),
              )
            : null,
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
                            labelText: 'Selling Price (MRP) *',
                            prefixIcon: Icon(Icons.currency_rupee),
                            border: OutlineInputBorder(),
                          ),
                          validator: (val) {
                            if (!isSelected) return null;
                            final price = double.tryParse(val ?? '');
                            if (price == null || price < 0) {
                              return 'Invalid selling price';
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextFormField(
                          controller: _costPriceCtrls[size],
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Cost Price (Purchase)',
                            prefixIcon: Icon(Icons.shopping_bag_outlined),
                            border: OutlineInputBorder(),
                            helperText: 'For gross margin tracking',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _qtyCtrls[size],
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Available Stock Qty *',
                            prefixIcon: Icon(Icons.inventory_2_outlined),
                            border: OutlineInputBorder(),
                          ),
                          validator: (val) {
                            if (!isSelected) return null;
                            final qty = int.tryParse(val ?? '');
                            if (qty == null || qty < 0) return 'Invalid qty';
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextFormField(
                          controller: _reorderLevelCtrls[size],
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Low Stock Alert Level',
                            prefixIcon: Icon(Icons.warning_amber_outlined),
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _barcodeCtrls[size],
                    decoration: InputDecoration(
                      labelText: 'Barcode *',
                      prefixIcon: const Icon(Icons.qr_code),
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        tooltip: 'Generate fresh barcode',
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
                      labelText: 'SKU Code',
                      prefixIcon: const Icon(Icons.label_outline),
                      border: const OutlineInputBorder(),
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
            labelText: 'Size Label (e.g. 32, 34, Free Size)',
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
                  _costPriceCtrls[newSize] = TextEditingController(text: '0');
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
        const SnackBar(content: Text('Please fix errors in the form')),
      );
      return;
    }

    final variants = <ProductVariant>[];
    final currentBarcodes = <String>{};

    for (var s in _availableSizes) {
      if (_selectedSizes[s] == true) {
        final barcode = _barcodeCtrls[s]!.text.trim();
        if (currentBarcodes.contains(barcode)) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Duplicate barcode detected: $barcode')),
          );
          return;
        }
        currentBarcodes.add(barcode);

        variants.add(
          ProductVariant(
            size: s,
            price: double.tryParse(_priceCtrls[s]!.text) ?? 0.0,
            costPrice: double.tryParse(_costPriceCtrls[s]?.text ?? '') ?? 0.0,
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

    if (!await _confirmSharedCode()) return;
    if (!mounted) return;

    final isNew = widget.existingProduct == null;
    final productId = widget.existingProduct?.id ?? _uuid.v4();

    final rate = GstTreatment.attractsTax(_gstTreatment)
        ? (_isCustomRate
              ? (double.tryParse(_customRateCtrl.text.trim()) ?? 0.0)
              : _selectedGstRate)
        : 0.0;

    final cess = double.tryParse(_cessCtrl.text.trim()) ?? 0.0;

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
      hsn: _hsnCtrl.text.trim(),
      uqc: _uqc,
      gstTreatment: _gstTreatment,
      gstRate: rate,
      cessRate: cess,
      gstRateConfigId: _selectedRateConfigId,
      variants: variants,
    );

    final repo = ref.read(storageRepositoryProvider);
    if (isNew) {
      await repo.saveProduct(product);
    } else {
      await repo.saveProductWithStockAudit(
        product,
        performedBy: 'Product form edit',
        reason: 'Updated variant specifications',
      );
    }

    await repo.saveHistory(
      ActionHistory(
        id: Ids.generate(),
        barcode: product.variants.first.barcode,
        productName: product.productName,
        action: isNew ? 'Created Product' : 'Updated Product',
        date: DateTime.now(),
      ),
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Product ${isNew ? "created" : "updated"} successfully.'),
      ),
    );
    Navigator.pop(context, true);
  }
}
