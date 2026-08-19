import 'dart:async';
import 'dart:math' as math;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import 'package:atomid/core/utils/ids.dart';
import 'package:atomid/data/models/sync_log_model.dart';
import 'package:atomid/data/models/sync_queue_model.dart';
import 'package:atomid/data/repositories/firebase_repository.dart';
import 'package:atomid/data/repositories/storage_repository.dart';
import 'package:atomid/data/sync/entity_codec.dart';
import 'package:atomid/domain/services/auth_service.dart';
import 'package:atomid/domain/services/session_service.dart';

/// What the cloud indicator is showing.
enum SyncPhase {
  /// No cloud account attached — the app is running purely on-device.
  offline,

  /// Signed in, queue empty.
  idle,

  /// Actively uploading or downloading.
  syncing,

  /// Some items failed and are waiting out their backoff.
  retrying,

  /// Items have exhausted their retries and need attention.
  failed,
}

class SyncStatus {
  final SyncPhase phase;
  final int pending;
  final int dead;
  final DateTime? lastSuccess;
  final String? message;

  const SyncStatus({
    this.phase = SyncPhase.offline,
    this.pending = 0,
    this.dead = 0,
    this.lastSuccess,
    this.message,
  });

  SyncStatus copyWith({
    SyncPhase? phase,
    int? pending,
    int? dead,
    DateTime? lastSuccess,
    String? message,
    bool clearMessage = false,
  }) => SyncStatus(
    phase: phase ?? this.phase,
    pending: pending ?? this.pending,
    dead: dead ?? this.dead,
    lastSuccess: lastSuccess ?? this.lastSuccess,
    message: clearMessage ? null : (message ?? this.message),
  );

  bool get isHealthy => phase != SyncPhase.failed && dead == 0;
}

/// Moves records between the device and the cloud.
///
/// Upload is queue-driven with exponential backoff. Download is a pull on
/// sign-in and on demand — previously absent entirely, which meant a second
/// device or a reinstall started empty and stayed empty.
class SyncService {
  static const _batchSize = 20;
  static const _fallbackInterval = Duration(minutes: 2);

  final StorageRepository _storageRepo;
  final FirebaseRepository _firebaseRepo;
  final AuthService _authService;
  final SessionService _sessionService;

  StreamSubscription? _connectivitySubscription;
  StreamSubscription? _authSubscription;
  Timer? _syncTimer;
  bool _isSyncing = false;
  bool _isPulling = false;

  final StreamController<SyncStatus> _statusController =
      StreamController.broadcast();
  SyncStatus _status = const SyncStatus();

  SyncService(
    this._storageRepo,
    this._firebaseRepo,
    this._authService,
    this._sessionService,
  );

  Stream<SyncStatus> get statusStream => _statusController.stream;
  SyncStatus get status => _status;

  void _emit(SyncStatus next) {
    _status = next;
    if (!_statusController.isClosed) _statusController.add(next);
  }

  void _refreshCounts({SyncPhase? phase, String? message}) {
    final dead = _storageRepo.getDeadSyncItems().length;
    final pending = _storageRepo.getPendingSyncItems().length;
    _emit(
      _status.copyWith(
        phase:
            phase ??
            (dead > 0
                ? SyncPhase.failed
                : pending > 0
                ? SyncPhase.retrying
                : SyncPhase.idle),
        pending: pending,
        dead: dead,
        message: message,
        clearMessage: message == null,
      ),
    );
  }

  void start() {
    if (!_firebaseRepo.isInitialized) {
      _emit(
        const SyncStatus(
          phase: SyncPhase.offline,
          message: 'Cloud sync is unavailable on this platform.',
        ),
      );
      return;
    }

    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      results,
    ) {
      final online = results.any((r) => r != ConnectivityResult.none);
      if (online) {
        processQueue();
      } else {
        _emit(
          _status.copyWith(
            phase: SyncPhase.offline,
            message: 'No connection — changes are queued on this device.',
          ),
        );
      }
    });

    // A fresh sign-in is the moment a device needs the store's history.
    _authSubscription = _authService.authStateChanges.listen((user) async {
      if (user == null) {
        _emit(const SyncStatus(phase: SyncPhase.offline));
        return;
      }
      await pullAll();
      await processQueue();
    });

    _syncTimer = Timer.periodic(_fallbackInterval, (_) => processQueue());

    if (_authService.currentUser != null) {
      _refreshCounts();
      processQueue();
    }
  }

  Future<void> stop() async {
    await _connectivitySubscription?.cancel();
    await _authSubscription?.cancel();
    _syncTimer?.cancel();
    await _statusController.close();
  }

  // --- Upload ---------------------------------------------------------------

  Future<void> processQueue() async {
    // Signing in is what gives the queue somewhere to go. Until then the work
    // is captured locally and simply waits — nothing is lost by being offline.
    final uid = _sessionService.cloudUid;
    if (_isSyncing) return;
    if (uid == null) {
      _emit(
        _status.copyWith(
          phase: SyncPhase.offline,
          message: 'Sign in to back this device up to the cloud.',
        ),
      );
      return;
    }

    _isSyncing = true;
    try {
      final pendingItems = _storageRepo.getPendingSyncItems();
      if (pendingItems.isEmpty) {
        _refreshCounts(phase: SyncPhase.idle);
        return;
      }

      _refreshCounts(phase: SyncPhase.syncing);

      for (var i = 0; i < pendingItems.length; i += _batchSize) {
        final slice = pendingItems.skip(i).take(_batchSize).toList();
        if (!_firebaseRepo.isInitialized) break;

        final writes = <SyncWrite>[];
        final queued = <String>[];
        final startedAt = <String, DateTime>{};

        for (final item in slice) {
          if (item.retryCount >= SyncState.maxRetries) continue;
          if (_isBackingOff(item.lastAttempt, item.retryCount)) continue;

          final collection = EntityCodec.collectionFor(item.entityType);
          final docId = _documentIdFor(item);

          startedAt[item.id] = DateTime.now();

          if (item.action == 'DELETE') {
            writes.add(
              SyncWrite.delete(collection: collection, documentId: docId),
            );
            queued.add(item.id);
            continue;
          }

          final data = _storageRepo.getEntityJson(
            item.entityType,
            item.entityId,
          );
          if (data == null) {
            // The record was deleted locally before it ever uploaded.
            await _storageRepo.deleteSyncItem(item.id);
            continue;
          }

          writes.add(
            SyncWrite.put(
              collection: collection,
              documentId: docId,
              data: data,
            ),
          );
          queued.add(item.id);
        }

        if (queued.isEmpty) continue;

        for (final id in queued) {
          await _storageRepo.updateSyncItemStatus(id, SyncState.syncing);
        }

        try {
          await _firebaseRepo.commitBatch(
            uid: uid,
            writes: writes,
            sourceDevice: _sessionService.deviceId,
          );
          await _recordOutcome(slice, queued, startedAt, success: true);
        } catch (error) {
          debugPrint('Sync batch failed: $error');
          if (_isPermissionDenied(error)) {
            _emit(
              _status.copyWith(
                phase: SyncPhase.failed,
                message:
                    'The cloud refused this write. Your work is safe on '
                    'this device — try signing in again.',
              ),
            );
          }
          await _recordOutcome(
            slice,
            queued,
            startedAt,
            success: false,
            error: error.toString(),
          );
        }
      }

      final remaining = _storageRepo.getPendingSyncItems().length;
      if (remaining == 0) {
        _emit(
          _status.copyWith(
            phase: _storageRepo.getDeadSyncItems().isEmpty
                ? SyncPhase.idle
                : SyncPhase.failed,
            pending: 0,
            dead: _storageRepo.getDeadSyncItems().length,
            lastSuccess: DateTime.now(),
            clearMessage: true,
          ),
        );
      } else {
        _refreshCounts();
      }
    } finally {
      _isSyncing = false;
    }
  }

  /// Config records share one document per store rather than one per row.
  String _documentIdFor(SyncQueueItem item) {
    switch (item.entityType) {
      case 'SettingsModel':
        return 'settings';
      case 'CompanyModel':
        return 'company';
      case 'InvoiceSettingsModel':
        return 'invoice';
      case 'LoyaltySettingsModel':
        return 'loyalty';
      default:
        return item.entityId;
    }
  }

  bool _isBackingOff(DateTime? lastAttempt, int retryCount) {
    if (lastAttempt == null) return false;
    final waited = DateTime.now().difference(lastAttempt).inSeconds;
    final threshold = math.pow(2, retryCount).toInt() * 30;
    return waited < threshold;
  }

  Future<void> _recordOutcome(
    List<SyncQueueItem> slice,
    List<String> queued,
    Map<String, DateTime> startedAt, {
    required bool success,
    String? error,
  }) async {
    for (final id in queued) {
      final item = slice.firstWhere((x) => x.id == id);
      final began = startedAt[id] ?? DateTime.now();
      final ended = DateTime.now();

      if (success) {
        await _storageRepo.deleteSyncItem(id);
      } else {
        await _storageRepo.updateSyncItemStatus(
          id,
          SyncState.failed,
          retryCount: item.retryCount + 1,
          lastAttempt: ended,
        );
      }

      await _storageRepo.addSyncLog(
        SyncLogModel(
          id: Ids.generate(),
          entityType: item.entityType,
          entityId: item.entityId,
          operation: item.action,
          deviceId: _sessionService.deviceId,
          startedAt: began,
          completedAt: ended,
          durationMs: ended.difference(began).inMilliseconds,
          status: success ? 'SUCCESS' : 'FAILED',
          retryCount: success ? item.retryCount : item.retryCount + 1,
          error: error,
        ),
      );
    }
  }

  // --- Download -------------------------------------------------------------

  /// Fetches this account's records and merges them into local storage.
  ///
  /// Local records with unsent changes always win, so pulling can never
  /// discard work this device has not uploaded yet.
  ///
  /// By default this is *incremental*: only records changed since the last
  /// fully successful pull are fetched. Pass [full] to force a complete
  /// refresh — that is what the System Console's "Re-fetch store data" does,
  /// and what happens automatically when there is no trustworthy watermark.
  ///
  /// [since] overrides the stored watermark and exists for tests.
  Future<int> pullAll({DateTime? since, bool full = false}) async {
    if (_isPulling) return 0;

    final uid = _sessionService.cloudUid;
    if (uid == null) return 0;

    // Taken before the first fetch, not after the last. A record written
    // while the pull is in flight would otherwise fall between the two and
    // never be asked for again. Re-fetching a handful of records next time is
    // free — applyRemote is idempotent — whereas missing one is permanent.
    final startedAt = DateTime.now();
    final watermark = full ? null : (since ?? _sessionService.lastPulledAt);

    _isPulling = true;
    _emit(
      _status.copyWith(
        phase: SyncPhase.syncing,
        message: watermark == null
            ? 'Fetching your data…'
            : 'Checking for changes…',
      ),
    );

    var applied = 0;
    final failures = <String>[];
    var deniedCount = 0;

    try {
      for (final entityType in EntityCodec.pullOrder) {
        final collection = EntityCodec.collectionFor(entityType);
        // Config records carry no timestamp of their own, so they are always
        // fetched whole — four documents, and it sidesteps filtering on a
        // value the uploader invented.
        final entitySince = EntityCodec.alwaysFullPull.contains(entityType)
            ? null
            : watermark;
        try {
          await _firebaseRepo.fetchCollectionPages(
            uid: uid,
            collection: collection,
            since: entitySince,
            onPage: (documents) async {
              for (final document in documents) {
                final id = _localIdFor(entityType, document);
                if (id == null) continue;
                final changed = await _storageRepo.applyRemote(
                  entityType,
                  id,
                  document,
                );
                if (changed) applied++;
              }
            },
          );
        } catch (error) {
          debugPrint('Pull failed for $entityType: $error');
          failures.add(entityType);
          if (_isPermissionDenied(error)) deniedCount++;
        }
      }

      await _storageRepo.reconcileAfterPull();

      // A pull where nothing came back is not a success. Reporting one was the
      // same mistake as the indicator that always read "Synced".
      if (failures.isEmpty) {
        // Only now, and only because every collection answered. Advancing the
        // watermark past a partial pull would mean the records in the failed
        // collection are never requested again.
        await _sessionService.setLastPulledAt(startedAt);
        _emit(
          _status.copyWith(
            phase: SyncPhase.idle,
            lastSuccess: DateTime.now(),
            clearMessage: true,
          ),
        );
      } else {
        _emit(
          _status.copyWith(
            phase: SyncPhase.failed,
            message: deniedCount > 0
                ? 'This account cannot read this store in the cloud. Check '
                      'that the security rules are deployed and that the '
                      'account belongs to this store.'
                : 'Could not fetch ${failures.length} of '
                      '${EntityCodec.pullOrder.length} record types.',
          ),
        );
      }
      return applied;
    } finally {
      _isPulling = false;
    }
  }

  static bool _isPermissionDenied(Object error) =>
      error.toString().toLowerCase().contains('permission-denied') ||
      error.toString().toLowerCase().contains('permission_denied');

  String? _localIdFor(String entityType, Map<String, dynamic> document) {
    switch (entityType) {
      case 'SettingsModel':
        return document['id'] == 'settings' ? 'app_settings' : null;
      case 'CompanyModel':
        return document['id'] == 'company' ? 'profile' : null;
      case 'InvoiceSettingsModel':
        return document['id'] == 'invoice' ? 'invoice_settings' : null;
      case 'LoyaltySettingsModel':
        return document['id'] == 'loyalty' ? 'loyalty_settings' : null;
      default:
        final id = document['id'];
        return id is String && id.isNotEmpty ? id : null;
    }
  }

  /// Re-queues everything that gave up, for the "retry failed" action.
  Future<void> retryFailed() async {
    await _storageRepo.retryDeadSyncItems();
    _refreshCounts(phase: SyncPhase.retrying);
    await processQueue();
  }
}
