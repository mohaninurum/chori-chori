import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/presence_model.dart';
import 'room_provider.dart';

abstract class BasePresenceRepository {
  Future<void> updatePresence(String roomId, String userId, {required bool isOnline});
  Stream<UserPresence?> watchPartnerPresence(String roomId, String currentUserId);
  Stream<List<UserPresence>> watchAllPresences(String roomId);
}

class FirestorePresenceRepository implements BasePresenceRepository {
  final FirebaseFirestore _firestore;

  FirestorePresenceRepository(this._firestore);

  CollectionReference _presenceCollection(String roomId) {
    return _firestore.collection('rooms').doc(roomId).collection('presence');
  }

  @override
  Future<void> updatePresence(String roomId, String userId, {required bool isOnline}) async {
    try {
      final presence = UserPresence(
        userId: userId,
        isOnline: isOnline,
        lastSeen: DateTime.now(),
      );
      await _presenceCollection(roomId)
          .doc(userId)
          .set(presence.toMap(), SetOptions(merge: true));
    } catch (e, st) {
      debugPrint('Error updating presence: $e\n$st');
    }
  }

  @override
  Stream<UserPresence?> watchPartnerPresence(String roomId, String currentUserId) {
    return _presenceCollection(roomId).snapshots().map((snapshot) {
      for (final doc in snapshot.docs) {
        if (doc.id != currentUserId) {
          final data = doc.data() as Map<String, dynamic>?;
          if (data != null) {
            return UserPresence.fromMap(data, doc.id);
          }
        }
      }
      return null;
    });
  }

  @override
  Stream<List<UserPresence>> watchAllPresences(String roomId) {
    return _presenceCollection(roomId).snapshots().map((snapshot) {
      return snapshot.docs.map((doc) {
        return UserPresence.fromMap(doc.data() as Map<String, dynamic>, doc.id);
      }).toList();
    });
  }
}

class MockPresenceRepository implements BasePresenceRepository {
  final Map<String, Map<String, UserPresence>> _presenceStore = {};
  final _controller = StreamController<void>.broadcast();

  @override
  Future<void> updatePresence(String roomId, String userId, {required bool isOnline}) async {
    _presenceStore.putIfAbsent(roomId, () => {});
    _presenceStore[roomId]![userId] = UserPresence(
      userId: userId,
      isOnline: isOnline,
      lastSeen: DateTime.now(),
    );
    _controller.add(null);
  }

  @override
  Stream<UserPresence?> watchPartnerPresence(String roomId, String currentUserId) async* {
    yield _getPartner(roomId, currentUserId);
    await for (final _ in _controller.stream) {
      yield _getPartner(roomId, currentUserId);
    }
  }

  UserPresence? _getPartner(String roomId, String currentUserId) {
    final roomMap = _presenceStore[roomId];
    if (roomMap == null) return null;
    for (final entry in roomMap.entries) {
      if (entry.key != currentUserId) {
        return entry.value;
      }
    }
    return null;
  }

  @override
  Stream<List<UserPresence>> watchAllPresences(String roomId) async* {
    yield _presenceStore[roomId]?.values.toList() ?? [];
    await for (final _ in _controller.stream) {
      yield _presenceStore[roomId]?.values.toList() ?? [];
    }
  }
}

final mockPresenceRepositoryProvider = Provider<MockPresenceRepository>((ref) {
  return MockPresenceRepository();
});

final presenceRepositoryProvider = Provider<BasePresenceRepository>((ref) {
  if (Firebase.apps.isEmpty) {
    return ref.watch(mockPresenceRepositoryProvider);
  }
  return FirestorePresenceRepository(ref.watch(firestoreProvider));
});

class PartnerPresenceQuery {
  final String roomId;
  final String currentUserId;

  const PartnerPresenceQuery({required this.roomId, required this.currentUserId});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PartnerPresenceQuery &&
          runtimeType == other.runtimeType &&
          roomId == other.roomId &&
          currentUserId == other.currentUserId;

  @override
  int get hashCode => roomId.hashCode ^ currentUserId.hashCode;
}

final partnerPresenceProvider = StreamProvider.autoDispose
    .family<UserPresence?, PartnerPresenceQuery>((ref, query) {
  return ref.watch(presenceRepositoryProvider).watchPartnerPresence(
        query.roomId,
        query.currentUserId,
      );
});
