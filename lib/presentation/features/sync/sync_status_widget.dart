import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:atomid/core/utils/formatters.dart';
import 'package:atomid/domain/services/sync_service.dart';
import 'package:atomid/presentation/features/auth/auth_screen.dart';
import 'package:atomid/presentation/providers/app_providers.dart';

/// Cloud indicator in the app bar. Reports the real queue state — it used to
/// show a green "Synced" regardless of what the queue was doing.
class SyncStatusWidget extends ConsumerWidget {
  const SyncStatusWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(syncStatusProvider);
    final signedIn = ref.watch(authStateProvider).value != null;
    final scheme = Theme.of(context).colorScheme;

    final (icon, color, tooltip) = _appearance(status, signedIn, scheme);

    return Tooltip(
      message: tooltip,
      child: InkWell(
        customBorder: const CircleBorder(),
        // Tapping while signed out goes straight to the one thing that would
        // make the indicator mean anything.
        onTap: () => signedIn
            ? _openSyncSheet(context, ref, status)
            : Navigator.push<void>(
                context,
                MaterialPageRoute(builder: (_) => const AuthScreen()),
              ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Badge(
            isLabelVisible: status.pending > 0 || status.dead > 0,
            label: Text('${status.dead > 0 ? status.dead : status.pending}'),
            backgroundColor: status.dead > 0 ? scheme.error : scheme.primary,
            child: status.phase == SyncPhase.syncing
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: color,
                    ),
                  )
                : Icon(icon, color: color),
          ),
        ),
      ),
    );
  }

  (IconData, Color, String) _appearance(
    SyncStatus status,
    bool signedIn,
    ColorScheme scheme,
  ) {
    if (!signedIn) {
      return (
        Icons.cloud_off_outlined,
        scheme.onSurfaceVariant,
        'Working on this device only — tap to connect cloud sync',
      );
    }

    return switch (status.phase) {
      SyncPhase.syncing => (
        Icons.cloud_sync_outlined,
        scheme.primary,
        status.message ?? 'Syncing…',
      ),
      SyncPhase.failed => (
        Icons.cloud_off,
        scheme.error,
        '${status.dead} ${status.dead == 1 ? 'record' : 'records'} could not sync',
      ),
      SyncPhase.retrying => (
        Icons.cloud_queue,
        Colors.orange.shade700,
        '${status.pending} waiting to upload',
      ),
      SyncPhase.offline => (
        Icons.cloud_off_outlined,
        scheme.onSurfaceVariant,
        status.message ?? 'Offline — changes are queued',
      ),
      SyncPhase.idle => (
        Icons.cloud_done_outlined,
        Colors.green.shade600,
        status.lastSuccess == null
            ? 'Connected'
            : 'Last synced ${Fmt.dateTime(status.lastSuccess!)}',
      ),
    };
  }

  void _openSyncSheet(BuildContext context, WidgetRef ref, SyncStatus status) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => _SyncSheet(status: status),
    );
  }
}

class _SyncSheet extends ConsumerWidget {
  final SyncStatus status;

  const _SyncSheet({required this.status});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final dead = ref.watch(deadSyncItemsProvider);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Cloud sync', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              status.lastSuccess == null
                  ? 'Not synced yet in this session.'
                  : 'Last synced ${Fmt.dateTime(status.lastSuccess!)}.',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                _Metric(
                  label: 'Waiting',
                  value: '${status.pending}',
                  color: scheme.primary,
                ),
                _Metric(
                  label: 'Failed',
                  value: '${status.dead}',
                  color: status.dead > 0 ? scheme.error : scheme.outline,
                ),
              ],
            ),
            if (dead.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.errorContainer.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${dead.length} ${dead.length == 1 ? 'record has' : 'records have'} '
                  'stopped retrying. They are still saved on this device.',
                  style: TextStyle(
                    fontSize: 13,
                    color: scheme.onErrorContainer,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    ref.read(syncServiceProvider).processQueue();
                  },
                  icon: const Icon(Icons.sync),
                  label: const Text('Sync now'),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    final syncService = ref.read(syncServiceProvider);
                    final messenger = ScaffoldMessenger.of(context);
                    Navigator.pop(context);
                    final applied = await syncService.pullAll();
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text(
                          applied == 0
                              ? 'Already up to date.'
                              : 'Updated $applied ${applied == 1 ? 'record' : 'records'} from the cloud.',
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.cloud_download_outlined),
                  label: const Text('Fetch from cloud'),
                ),
                if (dead.isNotEmpty)
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      ref.read(syncServiceProvider).retryFailed();
                    },
                    icon: const Icon(Icons.replay),
                    label: const Text('Retry failed'),
                  ),
                OutlinedButton.icon(
                  onPressed: () async {
                    final storageRepo = ref.read(storageRepositoryProvider);
                    final syncService = ref.read(syncServiceProvider);
                    final messenger = ScaffoldMessenger.of(context);
                    Navigator.pop(context);
                    await storageRepo.enqueueAllExistingDataForSync();
                    syncService.processQueue();
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text('Queued everything on this device.'),
                      ),
                    );
                  },
                  icon: const Icon(Icons.upload_outlined),
                  label: const Text('Upload everything'),
                ),
                TextButton.icon(
                  onPressed: () async {
                    final sessionService = ref.read(sessionServiceProvider);
                    final messenger = ScaffoldMessenger.of(context);
                    Navigator.pop(context);
                    await sessionService.logout();
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text('Signed out of cloud sync.'),
                      ),
                    );
                  },
                  icon: const Icon(Icons.logout),
                  label: const Text('Sign out'),
                  style: TextButton.styleFrom(foregroundColor: scheme.error),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _Metric({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.bold,
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
