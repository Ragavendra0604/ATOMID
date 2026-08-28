/// Statutory GST treatments under Indian GST law.
///
/// Distinguishes UNCONFIGURED (missing setup) from 0% Taxable, Nil Rated,
/// Exempt, and Non-GST supplies.
class GstTreatment {
  /// Regular taxable supply attracting configured GST rate (e.g. 5%, 12%, 18%, 28%).
  static const String taxable = 'TAXABLE';

  /// Goods with 0% statutory tariff rate (Schedule I of Notification No. 1/2017).
  static const String nilRated = 'NIL_RATED';

  /// Goods exempt from tax under Section 11 of CGST Act (Notification No. 2/2017).
  static const String exempt = 'EXEMPT';

  /// Goods outside the scope of GST under Section 9(2) (e.g. alcohol, petroleum).
  static const String nonGst = 'NON_GST';

  /// Supplies to SEZ or exports under Section 16 of IGST Act (zero-rated with/without LUT).
  static const String zeroRated = 'ZERO_RATED';

  /// Explicitly unconfigured product. Must NEVER be treated as 0% tax.
  static const String unconfigured = 'UNCONFIGURED';

  static const List<String> all = [
    taxable,
    nilRated,
    exempt,
    nonGst,
    zeroRated,
    unconfigured,
  ];

  static const List<String> selectable = [taxable, nilRated, exempt, nonGst];

  static String label(String? treatment) {
    switch (treatment?.toUpperCase()) {
      case taxable:
        return 'Taxable';
      case nilRated:
        return 'Nil Rated (0%)';
      case exempt:
        return 'Exempt';
      case nonGst:
        return 'Non-GST';
      case zeroRated:
        return 'Zero Rated (Export/SEZ)';
      case unconfigured:
      default:
        return 'Unconfigured';
    }
  }

  /// True when the treatment subjects the supply to tax calculations at the rate.
  static bool attractsTax(String? treatment) {
    return treatment == taxable;
  }

  /// True when the treatment is known and safe for billing.
  static bool isConfigured(String? treatment) {
    return treatment != null &&
        treatment != unconfigured &&
        all.contains(treatment);
  }
}
