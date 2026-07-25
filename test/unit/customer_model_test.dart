import 'package:flutter_test/flutter_test.dart';
import 'package:atomid/data/models/customer_model.dart';
import 'package:atomid/data/models/customer_ledger_model.dart';

void main() {
  group('Customer Model Tests', () {
    test('should create Customer with default values', () {
      final now = DateTime.now();
      final customer = Customer(
        id: 'c1',
        code: 'CUST-001',
        name: 'Jane Doe',
        mobile: '1234567890',
        createdDate: now,
      );

      expect(customer.id, 'c1');
      expect(customer.code, 'CUST-001');
      expect(customer.name, 'Jane Doe');
      expect(customer.mobile, '1234567890');
      expect(customer.gstNumber, '');
      expect(customer.address, '');
      expect(customer.creditLimit, 0.0);
      expect(customer.creditDays, 0);
      expect(customer.openingBalance, 0.0);
      expect(customer.currentBalance, 0.0);
      expect(customer.status, 'Active');
      expect(customer.createdDate, now);
      expect(customer.totalRewardPoints, 0.0);
      expect(customer.lifetimeSpend, 0.0);
      expect(customer.isSynced, false);
      expect(customer.version, 1);
      expect(customer.isDeleted, false);
      expect(customer.email, '');
      expect(customer.customerGroup, 'General');
      expect(customer.notes, '');
      expect(customer.tags, isEmpty);
      expect(customer.attachments, isEmpty);
    });
  });

  group('CustomerLedger Model Tests', () {
    test('should create CustomerLedger with default values', () {
      final now = DateTime.now();
      final ledger = CustomerLedger(
        id: 'cl1',
        customerId: 'c1',
        date: now,
        transactionType: 'Sale',
        referenceId: 'REF-1',
        debit: 100.0,
        balance: 100.0,
      );

      expect(ledger.id, 'cl1');
      expect(ledger.customerId, 'c1');
      expect(ledger.date, now);
      expect(ledger.transactionType, 'Sale');
      expect(ledger.debit, 100.0);
      expect(ledger.credit, 0.0);
      expect(ledger.balance, 100.0);
      expect(ledger.referenceId, 'REF-1');
      expect(ledger.notes, '');
    });
  });
}
