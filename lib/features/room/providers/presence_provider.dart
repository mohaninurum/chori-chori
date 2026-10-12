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
    return _firestore.collection('rooms').doc(roomId.trim().toUpperCase()).collection('presence');
  }

  @override
  Future<void> updatePresence(String roomId, String userId, {required bool isOnline}) async {
    try {
      final cleanRoomId = roomId.trim().toUpperCase();
      final presence = UserPresence(
        userId: userId,
        isOnline: isOnline,
        lastSeen: DateTime.now(),
      );
      await _presenceCollection(cleanRoomId)
          .doc(userId)
          .set(presence.toMap(), SetOptions(merge: true));
    } catch (e, st) {
      debugPrint('Error updating presence: $e\n$st');
    }
  }

  @override
  Stream<UserPresence?> watchPartnerPresence(String roomId, String currentUserId) {
    final cleanRoomId = roomId.trim().toUpperCase();
    return _presenceCollection(cleanRoomId).snapshots().map((snapshot) {
      final candidates = <UserPresence>[];
      for (final doc in snapshot.docs) {
        if (doc.id != currentUserId && doc.id != 'guest_user') {
          final data = doc.data() as Map<String, dynamic>?;
          if (data != null) {
            candidates.add(UserPresence.fromMap(data, doc.id));
          }
        }
      }

      // Fallback if only guest_user document exists from another device
      if (candidates.isEmpty && currentUserId != 'guest_user') {
        for (final doc in snapshot.docs) {
          if (doc.id == 'guest_user') {
            final data = doc.data() as Map<String, dynamic>?;
            if (data != null) {
              candidates.add(UserPresence.fromMap(data, doc.id));
            }
          }
        }
      }

      if (candidates.isEmpty) return null;

      // Prioritize actively online partner, then most recently active
      candidates.sort((a, b) {
        if (a.isActive && !b.isActive) return -1;
        if (!a.isActive && b.isActive) return 1;
        return b.lastSeen.compareTo(a.lastSeen);
      });

      return candidates.first;
    });
  }

  @override
  Stream<List<UserPresence>> watchAllPresences(String roomId) {
    final cleanRoomId = roomId.trim().toUpperCase();
    return _presenceCollection(cleanRoomId).snapshots().map((snapshot) {
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
    final cleanRoomId = roomId.trim().toUpperCase();
    _presenceStore.putIfAbsent(cleanRoomId, () => {});
    _presenceStore[cleanRoomId]![userId] = UserPresence(
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
    final cleanRoomId = roomId.trim().toUpperCase();
    final roomMap = _presenceStore[cleanRoomId];
    if (roomMap == null) return null;
    final candidates = <UserPresence>[];
    for (final entry in roomMap.entries) {
      if (entry.key != currentUserId && entry.key != 'guest_user') {
        candidates.add(entry.value);
      }
    }
    if (candidates.isEmpty && currentUserId != 'guest_user') {
      if (roomMap.containsKey('guest_user')) {
        candidates.add(roomMap['guest_user']!);
      }
    }
    if (candidates.isEmpty) return null;
    candidates.sort((a, b) {
      if (a.isActive && !b.isActive) return -1;
      if (!a.isActive && b.isActive) return 1;
      return b.lastSeen.compareTo(a.lastSeen);
    });
    return candidates.first;
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
