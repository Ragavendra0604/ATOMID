import 'dart:async';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:atomid/data/repositories/storage_repository.dart';
import 'package:atomid/data/repositories/firebase_repository.dart';
import 'package:atomid/domain/services/auth_service.dart';
import 'package:atomid/domain/services/session_service.dart';
import 'package:atomid/data/models/sync_log_model.dart';

class SyncService {
  final StorageRepository _storageRepo;
  final FirebaseRepository _firebaseRepo;
  final AuthService _authService;
  final SessionService _sessionService;
  
  StreamSubscription? _connectivitySubscription;
  Timer? _syncTimer;
  bool _isSyncing = false;

  SyncService(this._storageRepo, this._firebaseRepo, this._authService, this._sessionService);

  void start() {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) {
      if (results.isNotEmpty && results.first != ConnectivityResult.none) {
        processQueue();
      }
    });

    // Also run every 2 minutes as a fallback
    _syncTimer = Timer.periodic(const Duration(minutes: 2), (_) {
      processQueue();
    });
  }

  void stop() {
    _connectivitySubscription?.cancel();
    _syncTimer?.cancel();
  }

  Future<void> processQueue() async {
    if (_isSyncing) return;
    
    final user = _authService.currentUser;
    if (user == null) return; // Not authenticated

    _isSyncing = true;
    try {
      final pendingItems = _storageRepo.getPendingSyncItems();
      if (pendingItems.isEmpty) return;

      // Process in batches of 10
      final batchSize = 10;
      for (var i = 0; i < pendingItems.length; i += batchSize) {
        final batchItems = pendingItems.skip(i).take(batchSize).toList();
        final batch = _firebaseRepo.getBatch();
        
        if (batch == null) break;

        final itemsToMarkSyncing = <String>[];
        final startedAtMap = <String, DateTime>{};

        for (var item in batchItems) {
          if (item.retryCount >= 5) continue;
          
          // Exponential backoff
          if (item.lastAttempt != null) {
            final minutesSinceLastAttempt = DateTime.now().difference(item.lastAttempt!).inMinutes;
            final backoffThreshold = math.pow(2, item.retryCount);
            if (minutesSinceLastAttempt < backoffThreshold) {
              continue; 
            }
          }
          
          final collection = _getCollectionForType(item.entityType);
          
          startedAtMap[item.id] = DateTime.now();
          if (item.action == 'DELETE') {
            batch.delete(_firebaseRepo.getCollection(collection).doc(item.entityId));
            itemsToMarkSyncing.add(item.id);
          } else {
            final data = _storageRepo.getEntityJson(item.entityType, item.entityId);
            if (data != null) {
              batch.set(_firebaseRepo.getCollection(collection).doc(item.entityId), data, SetOptions(merge: true));
              itemsToMarkSyncing.add(item.id);
            }
          }
        }

        if (itemsToMarkSyncing.isEmpty) continue;

        for (var id in itemsToMarkSyncing) {
          await _storageRepo.updateSyncItemStatus(id, 'SYNCING');
        }

        try {
          await batch.commit();
          for (var id in itemsToMarkSyncing) {
            await _storageRepo.deleteSyncItem(id);
            
            final originalItem = pendingItems.firstWhere((x) => x.id == id);
            final startedAt = startedAtMap[id] ?? DateTime.now();
            final completedAt = DateTime.now();
            
            await _storageRepo.addSyncLog(SyncLogModel(
              id: DateTime.now().millisecondsSinceEpoch.toString() + originalItem.entityId,
              entityType: originalItem.entityType,
              entityId: originalItem.entityId,
              operation: originalItem.action,
              deviceId: _sessionService.deviceId,
              startedAt: startedAt,
              completedAt: completedAt,
              durationMs: completedAt.difference(startedAt).inMilliseconds,
              status: 'SUCCESS',
              retryCount: originalItem.retryCount,
            ));
          }
        } catch (e) {
          for (var id in itemsToMarkSyncing) {
            final originalItem = pendingItems.firstWhere((x) => x.id == id);
            await _storageRepo.updateSyncItemStatus(
              id, 
              'FAILED',
              retryCount: originalItem.retryCount + 1,
              lastAttempt: DateTime.now(),
            );
            
            final startedAt = startedAtMap[id] ?? DateTime.now();
            final completedAt = DateTime.now();
            
            await _storageRepo.addSyncLog(SyncLogModel(
              id: DateTime.now().millisecondsSinceEpoch.toString() + originalItem.entityId,
              entityType: originalItem.entityType,
              entityId: originalItem.entityId,
              operation: originalItem.action,
              deviceId: _sessionService.deviceId,
              startedAt: startedAt,
              completedAt: completedAt,
              durationMs: completedAt.difference(startedAt).inMilliseconds,
              status: 'FAILED',
              retryCount: originalItem.retryCount + 1,
              error: e.toString(),
            ));
          }
        }
      }
    } finally {
      _isSyncing = false;
    }
  }

  String _getCollectionForType(String entityType) {
    switch (entityType) {
      case 'Customer': return 'customers';
      case 'Sale': return 'sales';
      case 'LoyaltyTransaction': return 'loyaltyTransactions';
      case 'InventoryMovement': return 'inventoryMovements';
      case 'SettingsModel': return 'settings';
      case 'CompanyModel': return 'company';
      case 'ExpenseCategory': return 'expenseCategories';
      default: return '${entityType.toLowerCase()}s';
    }
  }
}
