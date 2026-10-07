import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'dart:typed_data';
import 'hardware_device.dart';
import 'package:atomid/data/models/hardware_config_model.dart';
import 'label_printer_adapter.dart';
import 'label_printer_profile.dart' as import_hardware_profile;

final labelPrinterServiceProvider = Provider((ref) => LabelPrinterService());

class LabelPrinterService extends HardwareDevice {
  import_hardware_profile.LabelPrinterProfile activeProfile =
      import_hardware_profile.LabelPrinterProfile.profile50x35Single;

  LabelPrinterService()
    : super(
        id: 'printer_tvs_lp46',
        name: 'Label Printer',
        model: 'TVS Electronics LP 46 DLITE',
        connectionType: ConnectionType.systemPrintSpooler,
      );

  void setProfile(import_hardware_profile.LabelPrinterProfile profile) {
    activeProfile = profile;
  }

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

      // Load the profile FIRST, even if they haven't selected a specific printer yet,
      // so the preview layout still uses their selected dimensions (e.g. 2 Across).
      final profile = import_hardware_profile.LabelPrinterProfile.predefined
          .firstWhere(
            (p) => p.id == config.labelProfileId,
            orElse: () =>
                import_hardware_profile.LabelPrinterProfile.profile50x35Single,
          );
      setProfile(profile);

      if (config.labelPrinterName == null || config.labelPrinterName!.isEmpty) {
        updateStatus(
          DeviceStatus.disconnected,
          'No label printer configured in settings.',
        );
        return status;
      }

      final printers = await Printing.listPrinters();
      final exists = printers.any((p) => p.name == config.labelPrinterName);

      if (exists) {
        updateStatus(
          DeviceStatus.connected,
          'Ready: ${config.labelPrinterName} (${config.labelProfileId})',
        );
      } else {
        updateStatus(
          DeviceStatus.error,
          'Configured label printer not found. Please ensure the driver for $model is installed on this laptop.',
        );
      }
      return status;
    } catch (e) {
      updateStatus(DeviceStatus.error, e.toString());
      return DeviceStatus.error;
    }
  }

  // Hardcode the Windows/Spooler adapter. Later this can be expanded to TSPL/EPL raw sockets if required.
  final List<LabelPrinterAdapter> _adapters = [WindowsPdfLabelPrinterAdapter()];

  /// Prints a pre-rendered PDF label directly to the OS print spooler.
  Future<bool> printLabel(
    Uint8List pdfBytes,
    String jobName, {
    String? printerName,
    PdfPageFormat? format,
  }) async {
    try {
      final targetPrinter = printerName ?? 'default';

      LabelPrinterAdapter? selectedAdapter;
      for (final adapter in _adapters) {
        if (adapter.canHandle(targetPrinter)) {
          selectedAdapter = adapter;
          break;
        }
      }

      if (selectedAdapter == null) {
        updateStatus(
          DeviceStatus.error,
          'No suitable print adapter found for "$targetPrinter"',
        );
        return false;
      }

      final success = await selectedAdapter.printLabel(
        pdfBytes,
        jobName,
        targetPrinter,
        format: format,
      );

      if (!success) {
        updateStatus(DeviceStatus.error, 'Print job rejected by spooler');
      } else {
        updateStatus(DeviceStatus.connected, 'Ready: $targetPrinter');
      }
      return success;
    } catch (e) {
      updateStatus(DeviceStatus.error, 'Driver error: $e');
      return false;
    }
  }
}
