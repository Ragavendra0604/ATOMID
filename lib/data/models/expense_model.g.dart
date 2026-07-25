// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'expense_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ExpenseCategoryAdapter extends TypeAdapter<ExpenseCategory> {
  @override
  final typeId = 25;

  @override
  ExpenseCategory read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ExpenseCategory(
      id: fields[0] as String,
      name: fields[1] as String,
      iconName: fields[2] == null ? 'receipt' : fields[2] as String,
    );
  }

  @override
  void write(BinaryWriter writer, ExpenseCategory obj) {
    writer
      ..writeByte(3)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.iconName);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExpenseCategoryAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class ExpenseAdapter extends TypeAdapter<Expense> {
  @override
  final typeId = 26;

  @override
  Expense read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Expense(
      id: fields[0] as String,
      title: fields[1] as String,
      categoryId: fields[2] as String,
      categoryName: fields[3] as String,
      amount: (fields[4] as num).toDouble(),
      date: fields[5] as DateTime,
      notes: fields[6] == null ? '' : fields[6] as String,
      receiptImagePath: fields[7] as String?,
      createdDate: fields[8] as DateTime,
      createdBy: fields[9] == null ? '' : fields[9] as String,
      isSynced: fields[10] == null ? false : fields[10] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, Expense obj) {
    writer
      ..writeByte(11)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.categoryId)
      ..writeByte(3)
      ..write(obj.categoryName)
      ..writeByte(4)
      ..write(obj.amount)
      ..writeByte(5)
      ..write(obj.date)
      ..writeByte(6)
      ..write(obj.notes)
      ..writeByte(7)
      ..write(obj.receiptImagePath)
      ..writeByte(8)
      ..write(obj.createdDate)
      ..writeByte(9)
      ..write(obj.createdBy)
      ..writeByte(10)
      ..write(obj.isSynced);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExpenseAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
