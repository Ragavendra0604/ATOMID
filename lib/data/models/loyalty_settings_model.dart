import 'package:hive_ce/hive.dart';

part 'loyalty_settings_model.g.dart';

@HiveType(typeId: 21)
class LoyaltySettingsModel extends HiveObject {
  @HiveField(0)
  bool isLoyaltyEnabled;

  @HiveField(1)
  double spendAmountForPoint; // e.g., ₹100

  @HiveField(2)
  double pointsEarnedPerSpend; // e.g., 10 points

  @HiveField(3)
  double pointRedemptionValue; // e.g., 1 point = ₹1

  @HiveField(4)
  double maxRedemptionPercentage; // e.g., 50%

  @HiveField(5)
  double minBillAmountForRedemption;

  /// When this record last changed, so two devices editing the same
  /// settings resolve on recency rather than on which pull landed last.
  @HiveField(6)
  DateTime? updatedAt;

  LoyaltySettingsModel({
    this.isLoyaltyEnabled = false,
    this.spendAmountForPoint = 100,
    this.pointsEarnedPerSpend = 1,
    this.pointRedemptionValue = 1,
    this.maxRedemptionPercentage = 50,
    this.minBillAmountForRedemption = 0,
    this.updatedAt,
  });
}
