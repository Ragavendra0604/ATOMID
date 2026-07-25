// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'activity_log_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ActivityLogModelAdapter extends TypeAdapter<ActivityLogModel> {
  @override
  final typeId = 64;

  @override
  ActivityLogModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ActivityLogModel(
      id: fields[0] as String?,
      timestamp: fields[1] as DateTime,
      action: fields[2] as String,
      ownerId: fields[3] as String,
      targetEmployeeId: fields[4] as String,
      isSynced: fields[5] == null ? false : fields[5] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, ActivityLogModel obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.timestamp)
      ..writeByte(2)
      ..write(obj.action)
      ..writeByte(3)
      ..write(obj.ownerId)
      ..writeByte(4)
      ..write(obj.targetEmployeeId)
      ..writeByte(5)
      ..write(obj.isSynced);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ActivityLogModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
