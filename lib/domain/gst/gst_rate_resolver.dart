import 'package:atomid/domain/gst/gst_treatment.dart';

/// Represents a GST Rate configuration in the rate book with effective dates.
class GstRateEntry {
  final String id;
  final String rateName;
  final double rate; // e.g. 5.0, 12.0, 18.0
  final double cessRate; // default 0.0
  final DateTime effectiveFrom;
  final DateTime? effectiveTo;
  final String description;

  const GstRateEntry({
    required this.id,
    required this.rateName,
    required this.rate,
    this.cessRate = 0.0,
    required this.effectiveFrom,
    this.effectiveTo,
    this.description = '',
  });

  /// True when this rate configuration applies to the given transaction date.
  bool isEffectiveOn(DateTime date) {
    if (date.isBefore(effectiveFrom)) return false;
    if (effectiveTo != null && date.isAfter(effectiveTo!)) return false;
    return true;
  }
}

/// Central date-aware GST Rate Book and resolver.
class GstRateResolver {
  /// Standard statutory Indian GST rate entries effective since the inception of GST (1 July 2017).
  static final DateTime gstInceptionDate = DateTime(2017, 7, 1);

  static final List<GstRateEntry> defaultRates = [
    GstRateEntry(
      id: 'gst_0',
      rateName: 'GST 0%',
      rate: 0.0,
      effectiveFrom: gstInceptionDate,
      description: 'Zero rate / Nil rated goods',
    ),
    GstRateEntry(
      id: 'gst_0_25',
      rateName: 'GST 0.25%',
      rate: 0.25,
      effectiveFrom: gstInceptionDate,
      description: 'Special rate (precious stones)',
    ),
    GstRateEntry(
      id: 'gst_3',
      rateName: 'GST 3%',
      rate: 3.0,
      effectiveFrom: gstInceptionDate,
      description: 'Special rate (gold, silver)',
    ),
    GstRateEntry(
      id: 'gst_5',
      rateName: 'GST 5%',
      rate: 5.0,
      effectiveFrom: gstInceptionDate,
      description: 'Garments and textile fabrics (standard lower slab)',
    ),
    GstRateEntry(
      id: 'gst_12',
      rateName: 'GST 12%',
      rate: 12.0,
      effectiveFrom: gstInceptionDate,
      description: 'Apparel and standard goods slab',
    ),
    GstRateEntry(
      id: 'gst_18',
      rateName: 'GST 18%',
      rate: 18.0,
      effectiveFrom: gstInceptionDate,
      description: 'Standard retail slab',
    ),
    GstRateEntry(
      id: 'gst_28',
      rateName: 'GST 28%',
      rate: 28.0,
      effectiveFrom: gstInceptionDate,
      description: 'Luxury / specific slab',
    ),
  ];

  /// Resolves the applicable GST rate for a product and transaction date.
  ///
  /// Returns a [GstRateResolution] with the resolved rates, or an error if
  /// the rate cannot be resolved safely.
  static GstRateResolution resolve({
    required String gstTreatment,
    required double? configuredRate,
    required double cessRate,
    String? rateConfigId,
    required DateTime transactionDate,
    List<GstRateEntry>? customRateBook,
  }) {
    if (gstTreatment == GstTreatment.unconfigured) {
      return const GstRateResolution.unresolved(
        'Product tax treatment is unconfigured.',
      );
    }

    if (gstTreatment == GstTreatment.nilRated ||
        gstTreatment == GstTreatment.exempt ||
        gstTreatment == GstTreatment.nonGst ||
        gstTreatment == GstTreatment.zeroRated) {
      return GstRateResolution.resolved(
        rate: 0.0,
        cessRate: 0.0,
        gstTreatment: gstTreatment,
      );
    }

    // Must be TAXABLE: verify rate is configured
    if (configuredRate == null) {
      return const GstRateResolution.unresolved(
        'Taxable product has no GST rate configured.',
      );
    }

    final rateBook = customRateBook ?? defaultRates;

    // Check if a specific config ID was provided
    if (rateConfigId != null && rateConfigId.isNotEmpty) {
      final match = rateBook.cast<GstRateEntry?>().firstWhere(
        (r) => r?.id == rateConfigId,
        orElse: () => null,
      );
      if (match == null) {
        return GstRateResolution.unresolved(
          'Configured rate ID "$rateConfigId" not found in rate book.',
        );
      }
      if (!match.isEffectiveOn(transactionDate)) {
        return GstRateResolution.unresolved(
          'GST rate configuration "${match.rateName}" is not effective on transaction date (${transactionDate.toIso8601String().split('T').first}).',
        );
      }
      return GstRateResolution.resolved(
        rate: match.rate,
        cessRate: match.cessRate > 0 ? match.cessRate : cessRate,
        gstTreatment: GstTreatment.taxable,
        configId: match.id,
      );
    }

    // Match by rate percentage
    final matchingRates = rateBook.where(
      (r) => (r.rate - configuredRate).abs() < 0.001,
    );

    if (matchingRates.isEmpty) {
      // If a custom rate not in book was given, check date against inception
      if (transactionDate.isBefore(gstInceptionDate)) {
        return GstRateResolution.unresolved(
          'Transaction date is before GST implementation date (01-Jul-2017).',
        );
      }
      return GstRateResolution.resolved(
        rate: configuredRate,
        cessRate: cessRate,
        gstTreatment: GstTreatment.taxable,
      );
    }

    final effectiveMatch = matchingRates.cast<GstRateEntry?>().firstWhere(
      (r) => r != null && r.isEffectiveOn(transactionDate),
      orElse: () => null,
    );

    if (effectiveMatch == null) {
      return GstRateResolution.unresolved(
        'No GST rate configuration for $configuredRate% covers transaction date (${transactionDate.toIso8601String().split('T').first}).',
      );
    }

    return GstRateResolution.resolved(
      rate: effectiveMatch.rate,
      cessRate: cessRate,
      gstTreatment: GstTreatment.taxable,
      configId: effectiveMatch.id,
    );
  }
}

class GstRateResolution {
  final bool isResolved;
  final double rate;
  final double cessRate;
  final String gstTreatment;
  final String? configId;
  final String? errorMessage;

  const GstRateResolution.resolved({
    required this.rate,
    required this.cessRate,
    required this.gstTreatment,
    this.configId,
  }) : isResolved = true,
       errorMessage = null;

  const GstRateResolution.unresolved(this.errorMessage)
    : isResolved = false,
      rate = 0.0,
      cessRate = 0.0,
      gstTreatment = GstTreatment.unconfigured,
      configId = null;
}
