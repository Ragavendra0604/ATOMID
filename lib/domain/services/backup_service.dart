import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;

import 'package:atomid/core/utils/app_error.dart';
import 'package:atomid/core/utils/ids.dart';
import 'package:atomid/core/utils/platform_io.dart';
import 'package:atomid/data/repositories/storage_repository.dart';

/// What a finished backup looks like to the caller.
class BackupResult {
  final String path;
  final int records;
  final int bytes;
  final DateTime takenAt;

  const BackupResult({
    required this.path,
    required this.records,
    required this.bytes,
    required this.takenAt,
  });
}

/// Takes and restores a complete copy of this device's data.
///
/// Cloud sync is a live mirror, not a backup: it faithfully replicates a
/// mistake. Deleting a year of sales replicates the deletion. A backup is a
/// point in time you can return to, which is a different job, so it is kept on
/// the device (and wherever the operator copies it) rather than in the cloud.
///
/// The file is plain JSON on purpose. A backup nobody can read without this
/// exact app version is a hostage, not a safeguard — this one can be opened,
/// inspected and salvaged by hand.
class BackupService {
  /// Bumped only when the file layout changes in a way a reader must know
  /// about. Adding a field to a record does not count; the codecs default
  /// anything absent.
  static const int formatVersion = 1;

  static const String _folder = 'Backups';
  static const int _keepRecent = 10;

  final StorageRepository _storage;

  BackupService(this._storage);

  /// Writes a full snapshot and returns where it landed.
  Future<BackupResult> createBackup() async {
    if (kIsWeb) {
      throw const AppException(
        'Backups need a file system, which the browser build does not have. '
        'Use the desktop or mobile app.',
      );
    }

    final snapshot = _storage.exportSnapshot();
    final records = snapshot.values.fold<int>(0, (n, l) => n + l.length);

    final payload = <String, dynamic>{
      'formatVersion': formatVersion,
      'takenAt': DateTime.now().toIso8601String(),
      'deviceTag': _storage.deviceTag,
      'recordCount': records,
      'data': snapshot,
    };

    // Pretty-printed so the file stays salvageable by a human. The size cost
    // is worth it — these are small next to the images the app already writes.
    final bytes = utf8.encode(
      const JsonEncoder.withIndent('  ').convert(payload),
    );

    final directory = await _backupDirectory();
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    final file = PlatformFile('${directory.path}/atomid-$stamp.json');

    // Written to a temporary neighbour and moved into place, so a crash
    // half-way through leaves the previous backup intact rather than a
    // truncated file that looks like a backup and is not one.
    final staging = PlatformFile('${file.path}.${Ids.generate()}.part');
    await staging.writeAsBytes(bytes, flush: true);
    await staging.rename(file.path);

    await _pruneOldBackups(directory);

    return BackupResult(
      path: file.path,
      records: records,
      bytes: bytes.length,
      takenAt: DateTime.now(),
    );
  }

  /// Reads a backup file and writes its records back.
  ///
  /// Returns how many of each entity type were restored.
  Future<Map<String, int>> restoreBackup(String path) async {
    if (kIsWeb) {
      throw const AppException(
        'Restoring needs a file system, which the browser build does not have.',
      );
    }

    final file = PlatformFile(path);
    if (!await file.exists()) {
      throw const AppException('That backup file is no longer there.');
    }

    late final Map<String, dynamic> payload;
    try {
      payload = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    } catch (error) {
      debugPrint('Backup parse failed: $error');
      throw const AppException('That file is not a readable Atomid backup.');
    }

    final version = payload['formatVersion'];
    if (version is! int || version > formatVersion) {
      throw AppException(
        'That backup was written by a newer version of Atomid '
        '(format $version). Update the app, then restore it.',
      );
    }

    final data = payload['data'];
    if (data is! Map) {
      throw const AppException('That backup has no records in it.');
    }

    final snapshot = <String, List<Map<String, dynamic>>>{};
    for (final entry in data.entries) {
      final rows = entry.value;
      if (rows is! List) continue;
      snapshot[entry.key as String] = rows
          .whereType<Map>()
          .map((r) => r.cast<String, dynamic>())
          .toList();
    }

    return _storage.importSnapshot(snapshot);
  }

  /// Existing backups, newest first.
  Future<List<BackupResult>> listBackups() async {
    if (kIsWeb) return const [];

    final directory = await _backupDirectory();
    final files = await _backupFiles(directory);

    final results = <BackupResult>[];
    for (final file in files) {
      final stat = await file.stat();
      results.add(
        BackupResult(
          path: file.path,
          // Counting records would mean parsing every file to draw a list, so
          // the size stands in for it here; the count is in the file itself.
          records: 0,
          bytes: stat.size,
          takenAt: stat.modified,
        ),
      );
    }
    return results;
  }

  /// Where backups live, per platform.
  ///
  /// Android needs external storage specifically. The documents directory
  /// there is app-private: a file manager cannot see it, and — the part that
  /// matters — Android deletes it when the app is uninstalled. A backup that
  /// dies with the app it protects is not a backup, and the failure would only
  /// show up on the day somebody reinstalled to recover.
  Future<PlatformDirectory> _backupDirectory() async {
    String? base;

    if (PlatformIo.isAndroid) {
      base = await PlatformIo.getExternalStorageDirectoryPath();
    }
    base ??= await PlatformIo.getApplicationDocumentsDirectoryPath();

    final directory = PlatformDirectory('$base/Atomid Store/$_folder');
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  Future<List<PlatformFile>> _backupFiles(PlatformDirectory directory) async {
    final entries = await directory.list().toList();
    final files = entries
        .whereType<PlatformFile>()
        .where((f) => f.path.endsWith('.json'))
        .toList();
    files.sort((a, b) => b.path.compareTo(a.path));
    return files;
  }

  /// Keeps the most recent [_keepRecent] and removes the rest.
  ///
  /// Unbounded backups are their own failure: the disk fills, and the write
  /// that fails is the next backup.
  Future<void> _pruneOldBackups(PlatformDirectory directory) async {
    try {
      final files = await _backupFiles(directory);
      for (final stale in files.skip(_keepRecent)) {
        await stale.delete();
      }
    } catch (error) {
      // A backup that was written but could not be tidied up after is still a
      // backup. Never fail the operation over housekeeping.
      debugPrint('Could not prune old backups: $error');
    }
  }
}
