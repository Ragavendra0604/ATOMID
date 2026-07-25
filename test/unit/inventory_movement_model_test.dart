import 'package:flutter_test/flutter_test.dart';
import 'package:atomid/data/models/inventory_movement_model.dart';

void main() {
  group('InventoryMovement Model Tests', () {
    test('should create InventoryMovement with correct properties', () {
      final now = DateTime.now();
      final movement = InventoryMovement(
        id: 'invm1',
        productId: 'prod1',
        productName: 'T-Shirt',
        variantBarcode: 'BAR123',
        variantSize: 'L',
        type: 'IN',
        quantity: 10,
        reason: 'Purchase',
        date: now,
        movementReferenceId: 'purch1',
        performedAt: 'warehouse',
      );

      expect(movement.id, 'invm1');
      expect(movement.productId, 'prod1');
      expect(movement.productName, 'T-Shirt');
      expect(movement.variantBarcode, 'BAR123');
      expect(movement.variantSize, 'L');
      expect(movement.type, 'IN');
      expect(movement.quantity, 10);
      expect(movement.reason, 'Purchase');
      expect(movement.date, now);
      expect(movement.movementReferenceId, 'purch1');
      expect(movement.performedAt, 'warehouse');
    });
  });
}
