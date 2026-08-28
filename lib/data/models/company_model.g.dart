// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'company_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class CompanyModelAdapter extends TypeAdapter<CompanyModel> {
  @override
  final typeId = 10;

  @override
  CompanyModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return CompanyModel(
      name: fields[0] == null ? '' : fields[0] as String,
      logoPath: fields[1] == null ? '' : fields[1] as String,
      ownerName: fields[2] == null ? '' : fields[2] as String,
      gstNumber: fields[3] == null ? '' : fields[3] as String,
      panNumber: fields[4] == null ? '' : fields[4] as String,
      phone1: fields[5] == null ? '' : fields[5] as String,
      phone2: fields[6] == null ? '' : fields[6] as String,
      email: fields[7] == null ? '' : fields[7] as String,
      website: fields[8] == null ? '' : fields[8] as String,
      address: fields[9] == null ? '' : fields[9] as String,
      city: fields[10] == null ? '' : fields[10] as String,
      state: fields[11] == null ? '' : fields[11] as String,
      country: fields[12] == null ? '' : fields[12] as String,
      pincode: fields[13] == null ? '' : fields[13] as String,
      invoicePrefix: fields[14] == null ? 'INV' : fields[14] as String,
      barcodePrefix: fields[15] == null ? 'BR' : fields[15] as String,
      currency: fields[16] == null ? '₹' : fields[16] as String,
      financialYear: fields[17] == null ? '' : fields[17] as String,
      updatedAt: fields[18] as DateTime?,
      stateCode: fields[19] == null ? '' : fields[19] as String,
      gstRegistrationStatus: fields[20] == null
          ? 'Registered'
          : fields[20] as String,
      tradeName: fields[21] == null ? '' : fields[21] as String,
    );
  }

  @override
  void write(BinaryWriter writer, CompanyModel obj) {
    writer
      ..writeByte(22)
      ..writeByte(0)
      ..write(obj.name)
      ..writeByte(1)
      ..write(obj.logoPath)
      ..writeByte(2)
      ..write(obj.ownerName)
      ..writeByte(3)
      ..write(obj.gstNumber)
      ..writeByte(4)
      ..write(obj.panNumber)
      ..writeByte(5)
      ..write(obj.phone1)
      ..writeByte(6)
      ..write(obj.phone2)
      ..writeByte(7)
      ..write(obj.email)
      ..writeByte(8)
      ..write(obj.website)
      ..writeByte(9)
      ..write(obj.address)
      ..writeByte(10)
      ..write(obj.city)
      ..writeByte(11)
      ..write(obj.state)
      ..writeByte(12)
      ..write(obj.country)
      ..writeByte(13)
      ..write(obj.pincode)
      ..writeByte(14)
      ..write(obj.invoicePrefix)
      ..writeByte(15)
      ..write(obj.barcodePrefix)
      ..writeByte(16)
      ..write(obj.currency)
      ..writeByte(17)
      ..write(obj.financialYear)
      ..writeByte(18)
      ..write(obj.updatedAt)
      ..writeByte(19)
      ..write(obj.stateCode)
      ..writeByte(20)
      ..write(obj.gstRegistrationStatus)
      ..writeByte(21)
      ..write(obj.tradeName);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CompanyModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
