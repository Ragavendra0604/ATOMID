import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:atomid/data/models/product_model.dart';

class CartItem {
  final Product product;
  final ProductVariant variant;
  int quantity;

  CartItem({required this.product, required this.variant, this.quantity = 1});

  double get total => variant.price * quantity;

  String get displayName => '${product.productName} (${variant.size})';
}

class CartNotifier extends Notifier<List<CartItem>> {
  @override
  List<CartItem> build() {
    return [];
  }

  void addItem(Product product, ProductVariant variant) {
    // Check if already in cart
    final existingIndex = state.indexWhere(
      (item) => item.variant.barcode == variant.barcode,
    );

    if (existingIndex >= 0) {
      // Increase quantity
      final existing = state[existingIndex];
      if (existing.quantity < variant.quantity) {
        final updated = List<CartItem>.from(state);
        updated[existingIndex].quantity++;
        state = updated;
      }
    } else {
      if (variant.quantity <= 0) return;
      state = [...state, CartItem(product: product, variant: variant)];
    }
  }

  void removeItem(String barcode) {
    state = state.where((item) => item.variant.barcode != barcode).toList();
  }

  void updateQuantity(String barcode, int newQty) {
    if (newQty <= 0) {
      removeItem(barcode);
      return;
    }

    final index = state.indexWhere((item) => item.variant.barcode == barcode);
    if (index >= 0) {
      final item = state[index];
      if (newQty > item.variant.quantity) return; // Cannot exceed stock
      final updated = List<CartItem>.from(state);
      updated[index].quantity = newQty;
      state = updated;
    }
  }

  void clearCart() {
    state = [];
  }

  double get subtotal => state.fold(0.0, (sum, item) => sum + item.total);

  int get totalItems => state.fold(0, (sum, item) => sum + item.quantity);

  /// Validates that no cart item exceeds available stock
  String? validateStock() {
    for (var item in state) {
      if (item.quantity > item.variant.quantity) {
        return '${item.displayName}: only ${item.variant.quantity} available, but ${item.quantity} in cart.';
      }
    }
    return null;
  }
}

final cartProvider = NotifierProvider<CartNotifier, List<CartItem>>(() {
  return CartNotifier();
});
