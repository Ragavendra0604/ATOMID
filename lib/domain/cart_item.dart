import 'package:atomid/core/utils/formatters.dart';
import 'package:atomid/data/models/product_model.dart';

/// One line in the basket: a product variant and how many of it.
///
/// This lives in `domain/` rather than beside `CartNotifier` in
/// `presentation/` because [SaleService] takes it as checkout input — a
/// domain service reaching up into the presentation layer for a type is the
/// one layering inversion this project had.
class CartItem {
  final Product product;
  final ProductVariant variant;
  final int quantity;

  const CartItem({
    required this.product,
    required this.variant,
    this.quantity = 1,
  });

  CartItem withQuantity(int value) =>
      CartItem(product: product, variant: variant, quantity: value);

  double get total => Fmt.round2(variant.price * quantity);

  /// How the line reads in the basket and at checkout — the same colour and
  /// size the bill will carry, so what the cashier confirms on screen is
  /// what the customer reads on the receipt.
  String get displayName => '${product.displayName} (${variant.size})';
}
