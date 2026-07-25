import 'package:hive_ce/hive.dart';

part 'action_history_model.g.dart';

@HiveType(typeId: 2)
class ActionHistory extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String barcode;

  @HiveField(2)
  String productName;

  @HiveField(3)
  String action;

  @HiveField(4)
  DateTime date;

  ActionHistory({
    required this.id,
    required this.barcode,
    required this.productName,
    required this.action,
    required this.date,
  });
}
