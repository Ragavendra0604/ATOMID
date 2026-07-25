// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'inventory_movement_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class InventoryMovementAdapter extends TypeAdapter<InventoryMovement> {
  @override
  final typeId = 4;

  @override
  InventoryMovement read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return InventoryMovement(
      id: fields[0] as String,
      productId: fields[1] as String,
      productName: fields[2] as String,
      variantBarcode: fields[3] as String,
      variantSize: fields[4] as String,
      quantity: (fields[5] as num).toInt(),
      type: fields[6] as String,
      reason: fields[7] as String,
      date: fields[8] as DateTime,
      movementReferenceId: fields[9] == null ? '' : fields[9] as String,
      performedAt: fields[10] == null ? '' : fields[10] as String,
    );
  }

  @override
  void write(BinaryWriter writer, InventoryMovement obj) {
    writer
      ..writeByte(11)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.productId)
      ..writeByte(2)
      ..write(obj.productName)
      ..writeByte(3)
      ..write(obj.variantBarcode)
      ..writeByte(4)
      ..write(obj.variantSize)
      ..writeByte(5)
      ..write(obj.quantity)
      ..writeByte(6)
      ..write(obj.type)
      ..writeByte(7)
      ..write(obj.reason)
      ..writeByte(8)
      ..write(obj.date)
      ..writeByte(9)
      ..write(obj.movementReferenceId)
      ..writeByte(10)
      ..write(obj.performedAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InventoryMovementAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
