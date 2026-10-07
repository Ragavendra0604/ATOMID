import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/hardware/hardware_manager.dart';

class HardwareDiagnosticsScreen extends ConsumerWidget {
  const HardwareDiagnosticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hwManager = ref.watch(hardwareManagerProvider);
    final devices = hwManager.allDevices;

    return Scaffold(
      appBar: AppBar(title: const Text('Hardware Diagnostics')),
      body: ListView.builder(
        itemCount: devices.length,
        itemBuilder: (context, index) {
          final device = devices[index];
          return Card(
            margin: const EdgeInsets.all(8),
            child: ListTile(
              leading: Icon(
                device.status.name == 'connected'
                    ? Icons.check_circle
                    : Icons.error,
                color: device.status.name == 'connected'
                    ? Colors.green
                    : Colors.red,
              ),
              title: Text(device.name),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Model: ${device.model}\nStatus: ${device.status.name}\nConnection: ${device.connectionType.name}',
                  ),
                  if (device.statusMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: Text(
                        device.statusMessage!,
                        style: TextStyle(
                          color: device.status.name == 'error'
                              ? Colors.redAccent
                              : Colors.green,
                          fontSize: 13,
                        ),
                      ),
                    ),
                ],
              ),
              trailing: IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Refresh Status',
                onPressed: () async {
                  await device.checkStatus();
                  (context as Element).markNeedsBuild();
                },
              ),
            ),
          );
        },
      ),
    );
  }
}
