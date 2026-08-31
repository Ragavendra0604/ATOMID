import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:atomid/core/utils/formatters.dart';
import 'package:atomid/domain/services/sync_service.dart';
import 'package:atomid/presentation/providers/app_providers.dart';
import 'package:atomid/data/models/sync_queue_model.dart';
import 'package:atomid/data/models/sync_log_model.dart';

class SyncStatusBar extends ConsumerStatefulWidget {
  const SyncStatusBar({super.key});

  @override
  ConsumerState<SyncStatusBar> createState() => _SyncStatusBarState();
}

class _SyncStatusBarState extends ConsumerState<SyncStatusBar> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(syncStatusProvider);

    // If there is no activity (idle or offline) and no pending items, hide the bar.
    if (status.phase != SyncPhase.syncing &&
        status.pending == 0 &&
        status.dead == 0) {
      // Return an empty widget to take up no space.
      return const SizedBox.shrink();
    }

    final scheme = Theme.of(context).colorScheme;
    final isSyncing = status.phase == SyncPhase.syncing;
    final hasFailed = status.dead > 0;

    final bgColor = hasFailed
        ? scheme.errorContainer
        : (isSyncing
              ? scheme.primaryContainer
              : scheme.surfaceContainerHighest);
    final fgColor = hasFailed
        ? scheme.onErrorContainer
        : (isSyncing ? scheme.onPrimaryContainer : scheme.onSurfaceVariant);

    String statusText;
    if (status.message != null && status.message!.isNotEmpty) {
      statusText = status.message!;
    } else if (isSyncing) {
      statusText = status.pending > 0
          ? 'Uploading ${status.pending} items...'
          : 'Syncing...';
    } else if (hasFailed) {
      statusText = '${status.dead} items failed to sync';
    } else {
      statusText = '${status.pending} items waiting to sync';
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      width: double.infinity,
      decoration: BoxDecoration(
        color: bgColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isSyncing)
              LinearProgressIndicator(
                backgroundColor: bgColor,
                color: scheme.primary,
                minHeight: 3,
              ),
            InkWell(
              onTap: () => setState(() => _isExpanded = !_isExpanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Icon(
                      isSyncing
                          ? Icons.cloud_sync
                          : (hasFailed ? Icons.cloud_off : Icons.cloud_queue),
                      color: fgColor,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        statusText,
                        style: TextStyle(
                          color: fgColor,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    Icon(
                      _isExpanded ? Icons.expand_more : Icons.expand_less,
                      color: fgColor,
                    ),
                  ],
                ),
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              child: _isExpanded
                  ? _ExpandedLogsPanel(fgColor: fgColor)
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExpandedLogsPanel extends ConsumerWidget {
  final Color fgColor;

  const _ExpandedLogsPanel({required this.fgColor});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendingItems = ref.watch(pendingSyncItemsProvider);
    final logs = ref.watch(syncLogProvider);

    // Sort logs descending (newest first)
    final sortedLogs = List<SyncLogModel>.from(logs)
      ..sort((a, b) => b.completedAt.compareTo(a.completedAt));

    return Container(
      constraints: const BoxConstraints(maxHeight: 250),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          if (pendingItems.isNotEmpty) ...[
            Text(
              'WAITING TO UPLOAD',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: fgColor.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 8),
            for (final item in pendingItems.take(5))
              _buildItemRow(
                icon: Icons.hourglass_empty,
                title: '${item.action} ${item.entityType}',
                subtitle: 'Queued',
                color: fgColor,
              ),
            if (pendingItems.length > 5)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  '...and ${pendingItems.length - 5} more',
                  style: TextStyle(
                    color: fgColor.withValues(alpha: 0.6),
                    fontSize: 12,
                  ),
                ),
              ),
            const SizedBox(height: 16),
          ],

          if (sortedLogs.isNotEmpty) ...[
            Text(
              'RECENTLY UPLOADED',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: fgColor.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 8),
            for (final log in sortedLogs.take(10))
              _buildItemRow(
                icon: log.status == 'SUCCESS'
                    ? Icons.check_circle
                    : Icons.error,
                title: '${log.operation} ${log.entityType}',
                subtitle: Fmt.dateTime(log.completedAt),
                color: log.status == 'SUCCESS'
                    ? Colors.green.shade600
                    : Colors.red.shade600,
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildItemRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: TextStyle(fontSize: 13, color: fgColor),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 11,
              color: fgColor.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}
