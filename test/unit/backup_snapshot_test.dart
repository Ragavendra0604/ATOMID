import 'package:flutter_test/flutter_test.dart';

import 'package:atomid/data/models/settings_model.dart';

import '../support/test_store.dart';

/// The snapshot behind backup and restore.
///
/// A backup that quietly omits a record is worse than no backup: it is only
/// discovered at the moment somebody needs it. These assert that what goes out
/// comes back.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestStore store;

  setUp(() async => store = await TestStore.open());
  tearDown(() => store.close());

  test('a snapshot carries every kind of record on the device', () async {
    final repo = store.repository;
    final product = await store.addProduct();
    final customer = await store.addCustomer();
    await store.addSupplier();

    final snapshot = repo.exportSnapshot();

    expect(snapshot['Product'], hasLength(1));
    expect(snapshot['Customer'], hasLength(1));
    expect(snapshot['Supplier'], hasLength(1));
    expect(
      snapshot['Product']!.single['id'],
      product.id,
      reason: 'records must be identifiable to restore under the same id',
    );
    expect(snapshot['Customer']!.single['id'], customer.id);
  });

  test('a singleton carries the key it has to be restored under', () async {
    final repo = store.repository;
    await repo.saveSettings(
      SettingsModel(companyName: 'Nila Traders', taxRate: 12),
    );

    final settings = repo.exportSnapshot()['SettingsModel']!.single;

    // The payload id is 'settings'; the box key is 'app_settings'. Restoring
    // under the payload id would create a second, ignored record.
    expect(settings['_localId'], 'app_settings');
  });

  test('restoring puts records back after they are deleted', () async {
    final repo = store.repository;
    final product = await store.addProduct(name: 'Silk Saree');
    final customer = await store.addCustomer(name: 'Meena');

    final snapshot = repo.exportSnapshot();

    await repo.deleteProduct(product.id);
    expect(repo.getProductById(product.id), isNull);

    final restored = await repo.importSnapshot(snapshot);

    expect(restored['Product'], 1);
    expect(repo.getProductById(product.id), isNotNull);
    expect(repo.getProductById(product.id)!.productName, 'Silk Saree');
    expect(repo.getCustomerById(customer.id)!.name, 'Meena');
  });

  test('restoring never deletes work done since the backup', () async {
    final repo = store.repository;
    await store.addProduct(name: 'Old Product');

    final snapshot = repo.exportSnapshot();

    final newer = await store.addProduct(name: 'Added Afterwards');
    await repo.importSnapshot(snapshot);

    expect(
      repo.getProductById(newer.id),
      isNotNull,
      reason: 'an older backup must not destroy newer work',
    );
    expect(repo.getAllProducts(), hasLength(2));
  });

  test('a restored record is queued for upload', () async {
    final repo = store.repository;
    final product = await store.addProduct();
    final snapshot = repo.exportSnapshot();

    for (final item in repo.getPendingSyncItems()) {
      await repo.deleteSyncItem(item.id);
    }
    await repo.importSnapshot(snapshot);

    expect(
      repo.getPendingSyncItems().any(
        (i) => i.entityType == 'Product' && i.entityId == product.id,
      ),
      isTrue,
      reason: 'a restore that never reaches the cloud is half a restore',
    );
  });

  test('the customer ledger survives a round trip', () async {
    final repo = store.repository;
    final customer = await store.addCustomer();

    await repo.addLedgerEntry(
      customerId: customer.id,
      date: DateTime(2026, 8, 4),
      transactionType: 'Sale',
      referenceId: 'INV-1',
      debit: 1200,
      notes: 'Credit sale',
    );

    final snapshot = repo.exportSnapshot();
    expect(
      snapshot['CustomerLedger'],
      hasLength(1),
      reason: 'the statement behind a balance is data, not a derived view',
    );

    final entry = snapshot['CustomerLedger']!.single;
    expect(entry['debit'], 1200);
    expect(entry['referenceId'], 'INV-1');
    expect(entry['notes'], 'Credit sale');
  });
}
