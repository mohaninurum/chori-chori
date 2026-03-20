import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:async';

// Firebase Auth Instance
final firebaseAuthProvider = Provider<FirebaseAuth>((ref) {
  return FirebaseAuth.instance;
});

// Stream of Auth State Changes
final authStateChangesProvider = StreamProvider<User?>((ref) {
  return ref.watch(firebaseAuthProvider).authStateChanges();
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
