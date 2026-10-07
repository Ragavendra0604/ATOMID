import 'dart:typed_data';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';

/// Adapter interface for physical label printers.
abstract class LabelPrinterAdapter {
  /// Check if the adapter can handle this printer on this platform.
  bool canHandle(String printerName);

  /// Send a print job directly to the printer.
  Future<bool> printLabel(
    Uint8List pdfBytes,
    String jobName,
    String printerName, {
    PdfPageFormat? format,
  });
}

/// Uses package:printing to send a pre-rendered PDF directly to the Windows spooler.
class WindowsPdfLabelPrinterAdapter implements LabelPrinterAdapter {
  @override
  bool canHandle(String printerName) {
    // We assume any configured printer name on Windows can be reached via the spooler
    // as long as package:printing can see it. We don't restrict it by name, but
    // the service handles checking if the printer actually exists.
    return true;
  }

  @override
  Future<bool> printLabel(
    Uint8List pdfBytes,
    String jobName,
    String printerName, {
    PdfPageFormat? format,
  }) async {
    Printer? selectedPrinter;
    final available = await Printing.listPrinters();
    for (final p in available) {
      if (p.name == printerName) {
        selectedPrinter = p;
        break;
      }
    }

    if (selectedPrinter == null) {
      throw Exception(
        'Print failed: Label printer "$printerName" is offline or missing.',
      );
    }

    return await Printing.directPrintPdf(
      printer: selectedPrinter,
      onLayout: (f) async => pdfBytes,
      name: jobName,
      format: format ?? PdfPageFormat.standard,
      usePrinterSettings: true,
    );
  }
}
