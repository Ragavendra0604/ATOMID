import 'package:hive_ce/hive.dart';

part 'expense_model.g.dart';

@HiveType(typeId: 25)
class ExpenseCategory extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String name;

  @HiveField(2)
  String iconName; // e.g. 'home', 'electric_bolt', 'receipt'

  ExpenseCategory({
    required this.id,
    required this.name,
    this.iconName = 'receipt',
  });
}

@HiveType(typeId: 26)
class Expense extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String title;

  @HiveField(2)
  String categoryId;

  @HiveField(3)
  String categoryName;

  @HiveField(4)
  double amount;

  @HiveField(5)
  DateTime date;

  @HiveField(6)
  String notes;

  @HiveField(7)
  String? receiptImagePath;

  @HiveField(8)
  DateTime createdDate;

  @HiveField(9)
  String createdBy;

  @HiveField(10)
  bool isSynced;

  Expense({
    required this.id,
    required this.title,
    required this.categoryId,
    required this.categoryName,
    required this.amount,
    required this.date,
    this.notes = '',
    this.receiptImagePath,
    required this.createdDate,
    this.createdBy = '',
    this.isSynced = false,
  });
}
