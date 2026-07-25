// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'login_history_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class LoginHistoryModelAdapter extends TypeAdapter<LoginHistoryModel> {
  @override
  final typeId = 63;

  @override
  LoginHistoryModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return LoginHistoryModel(
      id: fields[0] as String?,
      employeeId: fields[1] as String,
      loginTime: fields[2] as DateTime,
      deviceInfo: fields[3] as String,
      ipAddress: fields[4] as String,
      isSynced: fields[5] == null ? false : fields[5] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, LoginHistoryModel obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.employeeId)
      ..writeByte(2)
      ..write(obj.loginTime)
      ..writeByte(3)
      ..write(obj.deviceInfo)
      ..writeByte(4)
      ..write(obj.ipAddress)
      ..writeByte(5)
      ..write(obj.isSynced);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LoginHistoryModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
