import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:atomid/data/repositories/storage_repository.dart';
import 'package:atomid/domain/services/auth_service.dart';
import 'package:atomid/domain/services/session_service.dart';
import 'package:atomid/domain/services/sync_service.dart';

import '../support/fake_firebase_repository.dart';
import '../support/test_store.dart';

class _MockUser extends Mock implements User {}

/// Signed in, without a live Firebase.
class _FakeAuthService extends AuthService {
  _FakeAuthService(super.repository, {this.user});

  final User? user;

  @override
  User? get currentUser => user;
}

class _FakeSessionService extends SessionService {
  _FakeSessionService(super.auth, {this.uid = 'uid_under_test'});

  final String? uid;

  @override
  String get deviceId => 'dev_test_abcd';

  @override
  String? get cloudUid => uid;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestStore store;
  late FakeFirebaseRepository cloud;
  late SyncService sync;

  setUp(() async {
    store = await TestStore.open();
    cloud = FakeFirebaseRepository();
    final auth = _FakeAuthService(cloud, user: _MockUser());
    sync = SyncService(
      store.repository,
      cloud,
      auth,
      _FakeSessionService(auth),
    );
  });

  tearDown(() => store.close());

  group('upload', () {
    test('a saved record is sent to its account-scoped collection', () async {
      final product = await store.addProduct(name: 'Sync Me');

      await sync.processQueue();

      final writes = cloud.allWrites;
      expect(writes, isNotEmpty);

      final productWrite = writes.firstWhere(
        (w) => w.documentId == product.id,
        orElse: () => fail('the product was never queued for upload'),
      );
      expect(productWrite.collection, 'products');
      expect(productWrite.isDelete, isFalse);
      expect(productWrite.data!['productName'], 'Sync Me');
    });

    test('a successful upload empties the queue', () async {
      await store.addProduct();
      expect(store.repository.getPendingSyncItems(), isNotEmpty);

      await sync.processQueue();

      expect(store.repository.getPendingSyncItems(), isEmpty);
      expect(sync.status.phase, SyncPhase.idle);
    });

    test('a failed upload keeps the work and counts the attempt', () async {
      await store.addProduct();
      cloud.nextCommitError = Exception('network unavailable');

      await sync.processQueue();

      final pending = store.repository.getPendingSyncItems();
      expect(
        pending,
        isNotEmpty,
        reason: 'work must never be dropped because the cloud refused it',
      );
      expect(pending.first.retryCount, greaterThan(0));
    });

    test('a failure is recorded in the sync log for diagnosis', () async {
      await store.addProduct();
      cloud.nextCommitError = Exception('boom');

      await sync.processQueue();

      final failures = store.repository.getSyncLogs(failuresOnly: true);
      expect(failures, isNotEmpty);
      expect(failures.first.error, contains('boom'));
    });

    test(
      'an item that has exhausted its retries is parked, not retried',
      () async {
        await store.addProduct();
        final item = store.repository.getPendingSyncItems().first;
        await store.repository.updateSyncItemStatus(
          item.id,
          SyncState.failed,
          retryCount: SyncState.maxRetries,
          lastAttempt: DateTime.now().subtract(const Duration(days: 1)),
        );

        await sync.processQueue();

        expect(store.repository.getDeadSyncItems(), isNotEmpty);
        expect(
          cloud.allWrites.any((w) => w.documentId == item.entityId),
          isFalse,
          reason: 'a dead item must not be sent again',
        );
      },
    );

    test('an item still inside its backoff window is not retried', () async {
      await store.addProduct();
      final item = store.repository.getPendingSyncItems().first;
      await store.repository.updateSyncItemStatus(
        item.id,
        SyncState.failed,
        retryCount: 2,
        lastAttempt: DateTime.now(),
      );

      await sync.processQueue();

      expect(
        cloud.commitAttempts,
        0,
        reason: 'backoff must hold the item back rather than hammer the cloud',
      );
    });

    test(
      'a record deleted locally before upload is dropped, not sent',
      () async {
        final product = await store.addProduct();
        await store.repository.deleteProduct(product.id);

        await sync.processQueue();

        // The delete is legitimate and still goes up; what must not happen is a
        // put for a record that no longer exists.
        final puts = cloud.allWrites.where(
          (w) => w.documentId == product.id && !w.isDelete,
        );
        expect(puts, isEmpty);
      },
    );

    test('nothing is uploaded while signed out', () async {
      final auth = _FakeAuthService(cloud, user: _MockUser());
      final unclaimed = SyncService(
        store.repository,
        cloud,
        auth,
        _FakeSessionService(auth, uid: null),
      );
      await store.addProduct();

      await unclaimed.processQueue();

      expect(cloud.commitAttempts, 0);
    });

    test('a device with no cloud account queues rather than firing', () async {
      // Nothing to write under. Firing one request per collection anyway
      // produced a storm of refusals on the device and reported failure for
      // something that was never wrong.
      final auth = _FakeAuthService(cloud, user: _MockUser());
      final waiting = SyncService(
        store.repository,
        cloud,
        auth,
        _FakeSessionService(auth, uid: null),
      );
      await store.addProduct();

      await waiting.processQueue();
      final pulled = await waiting.pullAll();

      expect(cloud.commitAttempts, 0, reason: 'nothing may be uploaded');
      expect(cloud.fetchAttempts, 0, reason: 'nothing may be fetched');
      expect(pulled, 0);
      expect(
        store.repository.getPendingSyncItems(),
        isNotEmpty,
        reason: 'the work is held, not discarded, until sign-in',
      );
    });

    test('a signed-out device queues but does not upload', () async {
      final auth = _FakeAuthService(cloud, user: null);
      final offline = SyncService(
        store.repository,
        cloud,
        auth,
        // Signed out means there is no account to write under, which is the
        // one thing that stops the queue draining.
        _FakeSessionService(auth, uid: null),
      );
      await store.addProduct();

      await offline.processQueue();

      expect(cloud.commitAttempts, 0);
      expect(offline.status.phase, SyncPhase.offline);
      expect(store.repository.getPendingSyncItems(), isNotEmpty);
    });
  });

  group('download', () {
    test('a remote record is written into local storage', () async {
      cloud.remoteDocuments['customers'] = [
        {
          'id': 'remote-customer-1',
          'name': 'Pulled Customer',
          'mobile': '9111111111',
          'code': 'C-99',
          'updatedAt': DateTime.now().toIso8601String(),
        },
      ];

      final applied = await sync.pullAll();

      expect(applied, greaterThan(0));
      final stored = store.repository.getCustomerById('remote-customer-1');
      expect(stored, isNotNull);
      expect(stored!.name, 'Pulled Customer');
    });

    test('a ledger entry is queued for upload', () async {
      // Ledgers were never in the syncable set, so the entries explaining a
      // customer's balance stayed on the device that recorded them. The
      // balance travelled; the statement behind it did not.
      final customer = await store.addCustomer();
      await store.repository.addLedgerEntry(
        customerId: customer.id,
        date: DateTime.now(),
        transactionType: 'Sale',
        referenceId: 'INV-1',
        debit: 500,
      );

      expect(
        store.repository.getPendingSyncItems().any(
          (i) => i.entityType == 'CustomerLedger',
        ),
        isTrue,
      );
    });

    test('a collection larger than one page is pulled whole', () async {
      // Regression: the pull was a single limit(500) query with no ordering,
      // so a shop with more than 500 of anything silently received an
      // arbitrary subset and the pull still reported success.
      const total = 750;
      cloud.remoteDocuments['customers'] = [
        for (var i = 0; i < total; i++)
          {
            'id': 'bulk-customer-$i',
            'name': 'Customer $i',
            'mobile': '9${i.toString().padLeft(9, '0')}',
            'code': 'C-$i',
            'updatedAt': DateTime.now().toIso8601String(),
          },
      ];

      await sync.pullAll();

      expect(
        store.repository.getAllCustomers().length,
        total,
        reason: 'every page must be applied, not just the first',
      );
      expect(store.repository.getCustomerById('bulk-customer-749'), isNotNull);
    });

    test(
      'a collection that cannot be read is reported, not swallowed',
      () async {
        cloud.failingCollections.add('products');

        await sync.pullAll();

        expect(sync.status.phase, SyncPhase.failed);
        expect(sync.status.message, isNotNull);
        expect(sync.status.message, contains('cannot read'));
      },
    );

    test('unsent local work is never overwritten by a pull', () async {
      final product = await store.addProduct(name: 'Local Wins');
      // The save above left a pending queue item, which marks it unsent.
      cloud.remoteDocuments['products'] = [
        {
          'id': product.id,
          'productName': 'Cloud Version',
          'productCode': 'X-1',
          'updatedAt': DateTime.now()
              .add(const Duration(days: 1))
              .toIso8601String(),
        },
      ];

      await sync.pullAll();

      expect(
        store.repository.getProductById(product.id)!.productName,
        'Local Wins',
        reason: 'a pull must not discard work this device has not uploaded',
      );
    });
  });
}
