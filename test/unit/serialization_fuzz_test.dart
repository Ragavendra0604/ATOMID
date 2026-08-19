import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:atomid/data/repositories/storage_repository.dart';

import '../support/test_store.dart';

/// Hostile input against the cloud decoder.
///
/// `applyRemote` is fed whatever Firestore hands back. A document written by
/// an older build, a partially-written document, or one edited by hand in the
/// console will not match the shape the decoder expects — and an exception
/// there does not fail one record, it aborts the pull for that entire
/// collection and reports a failure the shop cannot act on.
///
/// So the contract under test is: **a malformed document must never throw.**
/// It may be rejected or decoded with defaults, but the pull has to survive it
/// and keep going.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestStore store;
  late StorageRepository repo;

  // One store for the whole file. Each case writes under its own key and
  // asserts only that the decoder survived, so isolation buys nothing — and
  // opening twenty-one Hive boxes per case took the suite from seconds to
  // twelve minutes, which is a cost CI pays on every push.
  setUpAll(() async {
    store = await TestStore.open();
    repo = store.repository;
  });

  tearDownAll(() => store.close());

  const entityTypes = [
    'Product',
    'Customer',
    'Supplier',
    'Sale',
    'Purchase',
    'Expense',
    'ExpenseCategory',
    'InventoryMovement',
    'LoyaltyTransaction',
    'CustomerLedger',
    'SupplierLedger',
    'SettingsModel',
    'CompanyModel',
    'InvoiceSettingsModel',
    'LoyaltySettingsModel',
  ];

  /// Payload shapes a real backend can genuinely produce.
  final hostilePayloads = <String, Map<String, dynamic>>{
    'empty': <String, dynamic>{},
    'id only': {'id': 'x1'},
    'nulls everywhere': {
      'id': 'x1',
      'name': null,
      'productName': null,
      'mobile': null,
      'grandTotal': null,
      'quantity': null,
      'date': null,
      'createdDate': null,
      'updatedAt': null,
      'items': null,
      'variants': null,
    },
    'wrong types': {
      'id': 'x1',
      'name': 42,
      'productName': true,
      'mobile': ['not', 'a', 'string'],
      'grandTotal': 'free',
      'quantity': 'many',
      'createdDate': 12345,
      'updatedAt': {'nested': 'object'},
      'items': 'not a list',
      'variants': {'not': 'a list'},
      'isDeleted': 'yes',
    },
    'numbers as strings': {
      'id': 'x1',
      'grandTotal': '100.50',
      'subtotal': '90',
      'quantity': '3',
      'points': '10',
    },
    'invalid dates': {
      'id': 'x1',
      'createdDate': 'not-a-date',
      'date': '2026-13-45T99:99:99',
      'updatedAt': '',
      'purchaseDate': 'yesterday',
    },
    'negative numbers': {
      'id': 'x1',
      'grandTotal': -9999.99,
      'quantity': -5,
      'price': -1,
      'points': -100,
      'currentBalance': -50000,
    },
    'enormous numbers': {
      'id': 'x1',
      'grandTotal': 1e308,
      'quantity': 9007199254740991,
      'price': double.maxFinite,
    },
    'non-finite numbers': {
      'id': 'x1',
      'grandTotal': double.infinity,
      'price': double.nan,
      'subtotal': double.negativeInfinity,
    },
    'extra unknown fields': {
      'id': 'x1',
      'somethingFromTheFuture': {
        'deeply': {
          'nested': [1, 2, 3],
        },
      },
      'anotherNewField': 'hello',
    },
    'malformed nested items': {
      'id': 'x1',
      'items': [
        null,
        'a string',
        42,
        <String, dynamic>{},
        {'quantity': 'lots', 'price': null},
      ],
      'variants': [
        null,
        'a string',
        {'barcode': 123, 'quantity': 'many', 'price': <String, dynamic>{}},
      ],
    },
    'empty strings': {
      'id': '',
      'name': '',
      'mobile': '',
      'productName': '',
      'invoiceNumber': '',
    },
    'unicode and very long text': {
      'id': 'x1',
      'name': 'Unicode shop, long name follows',
      'productName': 'Japanese text sample',
      'notes': 'y' * 5000,
    },
  };

  group('a malformed cloud document never throws', () {
    for (final entityType in entityTypes) {
      for (final entry in hostilePayloads.entries) {
        test('$entityType survives "${entry.key}"', () async {
          // The contract is survival, not acceptance. Either outcome is fine
          // provided the pull can continue past it.
          await expectLater(
            repo.applyRemote(entityType, 'fuzz-id', {...entry.value}),
            completes,
            reason:
                'a $entityType shaped like "${entry.key}" must not abort the '
                'pull for its whole collection',
          );
        });
      }
    }
  });

  group('the store stays coherent after hostile input', () {
    test('applying every hostile payload leaves no corruption', () async {
      for (final entityType in entityTypes) {
        for (final entry in hostilePayloads.entries) {
          try {
            await repo.applyRemote(entityType, 'fuzz-${entry.key}', {
              ...entry.value,
              'id': 'fuzz-${entry.key}',
            });
          } catch (_) {
            // Reported by the group above; here only the state left behind
            // matters.
          }
        }
      }
      await repo.reconcileAfterPull();

      expect(
        repo.auditDerivedState(),
        isEmpty,
        reason: 'hostile cloud input must not leave the indexes inconsistent',
      );
    });
  });

  group('randomised payloads', () {
    test('a thousand random documents cannot break the decoder', () async {
      // Fixed seed: a failure here has to be reproducible.
      final random = Random(20260819);
      final values = <dynamic>[
        null,
        0,
        1,
        -1,
        0.01,
        -0.01,
        1e18,
        -1e18,
        double.nan,
        double.infinity,
        '',
        'x',
        '0',
        'not-a-date',
        true,
        false,
        <dynamic>[],
        <String, dynamic>{},
        [1, 'two', null],
        {'a': 1},
        '2026-01-01T00:00:00.000',
        '9999999999999999999',
      ];
      const keys = [
        'id',
        'name',
        'productName',
        'mobile',
        'grandTotal',
        'subtotal',
        'quantity',
        'price',
        'date',
        'createdDate',
        'updatedAt',
        'updatedDate',
        'items',
        'variants',
        'isDeleted',
        'points',
        'currentBalance',
        'status',
        'transactionType',
        'customerId',
        'barcode',
      ];

      var applied = 0;
      for (var i = 0; i < 1000; i++) {
        final entityType = entityTypes[random.nextInt(entityTypes.length)];
        final payload = <String, dynamic>{'id': 'rnd-$i'};
        final fieldCount = random.nextInt(keys.length);
        for (var f = 0; f < fieldCount; f++) {
          payload[keys[random.nextInt(keys.length)]] =
              values[random.nextInt(values.length)];
        }

        try {
          await repo.applyRemote(entityType, 'rnd-$i', payload);
          applied++;
        } catch (error, stack) {
          fail(
            'seed 20260819, iteration $i: applyRemote($entityType) threw\n'
            '$error\npayload: $payload\n$stack',
          );
        }
      }

      expect(applied, 1000);
      await repo.reconcileAfterPull();
      expect(repo.auditDerivedState(), isEmpty);
    });
  });
}
