import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:atomid/core/utils/app_error.dart';
import 'package:atomid/core/utils/formatters.dart';
import 'package:atomid/core/utils/platform_io.dart';
import 'package:atomid/core/utils/responsive.dart';
import 'package:atomid/domain/services/backup_service.dart';
import 'package:atomid/presentation/providers/app_providers.dart';
import 'package:atomid/presentation/widgets/empty_state.dart';
import 'package:share_plus/share_plus.dart';

/// Taking a copy of everything, and putting one back.
class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  bool _busy = false;
  List<BackupResult> _backups = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    try {
      final backups = await ref.read(backupServiceProvider).listBackups();
      if (!mounted) return;
      setState(() => _backups = backups);
    } catch (error) {
      debugPrint('Could not list backups: $error');
    }
  }

  Future<void> _run(Future<String> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final message = await action();
      await _refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(describeError(error, fallback: 'That did not work.')),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _backupNow() => _run(() async {
    final result = await ref.read(backupServiceProvider).createBackup();
    return '${result.records} records saved (${_size(result.bytes)}).';
  });

  Future<void> _restore(BackupResult backup) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Restore this backup?'),
        content: Text(
          'Records from ${Fmt.dateTime(backup.takenAt)} will be written back. '
          'Anything with the same id is overwritten.\n\n'
          'Nothing is deleted: work done since this backup was taken stays '
          'where it is.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _run(() async {
      final counts = await ref
          .read(backupServiceProvider)
          .restoreBackup(backup.path);
      final total = counts.values.fold<int>(0, (n, c) => n + c);
      return total == 0
          ? 'That backup had nothing to restore.'
          : '$total records restored.';
    });
  }

  /// Hands the file to the OS share sheet.
  ///
  /// A backup sitting next to the data it protects survives a mistake but not
  /// a lost phone. Getting it off the device is the half people skip, so it is
  /// one tap here.
  Future<void> _share(BuildContext context, BackupResult backup) => _run(() async {
    final box = context.findRenderObject() as RenderBox?;
    final sharePositionOrigin = box != null
        ? box.localToGlobal(Offset.zero) & box.size
        : null;

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(backup.path)],
        text: 'Atomid backup — ${Fmt.dateTime(backup.takenAt)}',
        sharePositionOrigin: sharePositionOrigin,
      ),
    );
    return 'Backup shared.';
  });

  static String _size(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Backup and restore')),
      body: ListView(
        padding: ResponsivePadding.getScreenPadding(context),
        children: [
          Card(
            color: scheme.primaryContainer.withValues(alpha: 0.35),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.shield_outlined, color: scheme.primary),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'A backup is not the same as cloud sync',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Sync mirrors this device, so a deletion is mirrored too. '
                    'A backup is a moment you can return to. Take one before '
                    'anything you are unsure about.',
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (_busy)
                    const Center(child: CircularProgressIndicator())
                  else
                    FilledButton.icon(
                      onPressed: _backupNow,
                      icon: const Icon(Icons.save_alt, size: 18),
                      label: const Text('Back up now'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(46),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 22),

          Text(
            'ON THIS DEVICE',
            style: TextStyle(
              fontSize: 11.5,
              letterSpacing: 1.1,
              fontWeight: FontWeight.bold,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),

          if (_backups.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 24),
              child: EmptyState(
                icon: Icons.inventory_2_outlined,
                title: 'No backups yet',
                message:
                    'Take one now. The ten most recent are kept, and older '
                    'ones are removed automatically.',
              ),
            )
          else
            for (final backup in _backups)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: Text(Fmt.dateTime(backup.takenAt)),
                  subtitle: Text(_size(backup.bytes)),
                  trailing: Wrap(
                    spacing: 4,
                    children: [
                      IconButton(
                        tooltip: 'Copy file path',
                        icon: const Icon(Icons.copy_outlined, size: 20),
                        onPressed: () async {
                          await Clipboard.setData(
                            ClipboardData(text: backup.path),
                          );
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Path copied.')),
                          );
                        },
                      ),
                      if (!PlatformIo.isWindows &&
                          !PlatformIo.isLinux &&
                          !PlatformIo.isMacOS)
                        Builder(
                          builder: (ctx) => IconButton(
                            tooltip: 'Send a copy',
                            icon: const Icon(Icons.ios_share, size: 20),
                            onPressed: _busy ? null : () => _share(ctx, backup),
                          ),
                        ),
                      IconButton(
                        tooltip: 'Restore',
                        icon: const Icon(Icons.restore, size: 20),
                        onPressed: _busy ? null : () => _restore(backup),
                      ),
                    ],
                  ),
                ),
              ),

          const SizedBox(height: 24),
          Text(
            'Backups are plain JSON, so they can be opened and read without '
            'this app. Copy them somewhere else — a backup that only exists '
            'on the device it protects is not a backup.',
            style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
