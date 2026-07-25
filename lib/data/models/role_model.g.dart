// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'role_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class RoleAdapter extends TypeAdapter<Role> {
  @override
  final typeId = 61;

  @override
  Role read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return Role.owner;
      case 1:
        return Role.manager;
      case 2:
        return Role.cashier;
      case 3:
        return Role.inventoryStaff;
      case 4:
        return Role.salesStaff;
      case 5:
        return Role.accountant;
      case 6:
        return Role.custom;
      default:
        return Role.owner;
    }
  }

  @override
  void write(BinaryWriter writer, Role obj) {
    switch (obj) {
      case Role.owner:
        writer.writeByte(0);
      case Role.manager:
        writer.writeByte(1);
      case Role.cashier:
        writer.writeByte(2);
      case Role.inventoryStaff:
        writer.writeByte(3);
      case Role.salesStaff:
        writer.writeByte(4);
      case Role.accountant:
        writer.writeByte(5);
      case Role.custom:
        writer.writeByte(6);
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RoleAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
