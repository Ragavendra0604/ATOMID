import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'hardware_device.dart';
import 'barcode_scanner_service.dart';
import 'receipt_printer_service.dart';
import 'label_printer_service.dart';

final hardwareManagerProvider = Provider((ref) {
  final manager = HardwareManager();
  manager.registerDevice(ref.read(barcodeScannerServiceProvider));
  manager.registerDevice(ref.read(receiptPrinterServiceProvider));
  manager.registerDevice(ref.read(labelPrinterServiceProvider));
  return manager;
});

class HardwareManager {
  final Map<String, HardwareDevice> _devices = {};

  void registerDevice(HardwareDevice device) {
    _devices[device.id] = device;
  }

  void unregisterDevice(String id) {
    _devices.remove(id);
  }

  HardwareDevice? getDevice(String id) => _devices[id];

  List<HardwareDevice> get allDevices => _devices.values.toList();

  Future<void> connectAll() async {
    for (final device in _devices.values) {
      await device.connect();
    }
  }

  Future<void> disconnectAll() async {
    for (final device in _devices.values) {
      await device.disconnect();
    }
  }
}
