import 'package:hive_ce/hive.dart';

class HardwareConfigModel {
  String? receiptPrinterName;
  String? labelPrinterName;
  bool scannerEnabled;
  String labelProfileId;

  HardwareConfigModel({
    this.receiptPrinterName,
    this.labelPrinterName,
    this.scannerEnabled = true,
    this.labelProfileId = '50x35',
  });

  factory HardwareConfigModel.defaultConfig() {
    return HardwareConfigModel();
  }

  factory HardwareConfigModel.fromMap(Map<dynamic, dynamic> map) {
    return HardwareConfigModel(
      receiptPrinterName: map['receiptPrinterName'] as String?,
      labelPrinterName: map['labelPrinterName'] as String?,
      scannerEnabled: map['scannerEnabled'] as bool? ?? true,
      labelProfileId: map['labelProfileId'] as String? ?? '50x35',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'receiptPrinterName': receiptPrinterName,
      'labelPrinterName': labelPrinterName,
      'scannerEnabled': scannerEnabled,
      'labelProfileId': labelProfileId,
    };
  }

  static Future<HardwareConfigModel> load() async {
    final box = await Hive.openBox('hardware_config');
    final data = box.get('settings');
    if (data == null) {
      return HardwareConfigModel.defaultConfig();
    }
    return HardwareConfigModel.fromMap(data as Map);
  }

  Future<void> save() async {
    final box = await Hive.openBox('hardware_config');
    await box.put('settings', toMap());
  }
}
