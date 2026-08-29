import 'package:atomid/data/models/sale_model.dart';

/// One row of the customer-facing GST summary: every line on the bill that
/// carried the same GST rate, added together.
///
/// Nothing here recomputes tax. Each figure is a sum of the amounts the GST
/// engine already wrote onto the sale's snapshot lines at checkout, so a
/// template can only ever display what was charged.
class GstRateSummaryRow {
  /// The full GST rate for the group, e.g. 18 for an 18% line.
  final double gstRate;
  final double taxable;
  final double cgst;

  /// SGST or UTGST, whichever the engine recorded for this sale. The two
  /// never appear together on one document.
  final double stateGst;
  final double igst;
  final double cess;

  const GstRateSummaryRow({
    required this.gstRate,
    required this.taxable,
    required this.cgst,
    required this.stateGst,
    required this.igst,
    required this.cess,
  });

  /// The half-rate printed against CGST and against SGST, e.g. 9 for an 18%
  /// group. A label only: the money is the engine's, not this division's.
  double get halfRate => gstRate / 2;

  double get totalGst => cgst + stateGst + igst;

  double get totalTax => totalGst + cess;

  GstRateSummaryRow _plus({
    double cgst = 0,
    double stateGst = 0,
    double igst = 0,
    double cess = 0,
    double taxable = 0,
  }) {
    return GstRateSummaryRow(
      gstRate: gstRate,
      taxable: this.taxable + taxable,
      cgst: this.cgst + cgst,
      stateGst: this.stateGst + stateGst,
      igst: this.igst + igst,
      cess: this.cess + cess,
    );
  }
}

/// The bill's tax, grouped by GST rate, for printing on an invoice.
///
/// Built from the stored sale only. A sale saved before the GST engine
/// existed carries no snapshot, and [isEmpty] is then true so a template can
/// fall back to its legacy totals rather than print a fabricated 0.00.
class GstRateSummary {
  final List<GstRateSummaryRow> rows;

  /// 'SGST' or 'UTGST' — whichever the sale actually recorded. A Tamil Nadu
  /// shop always sees SGST; the union-territory spelling is kept so the same
  /// renderer stays correct if the engine ever prices one.
  final String stateLevyLabel;

  const GstRateSummary({required this.rows, required this.stateLevyLabel});

  bool get isEmpty => rows.isEmpty;

  bool get isNotEmpty => rows.isNotEmpty;

  /// True when more than one GST rate was billed, which is when the rate-wise
  /// table earns its place over a single CGST/SGST pair.
  bool get hasMultipleRates => rows.length > 1;

  double get taxable => _sum((r) => r.taxable);

  double get cgst => _sum((r) => r.cgst);

  double get stateGst => _sum((r) => r.stateGst);

  double get igst => _sum((r) => r.igst);

  double get cess => _sum((r) => r.cess);

  double get totalGst => cgst + stateGst + igst;

  double _sum(double Function(GstRateSummaryRow) pick) {
    var running = 0.0;
    for (final row in rows) {
      running += pick(row);
    }
    return running;
  }

  /// Groups the sale's snapshot lines by GST rate.
  ///
  /// The grouped columns are then reconciled against the sale's own stored
  /// totals: the group carrying the largest taxable value absorbs any
  /// difference, exactly as the engine apportions a discount remainder. This
  /// is presentation arithmetic and can move at most a paisa between printed
  /// rows — it never changes the tax charged or the total payable.
  static GstRateSummary fromSale(Sale sale) {
    final grouped = <double, GstRateSummaryRow>{};
    for (final item in sale.items) {
      final lineTax =
          item.cgstAmount +
          item.sgstAmount +
          item.utgstAmount +
          item.igstAmount +
          item.cessAmount;
      if (item.taxableValue == 0 && lineTax == 0) continue;
      final rate = item.gstRate ?? 0.0;
      final existing =
          grouped[rate] ??
          GstRateSummaryRow(
            gstRate: rate,
            taxable: 0,
            cgst: 0,
            stateGst: 0,
            igst: 0,
            cess: 0,
          );
      grouped[rate] = existing._plus(
        taxable: item.taxableValue,
        cgst: item.cgstAmount,
        stateGst: item.sgstAmount + item.utgstAmount,
        igst: item.igstAmount,
        cess: item.cessAmount,
      );
    }

    final label = sale.utgstAmount > 0 ? 'UTGST' : 'SGST';
    if (grouped.isEmpty) {
      return GstRateSummary(rows: const [], stateLevyLabel: label);
    }

    final rows = grouped.values.toList()
      ..sort((a, b) => a.gstRate.compareTo(b.gstRate));
    return GstRateSummary(
      rows: _reconciled(rows, sale),
      stateLevyLabel: label,
    );
  }

  /// Pushes any per-column difference between the grouped rows and the sale's
  /// stored totals onto the largest group, so the printed columns add up to
  /// the printed totals.
  static List<GstRateSummaryRow> _reconciled(
    List<GstRateSummaryRow> rows,
    Sale sale,
  ) {
    var widestAt = 0;
    for (var i = 1; i < rows.length; i++) {
      if (rows[i].taxable > rows[widestAt].taxable) widestAt = i;
    }
    var taxableSum = 0.0;
    var cgstSum = 0.0;
    var stateSum = 0.0;
    var igstSum = 0.0;
    var cessSum = 0.0;
    for (final row in rows) {
      taxableSum += row.taxable;
      cgstSum += row.cgst;
      stateSum += row.stateGst;
      igstSum += row.igst;
      cessSum += row.cess;
    }
    final widest = rows[widestAt];
    // A sale written before the GST engine existed can carry line snapshots
    // with no document-level totals, or the reverse. Absorbing a difference
    // that large would invent figures, so the grouped rows are printed as
    // they are and the mismatch stays visible.
    final drift = [
      sale.taxableAmount - taxableSum,
      sale.cgstAmount - cgstSum,
      (sale.sgstAmount + sale.utgstAmount) - stateSum,
      sale.igstAmount - igstSum,
      sale.cessAmount - cessSum,
    ];
    if (drift.any((d) => d.abs() > 1.0)) return rows;
    rows[widestAt] = GstRateSummaryRow(
      gstRate: widest.gstRate,
      taxable: _round2(widest.taxable + (sale.taxableAmount - taxableSum)),
      cgst: _round2(widest.cgst + (sale.cgstAmount - cgstSum)),
      stateGst: _round2(
        widest.stateGst +
            ((sale.sgstAmount + sale.utgstAmount) - stateSum),
      ),
      igst: _round2(widest.igst + (sale.igstAmount - igstSum)),
      cess: _round2(widest.cess + (sale.cessAmount - cessSum)),
    );
    for (var i = 0; i < rows.length; i++) {
      if (i == widestAt) continue;
      final row = rows[i];
      rows[i] = GstRateSummaryRow(
        gstRate: row.gstRate,
        taxable: _round2(row.taxable),
        cgst: _round2(row.cgst),
        stateGst: _round2(row.stateGst),
        igst: _round2(row.igst),
        cess: _round2(row.cess),
      );
    }
    return rows;
  }

  /// Half-away-from-zero, matching the GST engine's own rounding.
  static double _round2(double value) => (value * 100).roundToDouble() / 100;
}
