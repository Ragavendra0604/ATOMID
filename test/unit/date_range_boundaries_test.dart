import 'package:flutter_test/flutter_test.dart';

import 'package:atomid/data/models/sale_model.dart';
import 'package:atomid/data/repositories/storage_repository.dart';

import '../support/test_store.dart';

/// Regression cover for B-3: report windows used to be
/// `isAfter(start - 1 day) && isBefore(end + 1 day)`, which quietly swept in a
/// whole extra day at each end.
///
/// These are figures a shop owner reconciles against the cash drawer, so a
/// day either side is not a rounding difference — it is the wrong answer.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestStore store;

  setUp(() async => store = await TestStore.open());
  tearDown(() => store.close());

  Future<Sale> sell({required String id, required DateTime at}) async {
    final sale = Sale(
      id: id,
      invoiceNumber: id.toUpperCase(),
      date: at,
      customerId: '',
      customerName: 'Walk-In Customer',
      subtotal: 100,
      discountPercent: 0,
      discountAmount: 0,
      taxAmount: 0,
      grandTotal: 100,
      paymentMethod: 'Cash',
      items: const [],
    );
    await store.repository.saveSale(sale);
    return sale;
  }

  group(
    'getSalesByDateRange includes both requested days and nothing else',
    () {
      test('a single-day window is exactly that day', () async {
        final day = DateTime(2026, 6, 15);

        await sell(id: 'before', at: DateTime(2026, 6, 14, 23, 59, 59));
        await sell(id: 'first', at: DateTime(2026, 6, 15, 0, 0, 0));
        await sell(id: 'midday', at: DateTime(2026, 6, 15, 13, 30));
        await sell(id: 'last', at: DateTime(2026, 6, 15, 23, 59, 59));
        await sell(id: 'after', at: DateTime(2026, 6, 16, 0, 0, 0));

        final ids = store.repository
            .getSalesByDateRange(day, day)
            .map((s) => s.id)
            .toSet();

        expect(ids, {'first', 'midday', 'last'});
        expect(
          ids,
          isNot(contains('before')),
          reason: 'the previous day must not leak in',
        );
        expect(
          ids,
          isNot(contains('after')),
          reason: 'the following day must not leak in',
        );
      });

      test('a multi-day window includes both endpoints in full', () async {
        await sell(id: 'day1-start', at: DateTime(2026, 6, 10, 0, 0, 0));
        await sell(id: 'day3-end', at: DateTime(2026, 6, 12, 23, 59, 59));
        await sell(id: 'outside-before', at: DateTime(2026, 6, 9, 23, 59, 59));
        await sell(id: 'outside-after', at: DateTime(2026, 6, 13, 0, 0, 0));

        final ids = store.repository
            .getSalesByDateRange(DateTime(2026, 6, 10), DateTime(2026, 6, 12))
            .map((s) => s.id)
            .toSet();

        expect(ids, {'day1-start', 'day3-end'});
      });

      test('the time of day on the requested bounds is ignored', () async {
        await sell(id: 'early', at: DateTime(2026, 6, 15, 1));
        await sell(id: 'late', at: DateTime(2026, 6, 15, 22));

        // Asking with a mid-afternoon timestamp must still mean "that day".
        final ids = store.repository
            .getSalesByDateRange(
              DateTime(2026, 6, 15, 15, 42),
              DateTime(2026, 6, 15, 15, 42),
            )
            .map((s) => s.id)
            .toSet();

        expect(ids, {'early', 'late'});
      });

      test('a month boundary is not off by a day', () async {
        await sell(id: 'jun30', at: DateTime(2026, 6, 30, 20));
        await sell(id: 'jul01', at: DateTime(2026, 7, 1, 9));
        await sell(id: 'jul31', at: DateTime(2026, 7, 31, 23, 30));
        await sell(id: 'aug01', at: DateTime(2026, 8, 1, 0, 30));

        final ids = store.repository
            .getSalesByDateRange(DateTime(2026, 7, 1), DateTime(2026, 7, 31))
            .map((s) => s.id)
            .toSet();

        expect(ids, {'jul01', 'jul31'});
      });

      test('a year boundary is not off by a day', () async {
        await sell(id: 'dec31', at: DateTime(2025, 12, 31, 23, 59));
        await sell(id: 'jan01', at: DateTime(2026, 1, 1, 0, 1));

        final ids = store.repository
            .getSalesByDateRange(DateTime(2026, 1, 1), DateTime(2026, 1, 1))
            .map((s) => s.id)
            .toSet();

        expect(ids, {'jan01'});
      });

      test('an empty range reports nothing rather than throwing', () {
        expect(
          store.repository.getSalesByDateRange(
            DateTime(2026, 1, 1),
            DateTime(2026, 1, 31),
          ),
          isEmpty,
        );
      });

      test('a voided sale is excluded from a range that contains it', () async {
        final sale = await sell(id: 's1', at: DateTime(2026, 6, 15, 12));
        sale.isDeleted = true;
        await store.repository.saveSale(sale);

        expect(
          store.repository.getSalesByDateRange(
            DateTime(2026, 6, 15),
            DateTime(2026, 6, 15),
          ),
          isEmpty,
        );
      });
    },
  );

  group('startOfDay', () {
    test('snaps to local midnight and drops the time', () {
      expect(
        StorageRepository.startOfDay(DateTime(2026, 6, 15, 23, 59, 59)),
        DateTime(2026, 6, 15),
      );
      expect(
        StorageRepository.startOfDay(DateTime(2026, 6, 15)),
        DateTime(2026, 6, 15),
      );
    });
  });
}
