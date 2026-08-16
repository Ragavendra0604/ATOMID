import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:atomid/core/utils/formatters.dart';
import 'package:atomid/core/utils/responsive.dart';
import 'package:atomid/data/models/sync_log_model.dart';
import 'package:atomid/domain/services/sync_service.dart';
import 'package:atomid/presentation/providers/app_providers.dart';
import 'package:atomid/presentation/widgets/empty_state.dart';

/// System administration, separate from business administration.
///
/// Shows only system records — sync outcomes, sign-in history, queue and
/// storage health. Nothing here reports takings, stock or customers, so the
/// screen can be handed to a technician who has no business access at all.
class SystemConsoleScreen extends ConsumerStatefulWidget {
  const SystemConsoleScreen({super.key});

  @override
  ConsumerState<SystemConsoleScreen> createState() =>
      _SystemConsoleScreenState();
}

class _SystemConsoleScreenState extends ConsumerState<SystemConsoleScreen> {
  bool _busy = false;

  Future<void> _runOperation(
    String label,
    Future<void> Function() action,
  ) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$label completed.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$label failed: $error'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('System'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Health'),
              Tab(text: 'Sync log'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _HealthTab(busy: _busy, onRun: _runOperation, canOperate: true),
            const _SyncLogTab(),
          ],
        ),
      ),
    );
  }
}

class _HealthTab extends ConsumerWidget {
  final bool busy;
  final bool canOperate;
  final Future<void> Function(String, Future<void> Function()) onRun;

  const _HealthTab({
    required this.busy,
    required this.canOperate,
    required this.onRun,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(syncStatusProvider);
    final repo = ref.watch(storageRepositoryProvider);
    final sync = ref.watch(syncServiceProvider);
    final failures = ref.watch(syncFailureLogProvider);
    final session = ref.watch(sessionServiceProvider);

    return ListView(
      padding: ResponsivePadding.getScreenPadding(context),
      children: [
        _StatusCard(status: status),
        const SizedBox(height: 16),

        _SectionTitle('Queue'),
        _StatRow(label: 'Waiting to upload', value: '${status.pending}'),
        _StatRow(
          label: 'Given up (dead letter)',
          value: '${status.dead}',
          emphasise: status.dead > 0,
        ),
        _StatRow(label: 'Recent failures logged', value: '${failures.length}'),

        const SizedBox(height: 16),
        _SectionTitle('Device'),
        _StatRow(label: 'Device tag', value: session.deviceId),
        _StatRow(
          label: 'Cloud account',
          value: session.cloudUid ?? 'Not signed in',
        ),
        _StatRow(
          label: 'Last successful sync',
          value: status.lastSuccess == null
              ? 'Never'
              : Fmt.dateTime(status.lastSuccess!),
        ),

        const SizedBox(height: 16),
        _SectionTitle('Storage'),
        _StatRow(
          label: 'Boxes rebuilt after damage',
          value: repo.recoveredBoxes.isEmpty
              ? 'None'
              : repo.recoveredBoxes.join(', '),
          emphasise: repo.recoveredBoxes.isNotEmpty,
        ),

        const SizedBox(height: 24),
        _SectionTitle('Operations'),
        if (!canOperate)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'This account can view system health but not act on it.',
            ),
          )
        else ...[
          if (busy)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            FilledButton.tonalIcon(
              onPressed: () =>
                  onRun('Retry failed sync items', sync.retryFailed),
              icon: const Icon(Icons.refresh),
              label: const Text('Retry failed items'),
            ),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              onPressed: () => onRun('Push queued changes', sync.processQueue),
              icon: const Icon(Icons.cloud_upload_outlined),
              label: const Text('Push queued changes now'),
            ),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              onPressed: () =>
                  onRun('Re-fetch store data', () => sync.pullAll()),
              icon: const Icon(Icons.cloud_download_outlined),
              label: const Text('Re-fetch from cloud'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => onRun('Clear sync log', repo.clearSyncLogs),
              icon: const Icon(Icons.delete_sweep_outlined),
              label: const Text('Clear sync log'),
            ),
          ],
        ],
        const SizedBox(height: 24),
      ],
    );
  }
}

class _SyncLogTab extends ConsumerWidget {
  const _SyncLogTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logs = ref.watch(syncLogProvider);

    if (logs.isEmpty) {
      return const EmptyState(
        icon: Icons.receipt_long_outlined,
        title: 'No sync activity yet',
        message:
            'Once this device uploads or downloads records, every attempt '
            'is listed here with how long it took and why it failed.',
      );
    }

    return ListView.separated(
      itemCount: logs.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) => _SyncLogTile(log: logs[index]),
    );
  }
}

class _SyncLogTile extends StatelessWidget {
  final SyncLogModel log;

  const _SyncLogTile({required this.log});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final failed = log.status != 'SUCCESS';

    return ListTile(
      leading: Icon(
        failed ? Icons.error_outline : Icons.check_circle_outline,
        color: failed ? scheme.error : scheme.primary,
      ),
      title: Text('${log.operation} ${log.entityType}'),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${Fmt.dateTime(log.completedAt)} · ${log.durationMs}ms'
            '${log.retryCount > 0 ? ' · retry ${log.retryCount}' : ''}',
          ),
          if (log.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                log.error!,
                style: TextStyle(color: scheme.error, fontSize: 12),
              ),
            ),
        ],
      ),
      isThreeLine: log.error != null,
    );
  }
}

class _StatusCard extends StatelessWidget {
  final SyncStatus status;

  const _StatusCard({required this.status});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, colour, label) = switch (status.phase) {
      SyncPhase.idle => (Icons.cloud_done_outlined, scheme.primary, 'Healthy'),
      SyncPhase.syncing => (Icons.sync, scheme.primary, 'Syncing'),
      SyncPhase.retrying => (Icons.schedule, scheme.tertiary, 'Retrying'),
      SyncPhase.failed => (
        Icons.error_outline,
        scheme.error,
        'Needs attention',
      ),
      SyncPhase.offline => (
        Icons.cloud_off_outlined,
        scheme.onSurfaceVariant,
        'Device only',
      ),
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, color: colour, size: 32),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: colour,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (status.message != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(status.message!),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;

  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8, top: 4),
    child: Text(
      text,
      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
    ),
  );
}

class _StatRow extends StatelessWidget {
  final String label;
  final String value;
  final bool emphasise;

  const _StatRow({
    required this.label,
    required this.value,
    this.emphasise = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: emphasise ? scheme.error : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
