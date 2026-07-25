import 'package:flutter_test/flutter_test.dart';
import 'package:atomid/data/models/supplier_model.dart';

void main() {
  group('Supplier Model Tests', () {
    test('Supplier should be created with all required fields', () {
      final now = DateTime.now();
      final supplier = Supplier(
        id: 'sup-001',
        supplierCode: 'SUP-001',
        supplierName: 'Test Supplier',
        phone: '9876543210',
        email: 'test@supplier.com',
        address: '123 Test Street',
        gstNumber: 'GST1234567890',
        contactPerson: 'John Doe',
        notes: 'Test notes',
        createdDate: now,
        updatedDate: now,
        isActive: true,
      );

      expect(supplier.id, 'sup-001');
      expect(supplier.supplierCode, 'SUP-001');
      expect(supplier.supplierName, 'Test Supplier');
      expect(supplier.phone, '9876543210');
      expect(supplier.email, 'test@supplier.com');
      expect(supplier.address, '123 Test Street');
      expect(supplier.gstNumber, 'GST1234567890');
      expect(supplier.contactPerson, 'John Doe');
      expect(supplier.notes, 'Test notes');
      expect(supplier.createdDate, now);
      expect(supplier.isActive, true);
    });

    test('Supplier should have default values for optional fields', () {
      final now = DateTime.now();
      final supplier = Supplier(
        id: 'sup-002',
        supplierCode: 'SUP-002',
        supplierName: 'Minimal Supplier',
        createdDate: now,
        updatedDate: now,
      );

      expect(supplier.phone, '');
      expect(supplier.email, '');
      expect(supplier.address, '');
      expect(supplier.gstNumber, '');
      expect(supplier.contactPerson, '');
      expect(supplier.notes, '');
      expect(supplier.isActive, true);
    });

    test('Supplier isActive can be set to false', () {
      final supplier = Supplier(
        id: 'sup-003',
        supplierCode: 'SUP-003',
        supplierName: 'Inactive Supplier',
        createdDate: DateTime.now(),
        updatedDate: DateTime.now(),
        isActive: false,
      );

      expect(supplier.isActive, false);
    });
  });
}
