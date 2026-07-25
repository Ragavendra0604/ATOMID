// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'employee_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class EmployeeModelAdapter extends TypeAdapter<EmployeeModel> {
  @override
  final typeId = 60;

  @override
  EmployeeModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return EmployeeModel(
      id: fields[0] as String?,
      fullName: fields[1] as String,
      profilePicture: fields[2] as String?,
      email: fields[3] as String,
      phoneNumber: fields[4] as String,
      role: fields[5] as Role,
      permissions: (fields[6] as List).cast<Permission>(),
      pin: fields[7] as String?,
      isActive: fields[8] == null ? true : fields[8] as bool,
      dateJoined: fields[9] as DateTime?,
      lastLogin: fields[10] as DateTime?,
      createdBy: fields[11] as String?,
      updatedBy: fields[12] as String?,
      isDeleted: fields[13] == null ? false : fields[13] as bool,
      isSynced: fields[14] == null ? false : fields[14] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, EmployeeModel obj) {
    writer
      ..writeByte(15)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.fullName)
      ..writeByte(2)
      ..write(obj.profilePicture)
      ..writeByte(3)
      ..write(obj.email)
      ..writeByte(4)
      ..write(obj.phoneNumber)
      ..writeByte(5)
      ..write(obj.role)
      ..writeByte(6)
      ..write(obj.permissions)
      ..writeByte(7)
      ..write(obj.pin)
      ..writeByte(8)
      ..write(obj.isActive)
      ..writeByte(9)
      ..write(obj.dateJoined)
      ..writeByte(10)
      ..write(obj.lastLogin)
      ..writeByte(11)
      ..write(obj.createdBy)
      ..writeByte(12)
      ..write(obj.updatedBy)
      ..writeByte(13)
      ..write(obj.isDeleted)
      ..writeByte(14)
      ..write(obj.isSynced);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EmployeeModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
