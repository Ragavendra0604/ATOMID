import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:atomid/data/models/product_model.dart';
import 'package:atomid/presentation/providers/app_providers.dart';
import 'package:atomid/core/utils/responsive.dart';
import 'package:atomid/core/utils/app_error.dart';

class StockInScreen extends ConsumerStatefulWidget {
  final Product? preselectedProduct;
  final ProductVariant? preselectedVariant;

  const StockInScreen({
    super.key,
    this.preselectedProduct,
    this.preselectedVariant,
  });

  @override
  ConsumerState<StockInScreen> createState() => _StockInScreenState();
}

class _StockInScreenState extends ConsumerState<StockInScreen> {
  Product? _selectedProduct;
  ProductVariant? _selectedVariant;
  final _qtyController = TextEditingController();
  String _selectedReason = 'Purchase';
  bool _isLoading = false;

  final List<String> _reasons = [
    'Purchase',
    'Return',
    'Adjustment',
    'Manual Entry',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.preselectedProduct != null) {
      _selectedProduct = widget.preselectedProduct;
      _selectedVariant = widget.preselectedVariant;
    }
  }

  @override
  void dispose() {
    _qtyController.dispose();
    super.dispose();
  }

  Future<void> _performStockIn() async {
    if (_selectedProduct == null || _selectedVariant == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a product and variant')),
      );
      return;
    }

    final qty = int.tryParse(_qtyController.text.trim());
    if (qty == null || qty <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid quantity greater than 0'),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final repo = ref.read(storageRepositoryProvider);
      await repo.performStockIn(
        productId: _selectedProduct!.id,
        variantBarcode: _selectedVariant!.barcode,
        quantity: qty,
        reason: _selectedReason,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Stock In: +$qty for ${_selectedProduct!.productName} (${_selectedVariant!.size})',
            ),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e, stack) {
      debugPrint('Stock in error: $e\n$stack');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              describeError(
                e,
                fallback: 'Could not add stock. Please try again.',
              ),
            ),
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
    final products = ref.watch(productsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Stock In')),
      body: SingleChildScrollView(
        padding: ResponsivePadding.getScreenPadding(context),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: ResponsiveBreakpoints.maxFormWidth,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Info banner
                Card(
                  color: Colors.green.withAlpha(30),
                  child: const Padding(
                    padding: EdgeInsets.all(12.0),
                    child: Row(
                      children: [
                        Icon(Icons.add_box_outlined, color: Colors.green),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Add stock to your inventory. Select a product and variant, then enter the quantity to add.',
                            style: TextStyle(fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Product Selection
                const Text(
                  'Select Product',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<Product>(
                  initialValue: _selectedProduct,
                  isExpanded: true,
                  hint: const Text('Choose a product'),
                  decoration: const InputDecoration(
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
                    setState(() {
                      _selectedProduct = p;
                      _selectedVariant = null;
                    });
                  },
                ),
                const SizedBox(height: 20),

                // Variant Selection
                if (_selectedProduct != null) ...[
                  const Text(
                    'Select Variant',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<ProductVariant>(
                    initialValue: _selectedVariant,
                    isExpanded: true,
                    hint: const Text('Choose a variant'),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.straighten),
                      border: OutlineInputBorder(),
                    ),
                    items: _selectedProduct!.variants.map((v) {
                      return DropdownMenuItem(
                        value: v,
                        child: Text(
                          'Size: ${v.size} | Qty: ${v.quantity} | ${v.barcode}',
                        ),
                      );
                    }).toList(),
                    onChanged: (v) => setState(() => _selectedVariant = v),
                  ),
                  const SizedBox(height: 20),
                ],

                // Current Stock Info
                if (_selectedVariant != null) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Current Stock Info',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const Divider(),
                          _infoRow('Product', _selectedProduct!.productName),
                          _infoRow('Size', _selectedVariant!.size),
                          _infoRow(
                            'Current Qty',
                            _selectedVariant!.quantity.toString(),
                          ),
                          _infoRow(
                            'Total Stock In',
                            _selectedVariant!.stockIn.toString(),
                          ),
                          _infoRow(
                            'Reorder Level',
                            _selectedVariant!.reorderLevel.toString(),
                          ),
                          _infoRow('Barcode', _selectedVariant!.barcode),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Quantity
                  const Text(
                    'Quantity to Add',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _qtyController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.add),
                      hintText: 'Enter quantity',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Reason
                  const Text(
                    'Reason',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedReason,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.description),
                      border: OutlineInputBorder(),
                    ),
                    items: _reasons.map((r) {
                      return DropdownMenuItem(value: r, child: Text(r));
                    }).toList(),
                    onChanged: (r) {
                      if (r != null) setState(() => _selectedReason = r);
                    },
                  ),
                  const SizedBox(height: 32),

                  // Submit
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: _isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: _performStockIn,
                            icon: const Icon(Icons.add_box),
                            label: const Text('Confirm Stock In'),
                          ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
