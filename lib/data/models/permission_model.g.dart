// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'permission_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class PermissionAdapter extends TypeAdapter<Permission> {
  @override
  final typeId = 62;

  @override
  Permission read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return Permission.createProducts;
      case 1:
        return Permission.editProducts;
      case 2:
        return Permission.deleteProducts;
      case 3:
        return Permission.viewInventory;
      case 4:
        return Permission.adjustInventory;
      case 5:
        return Permission.createPurchase;
      case 6:
        return Permission.viewPurchase;
      case 7:
        return Permission.createSales;
      case 8:
        return Permission.viewReports;
      case 9:
        return Permission.manageCustomers;
      case 10:
        return Permission.manageSuppliers;
      case 11:
        return Permission.manageExpenses;
      case 12:
        return Permission.manageSettings;
      case 13:
        return Permission.manageEmployees;
      case 14:
        return Permission.manageBackup;
      case 15:
        return Permission.restoreBackup;
      default:
        return Permission.createProducts;
    }
  }

  @override
  void write(BinaryWriter writer, Permission obj) {
    switch (obj) {
      case Permission.createProducts:
        writer.writeByte(0);
      case Permission.editProducts:
        writer.writeByte(1);
      case Permission.deleteProducts:
        writer.writeByte(2);
      case Permission.viewInventory:
        writer.writeByte(3);
      case Permission.adjustInventory:
        writer.writeByte(4);
      case Permission.createPurchase:
        writer.writeByte(5);
      case Permission.viewPurchase:
        writer.writeByte(6);
      case Permission.createSales:
        writer.writeByte(7);
      case Permission.viewReports:
        writer.writeByte(8);
      case Permission.manageCustomers:
        writer.writeByte(9);
      case Permission.manageSuppliers:
        writer.writeByte(10);
      case Permission.manageExpenses:
        writer.writeByte(11);
      case Permission.manageSettings:
        writer.writeByte(12);
      case Permission.manageEmployees:
        writer.writeByte(13);
      case Permission.manageBackup:
        writer.writeByte(14);
      case Permission.restoreBackup:
        writer.writeByte(15);
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PermissionAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
