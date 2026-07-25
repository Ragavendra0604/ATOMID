import 'package:hive_ce/hive.dart';

part 'supplier_ledger_model.g.dart';

@HiveType(typeId: 22)
class SupplierLedger extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String supplierId;

  @HiveField(2)
  DateTime date;

  @HiveField(3)
  String transactionType; // 'Purchase', 'Payment', 'Opening Balance'

  @HiveField(4)
  String referenceId; // e.g., Purchase Number or Payment ID

  @HiveField(5)
  double credit; // Increases outstanding (e.g., Purchase from supplier)

  @HiveField(6)
  double debit; // Decreases outstanding (e.g., Payment to supplier)

  @HiveField(7)
  double balance; // Running balance at the time of entry

  @HiveField(8)
  String notes;

  SupplierLedger({
    required this.id,
    required this.supplierId,
    required this.date,
    required this.transactionType,
    required this.referenceId,
    this.credit = 0,
    this.debit = 0,
    this.balance = 0,
    this.notes = '',
  });
}
