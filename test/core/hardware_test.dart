import 'package:flutter_test/flutter_test.dart';
import 'package:atomid/core/hardware/print_job_manager.dart';
import 'package:atomid/core/hardware/barcode_scanner_service.dart';
import 'package:atomid/core/hardware/hardware_device.dart';

void main() {
  group('PrintJobManager Tests', () {
    test('Prevents duplicate active print jobs', () {
      final manager = PrintJobManager();

      final first = manager.startJob('job_1', 'txn_1', 'RECEIPT', 'printer_1');
      expect(first, isTrue);

      final duplicate = manager.startJob(
        'job_1',
        'txn_1',
        'RECEIPT',
        'printer_1',
      );
      expect(duplicate, isFalse, reason: 'Should block duplicate active job');

      manager.failJob('job_1', 'Out of paper');

      final retry = manager.startJob('job_1', 'txn_1', 'RECEIPT', 'printer_1');
      expect(retry, isTrue, reason: 'Should allow retry after failure');
      expect(manager.getJob('job_1')?.attempts, equals(1));
    });

    test('Completes job successfully', () {
      final manager = PrintJobManager();
      manager.startJob('job_2', 'txn_2', 'LABEL', 'printer_2');
      manager.completeJob('job_2');

      expect(manager.getJob('job_2')?.status, equals('COMPLETED'));

      final duplicate = manager.startJob(
        'job_2',
        'txn_2',
        'LABEL',
        'printer_2',
      );
      expect(
        duplicate,
        isFalse,
        reason: 'Should block duplicate even if completed',
      );
    });
  });

  group('BarcodeScannerService Tests', () {
    test('Emits barcode when connected', () async {
      final scanner = BarcodeScannerService();
      await scanner.connect();
      expect(scanner.status, equals(DeviceStatus.connected));

      String? emittedBarcode;
      scanner.onBarcodeScanned.listen((barcode) {
        emittedBarcode = barcode;
      });

      scanner.processScannedBarcode('123456789012');

      // Allow microtask to process
      await Future.delayed(Duration.zero);

      expect(emittedBarcode, equals('123456789012'));
      scanner.dispose();
    });

    test('Ignores barcodes when disconnected', () async {
      final scanner = BarcodeScannerService();
      // disconnected by default

      String? emittedBarcode;
      scanner.onBarcodeScanned.listen((barcode) {
        emittedBarcode = barcode;
      });

      scanner.processScannedBarcode('9999');

      await Future.delayed(Duration.zero);
      expect(emittedBarcode, isNull);
      scanner.dispose();
    });
  });
}
