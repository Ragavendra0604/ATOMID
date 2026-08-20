import 'package:hive_ce/hive.dart';

part 'diagnostic_log_model.g.dart';

/// A failure the shop needs a record of, written where a person can read it.
///
/// Distinct from [SyncLogModel], which records the outcome of talking to the
/// cloud, and from `ActionHistory`, which is a business activity trail shown
/// to the shopkeeper. This is the third case: something went wrong *locally*
/// in a path that touches money or stock, and the only previous trace was a
/// `debugPrint` to a console no shop owner has attached.
///
/// The motivating case is a checkout that fails partway and cannot fully
/// reverse itself. The sale is unwound, the till carries on, and the till
/// operator sees nothing — but stock may now disagree with the ledger, and a
/// technician arriving a week later has no way to find out that it happened,
/// let alone when or to which invoice.
///
/// Device-local by design. Nothing enqueues these for sync: a diagnostic
/// record describes one installation's disk and is meaningless on another.
@HiveType(typeId: 41)
class DiagnosticLog extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  DateTime occurredAt;

  /// [DiagnosticSeverity]. Stored as a string rather than an enum index so a
  /// later addition cannot renumber the existing rows on disk.
  @HiveField(2)
  String severity;

  /// Which part of the app failed — [DiagnosticArea].
  @HiveField(3)
  String area;

  /// The business document this concerns: an invoice number, a PO number, a
  /// box name. What a technician searches by.
  @HiveField(4)
  String reference;

  /// One line, written for a person rather than a log parser.
  @HiveField(5)
  String message;

  /// The exception and stack, when there was one.
  @HiveField(6)
  String? detail;

  DiagnosticLog({
    required this.id,
    required this.occurredAt,
    required this.severity,
    required this.area,
    required this.reference,
    required this.message,
    this.detail,
  });
}

class DiagnosticSeverity {
  /// Something failed but the app corrected for it.
  static const warning = 'WARNING';

  /// Something failed and data may now be inconsistent. Needs a human.
  static const error = 'ERROR';
}

class DiagnosticArea {
  static const checkout = 'Checkout';
  static const receiving = 'Receiving';
  static const storage = 'Storage';
  static const startup = 'Startup';
  static const backup = 'Backup';
}
