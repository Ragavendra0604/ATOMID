/// What a cashier needs to know about the person at the counter.
///
/// Derived from the sales history rather than stored, so it can never drift
/// out of step with the invoices it summarises.
class CustomerVisitStats {
  /// Number of completed sales attributed to this customer.
  final int visits;

  final double totalSpend;
  final DateTime? firstVisit;
  final DateTime? lastVisit;

  const CustomerVisitStats({
    this.visits = 0,
    this.totalSpend = 0,
    this.firstVisit,
    this.lastVisit,
  });

  static const CustomerVisitStats none = CustomerVisitStats();

  bool get isReturning => visits > 0;

  double get averageBasket => visits == 0 ? 0 : totalSpend / visits;

  int? get daysSinceLastVisit {
    final last = lastVisit;
    if (last == null) return null;
    return DateTime.now().difference(last).inDays;
  }

  /// A plain descriptor of how established the customer is.
  ///
  /// Deliberately factual — it describes the history, it does not prescribe a
  /// discount. What to give away is the shop's call, not the app's.
  String get standing {
    if (visits == 0) return 'First visit';
    if (visits == 1) return 'Second visit';
    if (visits < 5) return 'Occasional';
    if (visits < 15) return 'Regular';
    return 'Loyal';
  }

  /// Ordinal for the visit about to happen, e.g. "12th visit".
  String get nextVisitLabel {
    final n = visits + 1;
    final suffix = switch (n % 100) {
      11 || 12 || 13 => 'th',
      _ => switch (n % 10) {
        1 => 'st',
        2 => 'nd',
        3 => 'rd',
        _ => 'th',
      },
    };
    return '$n$suffix visit';
  }
}
