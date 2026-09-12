enum DeviceStatus { connected, disconnected, connecting, error, unknown }

enum ConnectionType { usb, bluetooth, network, serial, systemPrintSpooler, keyboardHid }

abstract class HardwareDevice {
  final String id;
  final String name;
  final String model;
  final ConnectionType connectionType;

  DeviceStatus _status = DeviceStatus.unknown;
  DeviceStatus get status => _status;
  
  String? _statusMessage;
  String? get statusMessage => _statusMessage;

  HardwareDevice({
    required this.id,
    required this.name,
    required this.model,
    required this.connectionType,
  });

  /// Connect to the physical hardware or initialized driver
  Future<bool> connect();

  /// Safely disconnect from the hardware
  Future<void> disconnect();

  /// Run an arbitrary connection/status check
  Future<DeviceStatus> checkStatus();

  void updateStatus(DeviceStatus newStatus, [String? message]) {
    _status = newStatus;
    _statusMessage = message; // Always overwrite to allow clearing errors on success
  }
}

class PrintJob {
  final String jobId;
  final String transactionId;
  final String documentType;
  final String printerId;
  final DateTime createdAt;
  
  String status;
  int attempts;
  String? error;

  PrintJob({
    required this.jobId,
    required this.transactionId,
    required this.documentType,
    required this.printerId,
    this.status = 'PENDING',
    this.attempts = 0,
  }) : createdAt = DateTime.now();
}
