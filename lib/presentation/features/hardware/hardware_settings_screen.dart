import 'package:flutter/material.dart';

import 'package:printing/printing.dart';
import '../../../data/models/hardware_config_model.dart';

class HardwareSettingsScreen extends StatefulWidget {
  const HardwareSettingsScreen({super.key});

  @override
  State<HardwareSettingsScreen> createState() => _HardwareSettingsScreenState();
}

class _HardwareSettingsScreenState extends State<HardwareSettingsScreen> {
  bool _loading = true;
  HardwareConfigModel _config = HardwareConfigModel();
  List<Printer> _printers = [];

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    final config = await HardwareConfigModel.load();
    final printers = await Printing.listPrinters();
    
    if (mounted) {
      setState(() {
        _config = config;
        _printers = printers;
        _loading = false;
      });
    }
  }

  Future<void> _saveConfig() async {
    await _config.save();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Hardware settings saved.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Hardware Terminals')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final printerNames = _printers.map((p) => p.name).toList();
    if (!printerNames.contains(_config.receiptPrinterName)) {
      printerNames.add(_config.receiptPrinterName ?? '');
    }
    if (!printerNames.contains(_config.labelPrinterName)) {
      printerNames.add(_config.labelPrinterName ?? '');
    }

    printerNames.removeWhere((name) => name.isEmpty);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Terminal Hardware Setup'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'These settings apply to THIS terminal only.',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            title: const Text('Keyboard HID Barcode Scanner'),
            subtitle: const Text('Listen for fast keystrokes simulating a barcode scanner.'),
            value: _config.scannerEnabled,
            onChanged: (val) {
              setState(() => _config.scannerEnabled = val);
              _saveConfig();
            },
          ),
          const Divider(),
          ListTile(
            title: const Text('Receipt Printer'),
            subtitle: const Text('Select the system printer used for POS receipts (e.g. RETSOL RTP-81).'),
            trailing: DropdownButton<String>(
              value: _config.receiptPrinterName == null || _config.receiptPrinterName!.isEmpty ? null : _config.receiptPrinterName,
              hint: const Text('Select Printer'),
              items: [
                const DropdownMenuItem<String>(value: null, child: Text('None (Use OS Dialog)')),
                ...printerNames.map((name) {
                  return DropdownMenuItem<String>(value: name, child: Text(name));
                }),
              ],
              onChanged: (val) {
                setState(() => _config.receiptPrinterName = val);
                _saveConfig();
              },
            ),
          ),
          const Divider(),
          ListTile(
            title: const Text('Label Printer'),
            subtitle: const Text('Select the system printer used for price tags (e.g. TVS LP 46 DLITE).'),
            trailing: DropdownButton<String>(
              value: _config.labelPrinterName == null || _config.labelPrinterName!.isEmpty ? null : _config.labelPrinterName,
              hint: const Text('Select Printer'),
              items: [
                const DropdownMenuItem<String>(value: null, child: Text('None (Use OS Dialog)')),
                ...printerNames.map((name) {
                  return DropdownMenuItem<String>(value: name, child: Text(name));
                }),
              ],
              onChanged: (val) {
                setState(() => _config.labelPrinterName = val);
                _saveConfig();
              },
            ),
          ),
          ListTile(
            title: const Text('Label Profile'),
            subtitle: const Text('The physical dimension of the label roll.'),
            trailing: DropdownButton<String>(
              value: _config.labelProfileId,
              items: const [
                DropdownMenuItem(value: '50x35', child: Text('50x35 mm')),
                DropdownMenuItem(value: '50x35_2up', child: Text('50x35 mm (2 Across)')),
                DropdownMenuItem(value: '50x50', child: Text('50x50 mm')),
              ],
              onChanged: (val) {
                if (val != null) {
                  setState(() => _config.labelProfileId = val);
                  _saveConfig();
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}
