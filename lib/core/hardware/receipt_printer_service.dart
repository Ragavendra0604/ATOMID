import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';
import 'dart:typed_data';
import 'hardware_device.dart';
import 'package:atomid/data/models/hardware_config_model.dart';

final receiptPrinterServiceProvider = Provider(
  (ref) => ReceiptPrinterService(),
);

class ReceiptPrinterService extends HardwareDevice {
  ReceiptPrinterService()
    : super(
        id: 'printer_retsol_rtp81',
        name: 'Receipt Printer',
        model: 'RETSOL RTP-81',
        connectionType: ConnectionType.systemPrintSpooler,
      );

  @override
  Future<bool> connect() async {
    final currentStatus = await checkStatus();
    return currentStatus == DeviceStatus.connected;
  }

  @override
  Future<void> disconnect() async {
    updateStatus(DeviceStatus.disconnected);
  }

  @override
  Future<DeviceStatus> checkStatus() async {
    try {
      final config = await HardwareConfigModel.load();
      if (config.receiptPrinterName == null ||
          config.receiptPrinterName!.isEmpty) {
        updateStatus(
          DeviceStatus.disconnected,
          'No printer configured in settings.',
        );
        return status;
      }

      final printers = await Printing.listPrinters();
      final exists = printers.any((p) => p.name == config.receiptPrinterName);

      if (exists) {
        updateStatus(
          DeviceStatus.connected,
          'Ready: ${config.receiptPrinterName}',
        );
      } else {
        updateStatus(
          DeviceStatus.error,
          'Configured printer not found. Please ensure the driver for $model is installed on this laptop.',
        );
      }
      return status;
    } catch (e) {
      updateStatus(DeviceStatus.error, e.toString());
      return DeviceStatus.error;
    }
  }

  /// Prints a pre-rendered PDF receipt directly to the OS print spooler.
  /// Does NOT block offline sales if it fails.
  Future<bool> printReceipt(
    Uint8List pdfBytes,
    String jobName, {
    String? printerName,
  }) async {
    try {
      Printer? selectedPrinter;
      if (printerName != null) {
        final available = await Printing.listPrinters();
        for (final p in available) {
          if (p.name == printerName) {
            selectedPrinter = p;
            break;
          }
        }
        if (selectedPrinter == null) {
          updateStatus(
            DeviceStatus.error,
            'Print failed: Printer "$printerName" is offline or missing.',
          );
          return false;
        }
      }

      final success = await Printing.directPrintPdf(
        printer: selectedPrinter ?? const Printer(url: 'default'),
        onLayout: (format) async => pdfBytes,
        name: jobName,
      );

      if (!success) {
        updateStatus(DeviceStatus.error, 'Print job rejected by spooler');
      } else {
        updateStatus(
          DeviceStatus.connected,
          'Ready: ${printerName ?? "Default"}',
        );
      }
      return success;
    } catch (e) {
      updateStatus(DeviceStatus.error, 'Driver error: $e');
      return false;
    }
  }
}
