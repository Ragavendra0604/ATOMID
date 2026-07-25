// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'action_history_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ActionHistoryAdapter extends TypeAdapter<ActionHistory> {
  @override
  final typeId = 2;

  @override
  ActionHistory read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ActionHistory(
      id: fields[0] as String,
      barcode: fields[1] as String,
      productName: fields[2] as String,
      action: fields[3] as String,
      date: fields[4] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, ActionHistory obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.barcode)
      ..writeByte(2)
      ..write(obj.productName)
      ..writeByte(3)
      ..write(obj.action)
      ..writeByte(4)
      ..write(obj.date);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ActionHistoryAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
