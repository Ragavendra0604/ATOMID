import 'package:hive_ce/hive.dart';

part 'customer_ledger_model.g.dart';

@HiveType(typeId: 16)
class CustomerLedger extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String customerId;

  @HiveField(2)
  DateTime date;

  @HiveField(3)
  String transactionType; // 'Sale', 'Payment', 'Opening Balance'

  @HiveField(4)
  String referenceId; // e.g., Invoice Number or Payment ID

  @HiveField(5)
  double debit; // Increases outstanding (e.g., Sale)

  @HiveField(6)
  double credit; // Decreases outstanding (e.g., Payment)

  @HiveField(7)
  double balance; // Running balance at the time of entry

  @HiveField(8)
  String notes;

  CustomerLedger({
    required this.id,
    required this.customerId,
    required this.date,
    required this.transactionType,
    required this.referenceId,
    this.debit = 0,
    this.credit = 0,
    this.balance = 0,
    this.notes = '',
  });
}
