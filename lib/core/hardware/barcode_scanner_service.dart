import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'hardware_device.dart';

final barcodeScannerServiceProvider = Provider(
  (ref) => BarcodeScannerService(),
);

class BarcodeScannerService extends HardwareDevice {
  BarcodeScannerService()
    : super(
        id: 'scanner_iball_bss209',
        name: 'Barcode Scanner',
        model: 'iBall BSS209',
        connectionType: ConnectionType.keyboardHid,
      );

  final _scanController = StreamController<String>.broadcast();
  Stream<String> get onBarcodeScanned => _scanController.stream;

  @override
  Future<bool> connect() async {
    // For Keyboard HID, "connect" is mostly logical (the OS handles physical USB/Bluetooth).
    // We assume it's connected if we are initializing it.
    updateStatus(DeviceStatus.connected);
    return true;
  }

  @override
  Future<void> disconnect() async {
    updateStatus(DeviceStatus.disconnected);
  }

  @override
  Future<DeviceStatus> checkStatus() async {
    return status;
  }

  /// Called by the GlobalBarcodeListener when a rapid keystroke sequence completes
  void processScannedBarcode(String barcode) {
    if (status != DeviceStatus.connected) {
      return; // Ignore if conceptually disabled
    }
    final cleanBarcode = barcode.trim();
    if (cleanBarcode.isNotEmpty) {
      _scanController.add(cleanBarcode);
    }
  }

  void dispose() {
    _scanController.close();
  }
}
