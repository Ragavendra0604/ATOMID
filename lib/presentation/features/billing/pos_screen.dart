import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:atomid/data/models/product_model.dart';
import 'package:atomid/presentation/providers/app_providers.dart';
import 'package:atomid/presentation/providers/cart_notifier.dart';
import 'package:atomid/presentation/features/billing/checkout_screen.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:atomid/core/utils/responsive.dart';
import 'package:atomid/presentation/widgets/adaptive_dialog.dart';
import 'package:atomid/presentation/features/sync/sync_status_widget.dart';

class PosScreen extends ConsumerStatefulWidget {
  const PosScreen({super.key});

  @override
  ConsumerState<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends ConsumerState<PosScreen> {
  final _searchController = TextEditingController();
  final MobileScannerController _scannerController = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _isScanning = false;

  @override
  void dispose() {
    _searchController.dispose();
    _scannerController.dispose();
    super.dispose();
  }

  void _handleBarcodeFound(BarcodeCapture capture) {
    if (!_isScanning) return;

    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isNotEmpty) {
      final String? barcode = barcodes.first.rawValue;
      if (barcode != null && barcode.isNotEmpty) {
        setState(() {
          _isScanning = false;
        });
        _searchController.text = barcode;
        _processSearch(barcode);
      }
    }
  }

  void _processSearch(String query) {
    if (query.isEmpty) return;

    final repo = ref.read(storageRepositoryProvider);
    final products = repo.searchProducts(query);

    if (products.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No product found for this search/barcode.'),
        ),
      );
      return;
    }

    if (products.length == 1) {
      // Find the exact variant if the query matches a barcode
      final product = products.first;
      final exactVariantIndex = product.variants.indexWhere(
        (v) => v.barcode == query,
      );

      if (exactVariantIndex != -1) {
        // Exact barcode match, add directly to cart
        final variant = product.variants[exactVariantIndex];
        _addToCart(product, variant);
      } else {
        // Multiple variants or search match, show selection dialog
        _showVariantSelectionDialog(product);
      }
    } else {
      // Multiple products found, show product selection dialog
      _showProductSelectionDialog(products);
    }

    _searchController.clear();
  }

  void _addToCart(Product product, ProductVariant variant) {
    if (variant.quantity <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${product.productName} (${variant.size}) is OUT OF STOCK.',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    ref.read(cartProvider.notifier).addItem(product, variant);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Added ${product.productName} (${variant.size}) to cart.',
        ),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 1),
      ),
    );
  }

  void _showVariantSelectionDialog(Product product) {
    showDialog(
      context: context,
      builder: (context) {
        return AdaptiveDialog(
          title: Text('Select Variant: ${product.productName}'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: product.variants.length,
              itemBuilder: (context, index) {
                final variant = product.variants[index];
                final isOutOfStock = variant.quantity <= 0;
                return ListTile(
                  title: Text('Size: ${variant.size} - ₹${variant.price}'),
                  subtitle: Text(
                    'Stock: ${variant.quantity} | Barcode: ${variant.barcode}',
                  ),
                  trailing: isOutOfStock
                      ? const Text(
                          'Out of Stock',
                          style: TextStyle(color: Colors.red),
                        )
                      : const Icon(
                          Icons.add_shopping_cart,
                          color: Colors.green,
                        ),
                  onTap: isOutOfStock
                      ? null
                      : () {
                          Navigator.pop(context);
                          _addToCart(product, variant);
                        },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  void _showProductSelectionDialog(List<Product> products) {
    showDialog(
      context: context,
      builder: (context) {
        return AdaptiveDialog(
          title: const Text('Select Product'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: products.length,
              itemBuilder: (context, index) {
                final product = products[index];
                return ListTile(
                  title: Text(product.productName),
                  subtitle: Text(
                    '${product.variants.length} variants available',
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _showVariantSelectionDialog(product);
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cartItems = ref.watch(cartProvider);
    final settings = ref.watch(settingsProvider);
    final allProducts = ref.watch(productsProvider);

    final subtotal = ref.watch(cartProvider.notifier).subtotal;
    // For now, no complex tax/discount in cart notifier, just simple summary
    // V1.2: settings.taxMode is available but tax calculation is 0 by default.
    final taxAmount = (subtotal * settings.taxRate) / 100;
    final grandTotal = subtotal + taxAmount;

    return Scaffold(
      appBar: AppBar(
        title: const Text('POS Billing'),
        actions: [
          const SyncStatusWidget(),
          if (cartItems.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep, color: Colors.red),
              onPressed: () {
                ref.read(cartProvider.notifier).clearCart();
              },
              tooltip: 'Clear Cart',
            ),
        ],
      ),
      body: ResponsiveBuilder(
        mobileBuilder: (context) => Column(
          children: [
            _buildSearchAndScan(),
            if (_isScanning) _buildScannerView(),
            Expanded(child: _buildCartItems(cartItems, settings)),
            if (cartItems.isNotEmpty)
              _buildTotalsAndCheckout(
                cartItems,
                settings,
                subtotal,
                taxAmount,
                grandTotal,
              ),
          ],
        ),
        tabletBuilder: (context) => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 5,
              child: Column(
                children: [
                  _buildSearchAndScan(),
                  if (_isScanning) _buildScannerView(),
                  Expanded(child: _buildProductGrid(allProducts)),
                ],
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              flex: 5,
              child: Column(
                children: [
                  Expanded(child: _buildCartItems(cartItems, settings)),
                  if (cartItems.isNotEmpty)
                    _buildTotalsAndCheckout(
                      cartItems,
                      settings,
                      subtotal,
                      taxAmount,
                      grandTotal,
                    ),
                ],
              ),
            ),
          ],
        ),
        desktopBuilder: (context) => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 6,
              child: Column(
                children: [
                  _buildSearchAndScan(),
                  if (_isScanning) _buildScannerView(),
                  Expanded(child: _buildProductGrid(allProducts)),
                ],
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              flex: 4,
              child: Column(
                children: [
                  Expanded(child: _buildCartItems(cartItems, settings)),
                  if (cartItems.isNotEmpty)
                    _buildTotalsAndCheckout(
                      cartItems,
                      settings,
                      subtotal,
                      taxAmount,
                      grandTotal,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductGrid(List<Product> products) {
    if (products.isEmpty) {
      return const Center(child: Text('No products available'));
    }
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 150,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: products.length,
      itemBuilder: (context, index) {
        final p = products[index];
        return InkWell(
          onTap: () {
            if (p.variants.length == 1) {
              _addToCart(p, p.variants.first);
            } else {
              _showVariantSelectionDialog(p);
            }
          },
          child: Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.inventory_2,
                    size: 32,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    p.productName,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSearchAndScan() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Theme.of(context).cardColor,
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search or scan barcode...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onSubmitted: _processSearch,
            ),
          ),
          const SizedBox(width: 12),
          Container(
            decoration: BoxDecoration(
              color: _isScanning
                  ? Colors.red
                  : Theme.of(context).colorScheme.primary,
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: Icon(
                _isScanning ? Icons.stop : Icons.qr_code_scanner,
                color: Colors.white,
              ),
              onPressed: () {
                setState(() {
                  _isScanning = !_isScanning;
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScannerView() {
    return SizedBox(
      height: 200,
      child: MobileScanner(
        controller: _scannerController,
        onDetect: _handleBarcodeFound,
      ),
    );
  }

  Widget _buildCartItems(List cartItems, dynamic settings) {
    if (cartItems.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.shopping_cart_outlined, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'Cart is empty',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      itemCount: cartItems.length,
      itemBuilder: (context, index) {
        final item = cartItems[index];
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.product.productName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Size: ${item.variant.size} | ${settings.currencySymbol}${item.variant.price}',
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                // Quantity Controls
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: () {
                        ref
                            .read(cartProvider.notifier)
                            .updateQuantity(
                              item.variant.barcode,
                              item.quantity - 1,
                            );
                      },
                    ),
                    Text(
                      '${item.quantity}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      onPressed: () {
                        ref
                            .read(cartProvider.notifier)
                            .updateQuantity(
                              item.variant.barcode,
                              item.quantity + 1,
                            );
                      },
                    ),
                  ],
                ),
                const SizedBox(width: 8),
                Text(
                  '${settings.currencySymbol}${item.total}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTotalsAndCheckout(
    List cartItems,
    dynamic settings,
    double subtotal,
    double taxAmount,
    double grandTotal,
  ) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 10,
            offset: Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Subtotal:', style: TextStyle(fontSize: 16)),
                Text(
                  '${settings.currencySymbol}$subtotal',
                  style: const TextStyle(fontSize: 16),
                ),
              ],
            ),
            if (taxAmount > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Tax (${settings.taxRate}%):',
                      style: const TextStyle(fontSize: 16),
                    ),
                    Text(
                      '${settings.currencySymbol}$taxAmount',
                      style: const TextStyle(fontSize: 16),
                    ),
                  ],
                ),
              ),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Grand Total:',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                Text(
                  '${settings.currencySymbol}$grandTotal',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: () {
                  final validationError = ref
                      .read(cartProvider.notifier)
                      .validateStock();
                  if (validationError != null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(validationError),
                        backgroundColor: Colors.red,
                      ),
                    );
                    return;
                  }
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CheckoutScreen(
                        subtotal: subtotal,
                        taxAmount: taxAmount,
                        grandTotal: grandTotal,
                      ),
                    ),
                  );
                },
                child: const Text(
                  'Proceed to Checkout',
                  style: TextStyle(fontSize: 18),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
