// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'gst_rate_config_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class GstRateConfigAdapter extends TypeAdapter<GstRateConfig> {
  @override
  final typeId = 70;

  @override
  GstRateConfig read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return GstRateConfig(
      id: fields[0] as String,
      rateName: fields[1] as String,
      rate: (fields[2] as num).toDouble(),
      cessRate: fields[3] == null ? 0.0 : (fields[3] as num).toDouble(),
      effectiveFrom: fields[4] as DateTime,
      effectiveTo: fields[5] as DateTime?,
      description: fields[6] == null ? '' : fields[6] as String,
      isDeleted: fields[7] == null ? false : fields[7] as bool,
      updatedAt: fields[8] as DateTime?,
      isSynced: fields[9] == null ? false : fields[9] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, GstRateConfig obj) {
    writer
      ..writeByte(10)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.rateName)
      ..writeByte(2)
      ..write(obj.rate)
      ..writeByte(3)
      ..write(obj.cessRate)
      ..writeByte(4)
      ..write(obj.effectiveFrom)
      ..writeByte(5)
      ..write(obj.effectiveTo)
      ..writeByte(6)
      ..write(obj.description)
      ..writeByte(7)
      ..write(obj.isDeleted)
      ..writeByte(8)
      ..write(obj.updatedAt)
      ..writeByte(9)
      ..write(obj.isSynced);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GstRateConfigAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
