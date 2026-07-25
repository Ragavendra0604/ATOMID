import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:atomid/data/models/supplier_model.dart';
import 'package:atomid/data/models/product_model.dart';
import 'package:atomid/data/models/purchase_model.dart';
import 'package:atomid/presentation/providers/provider_refresh_helper.dart';
import 'package:atomid/presentation/providers/app_providers.dart';
import 'package:atomid/core/utils/responsive.dart';

class PurchaseFormScreen extends ConsumerStatefulWidget {
  const PurchaseFormScreen({super.key});

  @override
  ConsumerState<PurchaseFormScreen> createState() => _PurchaseFormScreenState();
}

class _PurchaseFormScreenState extends ConsumerState<PurchaseFormScreen> {
  Supplier? _selectedSupplier;
  final _notesCtrl = TextEditingController();
  final _discountCtrl = TextEditingController(text: '0');
  final _taxCtrl = TextEditingController(text: '0');
  bool _isProcessing = false;
  String _status = 'Draft';
  DateTime? _expectedDeliveryDate;

  // Line items
  final List<_LineItem> _lineItems = [];

  @override
  void dispose() {
    _notesCtrl.dispose();
    _discountCtrl.dispose();
    _taxCtrl.dispose();
    for (var item in _lineItems) {
      item.dispose();
    }
    super.dispose();
  }

  double get _subtotal =>
      _lineItems.fold(0.0, (sum, item) => sum + item.lineTotal);

  double get _discount => double.tryParse(_discountCtrl.text) ?? 0;
  double get _tax => double.tryParse(_taxCtrl.text) ?? 0;

  double get _grandTotal {
    final sub = _subtotal;
    final afterDiscount = sub - _discount;
    return (afterDiscount + (afterDiscount * (_tax / 100))).clamp(
      0,
      double.infinity,
    );
  }

  void _calculateTotals() {
    setState(() {});
  }

  void _addLineItem() {
    setState(() {
      _lineItems.add(_LineItem());
    });
  }

  void _removeLineItem(int index) {
    setState(() {
      _lineItems[index].dispose();
      _lineItems.removeAt(index);
    });
  }

  Future<void> _savePurchase() async {
    // Validations
    if (_selectedSupplier == null) {
      _showError('Please select a supplier');
      return;
    }
    if (_lineItems.isEmpty) {
      _showError('Please add at least one item');
      return;
    }

    // Validate each line item
    for (var i = 0; i < _lineItems.length; i++) {
      final item = _lineItems[i];
      if (item.selectedProduct == null || item.selectedVariant == null) {
        _showError('Line ${i + 1}: Please select a product and variant');
        return;
      }
      final qty = int.tryParse(item.qtyCtrl.text) ?? 0;
      if (qty <= 0) {
        _showError('Line ${i + 1}: Quantity must be greater than 0');
        return;
      }
      final costPrice = double.tryParse(item.costPriceCtrl.text) ?? 0;
      if (costPrice < 0) {
        _showError('Line ${i + 1}: Cost price cannot be negative');
        return;
      }
    }

    setState(() => _isProcessing = true);

    try {
      final repo = ref.read(storageRepositoryProvider);
      final purchaseNumber = repo.getNextPurchaseNumber();
      final now = DateTime.now();

      final purchaseItems = _lineItems.map((item) {
        final qty = int.tryParse(item.qtyCtrl.text) ?? 0;
        final costPrice = double.tryParse(item.costPriceCtrl.text) ?? 0;
        return PurchaseItem(
          productId: item.selectedProduct!.id,
          productName: item.selectedProduct!.productName,
          variantBarcode: item.selectedVariant!.barcode,
          variantSize: item.selectedVariant!.size,
          sku: item.selectedVariant!.sku,
          quantity: qty,
          costPrice: costPrice,
          sellingPrice: item.selectedVariant!.price,
          lineTotal: costPrice * qty,
        );
      }).toList();

      final purchase = Purchase(
        id: now.millisecondsSinceEpoch.toString(),
        purchaseNumber: purchaseNumber,
        supplierId: _selectedSupplier!.id,
        supplierName: _selectedSupplier!.supplierName,
        purchaseDate: now,
        items: purchaseItems,
        subtotal: _subtotal,
        discount: _discount,
        tax: _tax,
        grandTotal: _grandTotal,
        notes: _notesCtrl.text.trim(),
        createdDate: now,
        status: _status,
        expectedDeliveryDate: _expectedDeliveryDate,
      );

      final service = ref.read(purchaseServiceProvider);
      await service.savePurchase(purchase, isNew: true);

      // Invalidate all relevant providers
      ProviderRefreshHelper.invalidatePurchaseProviders(ref);
      ProviderRefreshHelper.invalidateSupplierProviders(ref);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Purchase $purchaseNumber saved. Inventory updated.'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint('Purchase form error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Purchase could not be completed. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  @override
  Widget build(BuildContext context) {
    final activeSuppliers = ref.watch(activeSuppliersProvider);
    final products = ref.watch(productsProvider);
    final settings = ref.watch(settingsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('New Purchase'),
        actions: [
          if (_isProcessing)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            IconButton(icon: const Icon(Icons.save), tooltip: 'Save Purchase', onPressed: _savePurchase),
        ],
      ),
      body: Builder(
        builder: (context) {
          final supplierSelection = Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.grey.shade300),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Supplier Details',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<Supplier>(
                    decoration: const InputDecoration(
                      labelText: 'Select Supplier *',
                      border: OutlineInputBorder(),
                    ),
                    initialValue: _selectedSupplier,
                    items: activeSuppliers.map((s) {
                      return DropdownMenuItem(value: s, child: Text(s.supplierName));
                    }).toList(),
                    onChanged: (val) {
                      setState(() => _selectedSupplier = val);
                    },
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          decoration: const InputDecoration(
                            labelText: 'Status',
                            border: OutlineInputBorder(),
                          ),
                          initialValue: _status,
                          items: ['Draft', 'Issued', 'Received'].map((s) {
                            return DropdownMenuItem(value: s, child: Text(s));
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) setState(() => _status = val);
                          },
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: InkWell(
                          onTap: () async {
                            final date = await showDatePicker(
                              context: context,
                              initialDate: _expectedDeliveryDate ?? DateTime.now().add(const Duration(days: 7)),
                              firstDate: DateTime.now().subtract(const Duration(days: 365)),
                              lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
                            );
                            if (date != null) {
                              setState(() => _expectedDeliveryDate = date);
                            }
                          },
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'Expected Delivery',
                              border: OutlineInputBorder(),
                            ),
                            child: Text(
                              _expectedDeliveryDate == null
                                  ? 'Not Set'
                                  : '${_expectedDeliveryDate!.year}-${_expectedDeliveryDate!.month.toString().padLeft(2, '0')}-${_expectedDeliveryDate!.day.toString().padLeft(2, '0')}',
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );

          final lineItemsSection = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Items',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  ElevatedButton.icon(
                    onPressed: _addLineItem,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add Item'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_lineItems.isEmpty)
                Card(
                  child: const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(
                      child: Text('No items added yet. Click Add Item.'),
                    ),
                  ),
                )
              else
                ..._lineItems.asMap().entries.map((e) {
                  return _PurchaseLineItemCard(
                    index: e.key,
                    item: e.value,
                    products: products,
                    settings: settings,
                    onChanged: () => setState(() => _calculateTotals()),
                    onRemove: () => _removeLineItem(e.key),
                  );
                }),
            ],
          );

          final totalsSection = Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Summary',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const Divider(),
                  _summaryRow(
                    'Subtotal',
                    '${settings.currencySymbol}${_subtotal.toStringAsFixed(2)}',
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Tax (%)', style: TextStyle(fontSize: 16)),
                      SizedBox(
                        width: 100,
                        child: TextFormField(
                          controller: _taxCtrl,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.right,
                          decoration: const InputDecoration(
                            isDense: true,
                            contentPadding: EdgeInsets.all(8),
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (_) => _calculateTotals(),
                        ),
                      ),
                    ],
                  ),
                  const Divider(),
                  _summaryRow(
                    'Grand Total',
                    '${settings.currencySymbol}${_grandTotal.toStringAsFixed(2)}',
                    isBold: true,
                  ),
                ],
              ),
            ),
          );

          final notesSection = TextFormField(
            controller: _notesCtrl,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Notes (Optional)',
              prefixIcon: Icon(Icons.notes),
              border: OutlineInputBorder(),
            ),
          );

          final submitSection = SizedBox(
            width: double.infinity,
            height: 56,
            child: _isProcessing
                ? const Center(child: CircularProgressIndicator())
                : ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: _savePurchase,
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text(
                      'Save Purchase & Update Inventory',
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
          );

          return ResponsiveBuilder(
            mobileBuilder: (context) => SingleChildScrollView(
              padding: ResponsivePadding.getScreenPadding(context),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  supplierSelection,
                  const SizedBox(height: 16),
                  lineItemsSection,
                  const SizedBox(height: 16),
                  totalsSection,
                  const SizedBox(height: 16),
                  notesSection,
                  const SizedBox(height: 24),
                  submitSection,
                  const SizedBox(height: 32),
                ],
              ),
            ),
            tabletBuilder: (context) => SingleChildScrollView(
              padding: ResponsivePadding.getScreenPadding(context),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: ResponsiveBreakpoints.maxFormWidth,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 6,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            supplierSelection,
                            const SizedBox(height: 16),
                            lineItemsSection,
                            const SizedBox(height: 16),
                            notesSection,
                          ],
                        ),
                      ),
                      const SizedBox(width: 24),
                      Expanded(
                        flex: 4,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            totalsSection,
                            const SizedBox(height: 24),
                            submitSection,
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            desktopBuilder: (context) => SingleChildScrollView(
              padding: ResponsivePadding.getScreenPadding(context),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: ResponsiveBreakpoints.maxFormWidth,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 6,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            supplierSelection,
                            const SizedBox(height: 16),
                            lineItemsSection,
                            const SizedBox(height: 16),
                            notesSection,
                          ],
                        ),
                      ),
                      const SizedBox(width: 24),
                      Expanded(
                        flex: 4,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            totalsSection,
                            const SizedBox(height: 24),
                            submitSection,
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _summaryRow(String label, String value, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: isBold ? 20 : 16,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              color: isBold ? null : Colors.grey,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: isBold ? 20 : 16,
              fontWeight: FontWeight.bold,
              color: isBold ? Theme.of(context).colorScheme.primary : null,
            ),
          ),
        ],
      ),
    );
  }
}

/// Internal line item state helper
class _LineItem {
  Product? selectedProduct;
  ProductVariant? selectedVariant;
  final TextEditingController qtyCtrl = TextEditingController(text: '1');
  final TextEditingController costPriceCtrl = TextEditingController(text: '0');

  double get lineTotal {
    final qty = int.tryParse(qtyCtrl.text) ?? 0;
    final cost = double.tryParse(costPriceCtrl.text) ?? 0;
    return qty * cost;
  }

  void dispose() {
    qtyCtrl.dispose();
    costPriceCtrl.dispose();
  }
}

class _PurchaseLineItemCard extends StatelessWidget {
  final int index;
  final _LineItem item;
  final List<Product> products;
  final dynamic settings;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  const _PurchaseLineItemCard({
    required this.index,
    required this.item,
    required this.products,
    required this.settings,
    required this.onChanged,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: Theme.of(context).colorScheme.primary.withAlpha(60),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Item ${index + 1}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                  onPressed: onRemove,
                ),
              ],
            ),
            // Product dropdown
            DropdownButtonFormField<Product>(
              initialValue: item.selectedProduct,
              isExpanded: true,
              hint: const Text('Select product'),
              decoration: const InputDecoration(
                isDense: true,
                prefixIcon: Icon(Icons.inventory_2),
                border: OutlineInputBorder(),
              ),
              items: products.map((p) {
                return DropdownMenuItem(
                  value: p,
                  child: Text('${p.productName} (${p.productCode})'),
                );
              }).toList(),
              onChanged: (p) {
                item.selectedProduct = p;
                item.selectedVariant = null;
                onChanged();
              },
            ),
            const SizedBox(height: 8),
            // Variant dropdown
            if (item.selectedProduct != null)
              DropdownButtonFormField<ProductVariant>(
                initialValue: item.selectedVariant,
                isExpanded: true,
                hint: const Text('Select variant'),
                decoration: const InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.straighten),
                  border: OutlineInputBorder(),
                ),
                items: item.selectedProduct!.variants.map((v) {
                  return DropdownMenuItem(
                    value: v,
                    child: Text(
                      'Size: ${v.size} | Qty: ${v.quantity} | ${settings.currencySymbol}${v.price.toStringAsFixed(0)}',
                    ),
                  );
                }).toList(),
                onChanged: (v) {
                  item.selectedVariant = v;
                  if (v != null) {
                    item.costPriceCtrl.text = v.price.toStringAsFixed(2);
                  }
                  onChanged();
                },
              ),
            const SizedBox(height: 8),
            // Quantity & Cost Price
            if (item.selectedVariant != null)
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: item.qtyCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Qty',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => onChanged(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: item.costPriceCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Cost Price',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => onChanged(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.primary.withAlpha(20),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${settings.currencySymbol}${item.lineTotal.toStringAsFixed(2)}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
