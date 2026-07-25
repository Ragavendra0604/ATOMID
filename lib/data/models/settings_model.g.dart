// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'settings_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class SettingsModelAdapter extends TypeAdapter<SettingsModel> {
  @override
  final typeId = 3;

  @override
  SettingsModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return SettingsModel(
      isDarkMode: fields[0] as bool,
      companyName: fields[1] as String,
      currencySymbol: fields[2] as String,
      pdfPageSize: fields[3] as String,
      taxMode: fields[4] == null ? 'inclusive' : fields[4] as String,
      taxRate: fields[5] == null ? 0 : (fields[5] as num).toDouble(),
    );
  }

  @override
  void write(BinaryWriter writer, SettingsModel obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.isDarkMode)
      ..writeByte(1)
      ..write(obj.companyName)
      ..writeByte(2)
      ..write(obj.currencySymbol)
      ..writeByte(3)
      ..write(obj.pdfPageSize)
      ..writeByte(4)
      ..write(obj.taxMode)
      ..writeByte(5)
      ..write(obj.taxRate);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SettingsModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
