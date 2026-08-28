import 'package:hive_ce/hive.dart';

part 'gst_rate_config_model.g.dart';

@HiveType(typeId: 70)
class GstRateConfig extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String rateName;

  @HiveField(2)
  double rate;

  @HiveField(3)
  double cessRate;

  @HiveField(4)
  DateTime effectiveFrom;

  @HiveField(5)
  DateTime? effectiveTo;

  @HiveField(6)
  String description;

  @HiveField(7)
  bool isDeleted;

  @HiveField(8)
  DateTime? updatedAt;

  @HiveField(9)
  bool isSynced;

  GstRateConfig({
    required this.id,
    required this.rateName,
    required this.rate,
    this.cessRate = 0.0,
    required this.effectiveFrom,
    this.effectiveTo,
    this.description = '',
    this.isDeleted = false,
    this.updatedAt,
    this.isSynced = false,
  });

  bool isEffectiveOn(DateTime date) {
    if (date.isBefore(effectiveFrom)) return false;
    if (effectiveTo != null && date.isAfter(effectiveTo!)) return false;
    return true;
  }
}
