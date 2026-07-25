import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:atomid/presentation/providers/app_providers.dart';
import 'package:atomid/presentation/features/sync/cloud_login_dialog.dart';

class SyncStatusWidget extends ConsumerWidget {
  const SyncStatusWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(syncStatusProvider);
    final authState = ref.watch(authStateProvider);

    IconData icon;
    Color color;
    String message = status;
    bool isLoggedIn = authState.value != null;

    if (!isLoggedIn) {
      icon = Icons.cloud_off;
      color = Colors.grey;
      message = 'Offline - Tap to login to Cloud';
    } else if (status == 'Synced') {
      icon = Icons.cloud_done;
      color = Colors.green;
    } else if (status == 'Syncing...') {
      icon = Icons.cloud_upload;
      color = Colors.blue;
    } else {
      icon = Icons.cloud_off;
      color = Colors.orange;
    }

    return Tooltip(
      message: message,
      child: InkWell(
        onTap: () {
          if (!isLoggedIn) {
            showDialog(
              context: context,
              builder: (_) => const CloudLoginDialog(),
            );
          } else {
            showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Cloud Sync'),
                content: const Text('You are currently logged in and syncing to the cloud.'),
                actions: [
                  TextButton(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await ref.read(authServiceProvider).signOut();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Logged out successfully')),
                        );
                      }
                    },
                    child: const Text('Logout', style: TextStyle(color: Colors.red)),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      ref.read(syncServiceProvider).processQueue();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Manual sync triggered')),
                      );
                    },
                    child: const Text('Sync Now'),
                  ),
                  ElevatedButton(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await ref.read(storageRepositoryProvider).enqueueAllExistingDataForSync();
                      ref.read(syncServiceProvider).processQueue();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('All old data queued and syncing!')),
                        );
                      }
                    },
                    child: const Text('Force Sync Old Data'),
                  ),
                ],
              ),
            );
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Icon(icon, color: color),
        ),
      ),
    );
  }
}
