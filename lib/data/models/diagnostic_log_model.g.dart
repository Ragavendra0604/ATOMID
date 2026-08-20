// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'diagnostic_log_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class DiagnosticLogAdapter extends TypeAdapter<DiagnosticLog> {
  @override
  final typeId = 41;

  @override
  DiagnosticLog read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return DiagnosticLog(
      id: fields[0] as String,
      occurredAt: fields[1] as DateTime,
      severity: fields[2] as String,
      area: fields[3] as String,
      reference: fields[4] as String,
      message: fields[5] as String,
      detail: fields[6] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, DiagnosticLog obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.occurredAt)
      ..writeByte(2)
      ..write(obj.severity)
      ..writeByte(3)
      ..write(obj.area)
      ..writeByte(4)
      ..write(obj.reference)
      ..writeByte(5)
      ..write(obj.message)
      ..writeByte(6)
      ..write(obj.detail);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DiagnosticLogAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
