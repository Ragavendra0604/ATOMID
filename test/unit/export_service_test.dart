import 'package:flutter_test/flutter_test.dart';
import 'package:atomid/core/services/export_service.dart';

void main() {
  group('ExportService Tests', () {
    test('ExportService should be instantiable', () {
      final exportService = ExportService();
      expect(exportService, isNotNull);
    });
  });
}
