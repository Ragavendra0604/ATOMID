import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:atomid/domain/services/customer_service.dart';
import 'package:atomid/domain/services/session_service.dart';

import '../support/test_store.dart';

class MockSessionService extends Mock implements SessionService {}

/// Regression cover for the customer merge that used to hand-add
/// `currentBalance` and silently drop the secondary account's ledger rows —
/// this exercises the real [StorageRepository], not a mock, so it proves the
/// ledger entries actually land and the balance actually agrees with them.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestStore store;
  late CustomerService customers;

  setUp(() async {
    store = await TestStore.open();
    final session = MockSessionService();
    when(() => session.deviceId).thenReturn('dev_test_abcd');
    customers = CustomerService(store.repository, session);
  });

  tearDown(() => store.close());

  test(
    'merging moves the secondary\'s ledger rows, not just its balance number',
    () async {
      final primary = await store.addCustomer(name: 'Primary', mobile: '111');
      final secondary = await store.addCustomer(
        name: 'Secondary',
        mobile: '222',
      );

      await store.repository.addLedgerEntry(
        customerId: primary.id,
        date: DateTime(2026, 1, 1),
        transactionType: 'Sale',
        referenceId: 'INV-P1',
        debit: 500,
      );
      await store.repository.addLedgerEntry(
        customerId: secondary.id,
        date: DateTime(2026, 1, 2),
        transactionType: 'Sale',
        referenceId: 'INV-S1',
        debit: 300,
      );
      await store.repository.addLedgerEntry(
        customerId: secondary.id,
        date: DateTime(2026, 1, 3),
        transactionType: 'Payment',
        referenceId: 'INV-S1',
        credit: 100,
      );

      expect(store.repository.getCustomerById(primary.id)!.currentBalance, 500);
      expect(
        store.repository.getCustomerById(secondary.id)!.currentBalance,
        200,
      );

      await customers.mergeCustomers(primary.id, secondary.id);

      // The combined balance is correct...
      final merged = store.repository.getCustomerById(primary.id)!;
      expect(merged.currentBalance, 700);

      // ...and, unlike the old hand-added field, it is backed by the ledger
      // rows actually being there under the primary's id.
      final ledger = store.repository.getLedgerForCustomer(primary.id);
      expect(
        ledger.map((e) => e.referenceId),
        containsAll(['INV-P1', 'INV-S1']),
      );
      expect(ledger, hasLength(3));

      // The secondary is left with nothing outstanding, not a stale number.
      expect(store.repository.getLedgerForCustomer(secondary.id), isEmpty);
      expect(store.repository.getCustomerById(secondary.id)!.currentBalance, 0);
    },
  );

  test(
    'a nonzero opening balance is carried into the merge, not lost',
    () async {
      final primary = await store.addCustomer(name: 'Primary', mobile: '111');
      final secondary = await store.addCustomer(
        name: 'Secondary',
        mobile: '222',
      );

      final secondaryRecord = store.repository.getCustomerById(secondary.id)!;
      secondaryRecord.openingBalance = 150;
      secondaryRecord.currentBalance = 150;
      await store.repository.saveCustomer(secondaryRecord);

      await customers.mergeCustomers(primary.id, secondary.id);

      expect(store.repository.getCustomerById(primary.id)!.currentBalance, 150);
      expect(
        store.repository.getLedgerForCustomer(primary.id).single.notes,
        contains('Opening balance carried into merge'),
      );
    },
  );

  test('the reassigned ledger row is re-queued as an update', () async {
    final primary = await store.addCustomer(name: 'Primary', mobile: '111');
    final secondary = await store.addCustomer(name: 'Secondary', mobile: '222');

    final entryId = await store.repository.addLedgerEntry(
      customerId: secondary.id,
      date: DateTime.now(),
      transactionType: 'Sale',
      referenceId: 'INV-S1',
      debit: 300,
    );

    await customers.mergeCustomers(primary.id, secondary.id);

    // The queue dedupes pending writes for the same record into one item
    // (the original CREATE, still unsent), so what matters is that it is
    // still queued — not stuck as COMPLETED with the reassignment unsent.
    final queued = store.repository
        .getPendingSyncItems()
        .where((i) => i.entityId == entryId)
        .toList();
    expect(queued, hasLength(1));

    // And the payload actually sent to the cloud carries the new owner.
    final json = store.repository.getEntityJson('CustomerLedger', entryId);
    expect(json?['customerId'], primary.id);
  });

  test(
    'merging moves the secondary\'s loyalty rows, so its points survive the '
    'next recomputation',
    () async {
      final primary = await store.addCustomer(name: 'Primary', mobile: '111');
      final secondary = await store.addCustomer(
        name: 'Secondary',
        mobile: '222',
      );

      await store.repository.addLoyaltyTransaction(
        customerId: primary.id,
        transactionType: 'Earn',
        points: 40,
        monetaryValue: 0,
        reference: 'INV-P1',
        createdBy: 'test',
      );
      await store.repository.addLoyaltyTransaction(
        customerId: secondary.id,
        transactionType: 'Earn',
        points: 60,
        monetaryValue: 0,
        reference: 'INV-S1',
        createdBy: 'test',
      );

      await customers.mergeCustomers(primary.id, secondary.id);

      expect(
        store.repository.getCustomerById(primary.id)!.totalRewardPoints,
        100,
        reason: 'the merged account keeps both balances',
      );
      expect(
        store.repository.getCustomerById(secondary.id)!.totalRewardPoints,
        0,
        reason: 'and the emptied account keeps none of them',
      );

      // The real regression. Hand-adding the number looked correct right up
      // to here, and the merged-in points disappeared on the customer's very
      // next sale, when the balance was derived again from rows that had
      // never been moved across.
      await store.repository.addLoyaltyTransaction(
        customerId: primary.id,
        transactionType: 'Earn',
        points: 5,
        monetaryValue: 0,
        reference: 'INV-P2',
        createdBy: 'test',
      );

      expect(
        store.repository.getCustomerById(primary.id)!.totalRewardPoints,
        105,
        reason: 'merged-in points must survive the next recomputation',
      );
    },
  );

  test('the reassigned loyalty row is re-queued as an update', () async {
    final primary = await store.addCustomer(name: 'Primary', mobile: '111');
    final secondary = await store.addCustomer(name: 'Secondary', mobile: '222');

    final txId = await store.repository.addLoyaltyTransaction(
      customerId: secondary.id,
      transactionType: 'Earn',
      points: 25,
      monetaryValue: 0,
      reference: 'INV-S1',
      createdBy: 'test',
    );

    await customers.mergeCustomers(primary.id, secondary.id);

    final json = store.repository.getEntityJson('LoyaltyTransaction', txId);
    expect(
      json?['customerId'],
      primary.id,
      reason: 'the other device must be told who owns these points now',
    );
  });
}
