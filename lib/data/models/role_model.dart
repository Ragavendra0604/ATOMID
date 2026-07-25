import 'package:hive_ce/hive.dart';

part 'role_model.g.dart';

@HiveType(typeId: 61)
enum Role {
  @HiveField(0)
  owner,
  @HiveField(1)
  manager,
  @HiveField(2)
  cashier,
  @HiveField(3)
  inventoryStaff,
  @HiveField(4)
  salesStaff,
  @HiveField(5)
  accountant,
  @HiveField(6)
  custom,
}
