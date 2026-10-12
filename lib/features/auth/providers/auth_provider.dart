import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'dart:async';

// Global cache for persistent unique device ID
String _cachedDeviceUserId = '';

/// Initializes or retrieves the unique, persistent device ID.
Future<String> getOrInitDeviceUserId() async {
  if (_cachedDeviceUserId.isNotEmpty && _cachedDeviceUserId != 'guest_user') {
    return _cachedDeviceUserId;
  }
  try {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString('local_device_user_id');
    if (id == null || id.isEmpty || id == 'guest_user') {
      id = 'dev_${const Uuid().v4().replaceAll('-', '').substring(0, 12)}';
      await prefs.setString('local_device_user_id', id);
    }
    _cachedDeviceUserId = id;
    return id;
  } catch (_) {
    if (_cachedDeviceUserId.isEmpty) {
      _cachedDeviceUserId = 'dev_${const Uuid().v4().replaceAll('-', '').substring(0, 12)}';
    }
    return _cachedDeviceUserId;
  }
}

/// Synchronous getter for device ID fallback.
String get currentDeviceUserId {
  if (_cachedDeviceUserId.isNotEmpty && _cachedDeviceUserId != 'guest_user') {
    return _cachedDeviceUserId;
  }
  _cachedDeviceUserId = 'dev_${const Uuid().v4().replaceAll('-', '').substring(0, 12)}';
  return _cachedDeviceUserId;
}

// Firebase Auth Instance
final firebaseAuthProvider = Provider<FirebaseAuth>((ref) {
  return FirebaseAuth.instance;
});

// Stream of Auth State Changes
final authStateChangesProvider = StreamProvider<User?>((ref) {
  if (Firebase.apps.isEmpty) {
    return Stream.value(null);
  }
  return ref.watch(firebaseAuthProvider).authStateChanges();
});

// Guaranteed Unique User ID Provider across the app (Never generic 'guest_user')
final userIdProvider = Provider<String>((ref) {
  final firebaseUser = ref.watch(authStateChangesProvider).value ?? FirebaseAuth.instance.currentUser;
  if (firebaseUser != null && firebaseUser.uid.isNotEmpty) {
    return firebaseUser.uid;
  }
  return currentDeviceUserId;
});

// A Notifier to handle Authentication tasks (Sign in Anonymously)
class AuthController extends AsyncNotifier<void> {
  @override
  FutureOr<void> build() {}

  Future<void> signInAnonymously() async {
    state = const AsyncLoading();
    try {
      await ref.read(firebaseAuthProvider).signInAnonymously();
      state = const AsyncData(null);
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }

  Future<void> signOut() async {
    await ref.read(firebaseAuthProvider).signOut();
  }
}

// Provider for AuthController
final authControllerProvider = AsyncNotifierProvider<AuthController, void>(() {
  return AuthController();
});
