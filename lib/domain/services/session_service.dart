import 'dart:math';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:atomid/domain/services/auth_service.dart';
import 'package:atomid/data/repositories/firebase_repository.dart';

class SessionService {
  final AuthService _authService;
  final FirebaseRepository _firebaseRepo;
  late Box _sessionBox;
  String _deviceId = '';
  String? _currentUserRole;

  SessionService(this._authService, this._firebaseRepo);

  Future<void> init() async {
    _sessionBox = await Hive.openBox('session');
    
    // Initialize or retrieve deviceId
    final savedId = _sessionBox.get('deviceId');
    if (savedId != null) {
      _deviceId = savedId;
    } else {
      _deviceId = _generateDeviceId();
      await _sessionBox.put('deviceId', _deviceId);
    }

    // Listen to auth changes to fetch user role
    _authService.authStateChanges.listen((user) async {
      if (user != null) {
        await _fetchUserRole(user.uid);
      } else {
        _currentUserRole = null;
        await _sessionBox.delete('role');
      }
    });

    // Try to load cached role
    _currentUserRole = _sessionBox.get('role');
  }

  String get deviceId => _deviceId;
  String? get role => _currentUserRole;

  bool get isOwner => _currentUserRole == 'Owner';

  Future<void> _fetchUserRole(String uid) async {
    try {
      final doc = await _firebaseRepo.getCollection('users').doc(uid).get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>?;
        if (data != null && data.containsKey('role')) {
          _currentUserRole = data['role'];
          await _sessionBox.put('role', _currentUserRole);
        }
      }
    } catch (e) {
      // Offline or permission issue, fallback to cached role gracefully
      _currentUserRole = _sessionBox.get('role');
    }
  }

  Future<void> logout() async {
    _currentUserRole = null;
    await _sessionBox.delete('role');
    await _authService.signOut();
  }

  String _generateDeviceId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final random = Random().nextInt(1000000).toString().padLeft(6, '0');
    return 'dev_${timestamp}_$random';
  }
}
