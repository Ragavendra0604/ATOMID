// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sync_log_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class SyncLogModelAdapter extends TypeAdapter<SyncLogModel> {
  @override
  final typeId = 40;

  @override
  SyncLogModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return SyncLogModel(
      id: fields[0] as String,
      entityType: fields[1] as String,
      entityId: fields[2] as String,
      operation: fields[3] as String,
      deviceId: fields[4] as String,
      startedAt: fields[5] as DateTime,
      completedAt: fields[6] as DateTime,
      durationMs: (fields[7] as num).toInt(),
      status: fields[8] as String,
      retryCount: (fields[9] as num).toInt(),
      error: fields[10] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, SyncLogModel obj) {
    writer
      ..writeByte(11)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.entityType)
      ..writeByte(2)
      ..write(obj.entityId)
      ..writeByte(3)
      ..write(obj.operation)
      ..writeByte(4)
      ..write(obj.deviceId)
      ..writeByte(5)
      ..write(obj.startedAt)
      ..writeByte(6)
      ..write(obj.completedAt)
      ..writeByte(7)
      ..write(obj.durationMs)
      ..writeByte(8)
      ..write(obj.status)
      ..writeByte(9)
      ..write(obj.retryCount)
      ..writeByte(10)
      ..write(obj.error);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SyncLogModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
