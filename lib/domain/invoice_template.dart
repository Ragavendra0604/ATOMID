/// The invoice designs the shop can choose between.
///
/// A template is presentation only. Every one of them renders the same stored
/// sale — the same quantities, taxable value, GST rates, CGST, SGST and total
/// payable — so changing the selection can never change what the customer is
/// charged.
enum InvoiceTemplate {
  /// Compact till-roll receipt, 58mm or 80mm. The counter default.
  thermal(
    id: 'THERMAL',
    label: 'Thermal Receipt',
    description: 'Compact 58mm / 80mm till roll. Fastest at the counter.',
  ),

  /// Clean A4 tax invoice: items, GST summary, amount in words.
  a4Professional(
    id: 'A4_PROFESSIONAL',
    label: 'A4 Professional',
    description: 'Full-page tax invoice with a clear CGST / SGST summary.',
  ),

  /// A4 with per-line tax columns as well as the summary, for a customer or
  /// accountant who wants the whole breakup.
  a4DetailedGst(
    id: 'A4_DETAILED_GST',
    label: 'A4 Detailed GST',
    description: 'Adds HSN and per-item CGST / SGST columns to the A4 sheet.',
  ),

  /// A4 with the tax columns stripped back to a plain shop bill.
  simpleRetail(
    id: 'SIMPLE_RETAIL',
    label: 'Simple Retail',
    description: 'Plain A4 bill: item, quantity, rate, amount, GST totals.',
  );

  const InvoiceTemplate({
    required this.id,
    required this.label,
    required this.description,
  });

  /// The value persisted in settings. Stable across renames of [label].
  final String id;
  final String label;
  final String description;

  /// True for the till roll, false for every sheet template.
  bool get isThermal => this == InvoiceTemplate.thermal;

  /// Prints per-item tax columns rather than only the summary.
  bool get showsLineTaxColumns => this == InvoiceTemplate.a4DetailedGst;

  /// Prints HSN against each item.
  bool get showsHsn => this == InvoiceTemplate.a4DetailedGst;

  /// The default for a new install, and the fallback for an unrecognised
  /// stored id.
  static const InvoiceTemplate fallback = InvoiceTemplate.thermal;

  /// Resolves a stored id. An id this build does not know — written by a
  /// newer version, or corrupted — resolves to [fallback] rather than
  /// throwing at the till.
  static InvoiceTemplate fromId(String? id) {
    for (final template in InvoiceTemplate.values) {
      if (template.id == id) return template;
    }
    return fallback;
  }
}
