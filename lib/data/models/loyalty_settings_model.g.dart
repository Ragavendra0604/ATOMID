// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'loyalty_settings_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class LoyaltySettingsModelAdapter extends TypeAdapter<LoyaltySettingsModel> {
  @override
  final typeId = 21;

  @override
  LoyaltySettingsModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return LoyaltySettingsModel(
      isLoyaltyEnabled: fields[0] == null ? false : fields[0] as bool,
      spendAmountForPoint: fields[1] == null
          ? 100
          : (fields[1] as num).toDouble(),
      pointsEarnedPerSpend: fields[2] == null
          ? 1
          : (fields[2] as num).toDouble(),
      pointRedemptionValue: fields[3] == null
          ? 1
          : (fields[3] as num).toDouble(),
      maxRedemptionPercentage: fields[4] == null
          ? 50
          : (fields[4] as num).toDouble(),
      minBillAmountForRedemption: fields[5] == null
          ? 0
          : (fields[5] as num).toDouble(),
      updatedAt: fields[6] as DateTime?,
    );
  }

  @override
  void write(BinaryWriter writer, LoyaltySettingsModel obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.isLoyaltyEnabled)
      ..writeByte(1)
      ..write(obj.spendAmountForPoint)
      ..writeByte(2)
      ..write(obj.pointsEarnedPerSpend)
      ..writeByte(3)
      ..write(obj.pointRedemptionValue)
      ..writeByte(4)
      ..write(obj.maxRedemptionPercentage)
      ..writeByte(5)
      ..write(obj.minBillAmountForRedemption)
      ..writeByte(6)
      ..write(obj.updatedAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LoyaltySettingsModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
