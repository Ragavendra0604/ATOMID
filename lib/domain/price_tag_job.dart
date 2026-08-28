import 'package:atomid/data/models/product_model.dart';

/// One product variant and how many tags of it to print.
///
/// The bulk generator could print a single product's variants only, so the
/// product was passed once alongside a flat list of variants. Printing
/// several products onto the same sheet — the whole point of filling a sheet
/// before starting a new one — means every tag has to carry its own product.
class PriceTagLine {
  const PriceTagLine({
    required this.product,
    required this.variant,
    required this.quantity,
  });

  final Product product;
  final ProductVariant variant;
  final int quantity;
}
