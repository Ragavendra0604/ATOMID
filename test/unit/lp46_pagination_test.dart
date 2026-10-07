import 'package:flutter_test/flutter_test.dart';
import 'package:atomid/core/hardware/label_layout_engine.dart';
import 'package:atomid/core/hardware/label_printer_profile.dart';

void main() {
  group('LP46 Pagination Tests', () {
    final profile = LabelPrinterProfile.profile50x35TwoColumn;
    final engine = LabelLayoutEngine(profile);

    void runTest(
      int quantity,
      int expectedRows,
      int expectedPdfPages,
      int expectedPopulated,
      int expectedEmpty,
    ) async {
      // 1. Math checks
      final totalLabels = quantity;
      final rows = (quantity + 1) ~/ 2;
      expect(
        rows,
        expectedRows,
        reason: 'Row calculation mismatch for quantity \$quantity',
      );

      final layoutEnginePages = engine.calculateTotalPages(totalLabels);
      expect(
        layoutEnginePages,
        expectedPdfPages,
        reason: 'Layout Engine pages mismatch for quantity \$quantity',
      );

      final populated = totalLabels;
      expect(populated, expectedPopulated, reason: 'Populated count mismatch');

      final empty = (rows * profile.columns) - totalLabels;
      expect(empty, expectedEmpty, reason: 'Empty slots mismatch');
    }

    test('Quantity 0', () => runTest(0, 0, 0, 0, 0));
    test('Quantity 1', () => runTest(1, 1, 1, 1, 1));
    test('Quantity 2', () => runTest(2, 1, 1, 2, 0));
    test('Quantity 3', () => runTest(3, 2, 2, 3, 1));
    test('Quantity 4', () => runTest(4, 2, 2, 4, 0));
    test('Quantity 5', () => runTest(5, 3, 3, 5, 1));
    test('Quantity 10', () => runTest(10, 5, 5, 10, 0));
    test('Quantity 89', () => runTest(89, 45, 45, 89, 1));
  });
}
