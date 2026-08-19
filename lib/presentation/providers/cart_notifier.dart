import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:atomid/core/utils/formatters.dart';
import 'package:atomid/data/models/product_model.dart';
import 'package:atomid/domain/cart_item.dart';

// `CartItem` moved to `domain/cart_item.dart`. It is re-exported here so the
// screens that already import this file keep working, and so the cart's type
// stays discoverable from the notifier that manages it.
export 'package:atomid/domain/cart_item.dart' show CartItem;

class CartNotifier extends Notifier<List<CartItem>> {
  @override
  List<CartItem> build() => const [];

  /// Adds one unit. Returns false when stock is exhausted, so the caller can
  /// explain why nothing happened instead of silently ignoring the tap.
  bool addItem(Product product, ProductVariant variant) {
    if (variant.quantity <= 0) return false;

    final index = state.indexWhere(
      (item) => item.variant.barcode == variant.barcode,
    );

    if (index < 0) {
      state = [...state, CartItem(product: product, variant: variant)];
      return true;
    }

    final existing = state[index];
    if (existing.quantity >= variant.quantity) return false;

    final updated = [...state];
    updated[index] = existing.withQuantity(existing.quantity + 1);
    state = updated;
    return true;
  }

  void removeItem(String barcode) {
    state = state.where((item) => item.variant.barcode != barcode).toList();
  }

  bool updateQuantity(String barcode, int newQuantity) {
    if (newQuantity <= 0) {
      removeItem(barcode);
      return true;
    }

    final index = state.indexWhere((item) => item.variant.barcode == barcode);
    if (index < 0) return false;

    final item = state[index];
    if (newQuantity > item.variant.quantity) return false;

    final updated = [...state];
    updated[index] = item.withQuantity(newQuantity);
    state = updated;
    return true;
  }

  void clearCart() => state = const [];

  double get subtotal =>
      Fmt.round2(state.fold(0.0, (sum, item) => sum + item.total));

  int get totalItems => state.fold(0, (sum, item) => sum + item.quantity);

  /// Names the first line that now exceeds what is on the shelf. Stock can
  /// move underneath a basket that has been open for a while.
  String? validateStock() {
    for (final item in state) {
      if (item.quantity > item.variant.quantity) {
        return '${item.displayName}: only ${item.variant.quantity} available, '
            'but ${item.quantity} in the basket.';
      }
    }
    return null;
  }
}

final cartProvider = NotifierProvider<CartNotifier, List<CartItem>>(
  CartNotifier.new,
);
