import 'package:hive_ce/hive.dart';

part 'permission_model.g.dart';

@HiveType(typeId: 62)
enum Permission {
  @HiveField(0)
  createProducts,
  @HiveField(1)
  editProducts,
  @HiveField(2)
  deleteProducts,
  @HiveField(3)
  viewInventory,
  @HiveField(4)
  adjustInventory,
  @HiveField(5)
  createPurchase,
  @HiveField(6)
  viewPurchase,
  @HiveField(7)
  createSales,
  @HiveField(8)
  viewReports,
  @HiveField(9)
  manageCustomers,
  @HiveField(10)
  manageSuppliers,
  @HiveField(11)
  manageExpenses,
  @HiveField(12)
  manageSettings,
  @HiveField(13)
  manageEmployees,
  @HiveField(14)
  manageBackup,
  @HiveField(15)
  restoreBackup,
}
