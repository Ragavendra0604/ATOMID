import 'package:flutter_test/flutter_test.dart';

import 'package:atomid/core/utils/formatters.dart';
import 'package:atomid/core/utils/ids.dart';

void main() {
  group('money', () {
    test('always shows two decimals with the store symbol', () {
      expect(Fmt.money(1299.9, '\$'), r'$1,299.90');
      expect(Fmt.money(0, '₹'), '₹0.00');
      expect(Fmt.money(1000000, '₹'), '₹1,000,000.00');
    });

    test('never leaks floating point noise', () {
      expect(Fmt.money(1299.90 * 3, '₹'), '₹3,899.70');
    });

    test('negative amounts keep their sign', () {
      expect(Fmt.money(-45.5, '₹'), '-₹45.50');
    });
  });

  test('round2 stops error accumulating in a ledger', () {
    var running = 0.0;
    for (var i = 0; i < 10; i++) {
      running = Fmt.round2(running + 0.1);
    }
    expect(running, 1.0);
  });

  test('points and counts read as whole numbers', () {
    expect(Fmt.points(20), '20 pts');
    expect(Fmt.count(1500), '1,500');
  });

  group('ids', () {
    test('generated ids are unique even in a tight loop', () {
      final ids = List.generate(2000, (_) => Ids.generate()).toSet();
      expect(ids, hasLength(2000));
    });

    test('a device short code is a stable four characters', () {
      expect(Ids.shortCode('dev_1723456789_ab12'), 'AB12');
      expect(Ids.shortCode('xy'), hasLength(4));
    });

    test('different devices produce different codes', () {
      expect(Ids.shortCode('dev_1_aaaa'), isNot(Ids.shortCode('dev_1_bbbb')));
    });
  });
}
