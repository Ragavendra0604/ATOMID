import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:hive_ce_flutter/hive_flutter.dart';

import 'package:atomid/core/utils/platform_io.dart';
import 'package:atomid/domain/services/auth_service.dart';

/// Per-install state: which device this is.
///
/// This used to carry a store id, a cloud role and an active operator, because
/// a shop could have many people and many tills. It has one user now, so the
/// only thing worth remembering across launches is the device tag — document
/// numbering needs it so two devices billing offline cannot both issue
/// invoice 0001.
class SessionService {
  static const _boxName = 'session';
  static const _keyDeviceId = 'deviceId';

  final AuthService _authService;

  late Box _sessionBox;
  StreamSubscription? _authSubscription;

  String _deviceId = '';

  /// Fires when the signed-in identity changes, so anything showing cloud
  /// state can re-resolve.
  final StreamController<void> _sessionChanges = StreamController.broadcast();
  Stream<void> get sessionChanges => _sessionChanges.stream;

  SessionService(this._authService);

  Future<void> init() async {
    _sessionBox = await _safeOpenBox(_boxName);

    final savedDevice = _sessionBox.get(_keyDeviceId);
    if (savedDevice is String && savedDevice.isNotEmpty) {
      _deviceId = savedDevice;
    } else {
      _deviceId = _generateDeviceId();
      await _sessionBox.put(_keyDeviceId, _deviceId);
    }

    _authSubscription = _authService.authStateChanges.listen((_) {
      _sessionChanges.add(null);
    });
  }

  Future<void> dispose() async {
    await _authSubscription?.cancel();
    await _sessionChanges.close();
  }

  Future<Box> _safeOpenBox(String boxName) async {
    try {
      return await Hive.openBox(boxName);
    } catch (e) {
      debugPrint('Session box failed to open ($e); retrying with recovery.');
      try {
        return await Hive.openBox(boxName, crashRecovery: true);
      } catch (_) {
        try {
          await Hive.deleteBoxFromDisk(boxName);
        } catch (_) {}
        return await Hive.openBox(boxName);
      }
    }
  }

  // --- Identity -------------------------------------------------------------

  String get deviceId => _deviceId;

  /// Scopes every cloud document. Null when signed out, which is what tells
  /// sync there is nowhere to write yet.
  String? get cloudUid => _authService.uid;

  String get deviceLabel {
    if (kIsWeb) return 'Web browser';
    if (PlatformIo.isAndroid) return 'Android device';
    if (PlatformIo.isIOS) return 'iPhone or iPad';
    if (PlatformIo.isWindows) return 'Windows PC';
    if (PlatformIo.isMacOS) return 'Mac';
    if (PlatformIo.isLinux) return 'Linux PC';
    return 'Unknown device';
  }

  Future<void> logout() => _authService.signOut();

  String _generateDeviceId() {
    final random = Random.secure();
    final entropy = List<int>.generate(
      4,
      (_) => random.nextInt(256),
    ).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return 'dev_${DateTime.now().millisecondsSinceEpoch}_$entropy';
  }
}
