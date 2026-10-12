import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/room_model.dart';
import 'dart:async';

final firestoreProvider = Provider<FirebaseFirestore>((ref) {
  return FirebaseFirestore.instance;
});

abstract class BaseRoomRepository {
  Future<void> createRoom(Room room);
  Future<Room?> getRoom(String id);
  Stream<Room?> watchRoom(String id);
  Future<void> deleteRoom(String id);
  Future<void> saveActiveRoomLocally(String roomId, DateTime expiresAt);
  Future<void> clearActiveRoomLocally();
  Future<void> cleanExpiredRooms();
}

class RoomRepository implements BaseRoomRepository {
  final FirebaseFirestore _firestore;
  RoomRepository(this._firestore);

  @override
  Future<void> createRoom(Room room) async {
    await _firestore.collection('rooms').doc(room.id).set(room.toMap());
  }

  @override
  Future<Room?> getRoom(String id) async {
    final cleanId = id.trim().replaceAll(RegExp(r'\s+'), '').toUpperCase();
    debugPrint('Searching for room with input: "$id", cleanId: "$cleanId"');

    try {
      // 1. Direct document lookup by cleaned ID
      final doc = await _firestore.collection('rooms').doc(cleanId).get();
      if (doc.exists && doc.data() != null) {
        return Room.fromMap(doc.data()!, doc.id);
      }

      // 2. Query by 'id' field in case doc ID differs
      final idQuery = await _firestore
          .collection('rooms')
          .where('id', isEqualTo: cleanId)
          .limit(1)
          .get();
      if (idQuery.docs.isNotEmpty) {
        return Room.fromMap(idQuery.docs.first.data(), idQuery.docs.first.id);
      }

      // 3. User might have entered the Room Name instead of Room ID
      final nameQuery = await _firestore
          .collection('rooms')
          .where('name', isEqualTo: id.trim())
          .limit(1)
          .get();
      if (nameQuery.docs.isNotEmpty) {
        return Room.fromMap(
          nameQuery.docs.first.data(),
          nameQuery.docs.first.id,
        );
      }

      // 4. Fallback for common 0 (zero) vs O (letter) visual confusion
      if (cleanId.contains('0') || cleanId.contains('O')) {
        final swapped = cleanId.contains('0')
            ? cleanId.replaceAll('0', 'O')
            : cleanId.replaceAll('O', '0');
        final swappedDoc = await _firestore
            .collection('rooms')
            .doc(swapped)
            .get();
        if (swappedDoc.exists && swappedDoc.data() != null) {
          return Room.fromMap(swappedDoc.data()!, swappedDoc.id);
        }
      }

      // 5. Fallback for 1 (one) vs I (capital i) visual confusion
      if (cleanId.contains('1') || cleanId.contains('I')) {
        final swapped = cleanId.contains('1')
            ? cleanId.replaceAll('1', 'I')
            : cleanId.replaceAll('I', '1');
        final swappedDoc = await _firestore
            .collection('rooms')
            .doc(swapped)
            .get();
        if (swappedDoc.exists && swappedDoc.data() != null) {
          return Room.fromMap(swappedDoc.data()!, swappedDoc.id);
        }
      }
    } catch (e, st) {
      debugPrint('Error querying room in Firestore: $e\n$st');
      rethrow;
    }

    return null;
  }

  @override
  Stream<Room?> watchRoom(String id) {
    final cleanId = id.trim().replaceAll(RegExp(r'\s+'), '').toUpperCase();
    return _firestore.collection('rooms').doc(cleanId).snapshots().map((doc) {
      if (doc.exists && doc.data() != null) {
        final room = Room.fromMap(doc.data()!, doc.id);
        if (room.status == RoomStatus.expired) return null;
        return room;
      }
      return null;
    });
  }

  @override
  Future<void> deleteRoom(String id) async {
    final cleanId = id.trim().replaceAll(RegExp(r'\s+'), '').toUpperCase();
    final roomRef = _firestore.collection('rooms').doc(cleanId);

    // 1. Immediately update status to expired so live listeners kick out participants
    try {
      await roomRef.update({'status': 'expired'});
    } catch (_) {}

    // 2. Delete all documents in subcollections
    Future<void> deleteCollection(CollectionReference col) async {
      try {
        final snapshot = await col.get();
        final batch = _firestore.batch();
        for (final doc in snapshot.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();
      } catch (e) {
        debugPrint('Error deleting subcollection: $e');
      }
    }

    await deleteCollection(roomRef.collection('messages'));
    await deleteCollection(roomRef.collection('presence'));
    await deleteCollection(roomRef.collection('extras'));
    await deleteCollection(roomRef.collection('callerCandidates'));
    await deleteCollection(roomRef.collection('calleeCandidates'));

    // Clean call session subcollection
    try {
      final sessionRef = roomRef.collection('call').doc('session');
      await deleteCollection(sessionRef.collection('callerCandidates'));
      await deleteCollection(sessionRef.collection('calleeCandidates'));
      await sessionRef.delete();
    } catch (_) {}

    // 3. Delete the root room document
    try {
      await roomRef.delete();
    } catch (e) {
      debugPrint('Error deleting root room document: $e');
    }
  }

  @override
  Future<void> saveActiveRoomLocally(String roomId, DateTime expiresAt) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_active_room_id', roomId.trim().toUpperCase());
      await prefs.setInt('last_active_room_expires_at', expiresAt.millisecondsSinceEpoch);
      debugPrint('Saved active room locally: $roomId, expiresAt: $expiresAt');
    } catch (e) {
      debugPrint('Error saving room locally: $e');
    }
  }

  @override
  Future<void> clearActiveRoomLocally() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('last_active_room_id');
      await prefs.remove('last_active_room_expires_at');
      debugPrint('Cleared locally tracked room.');
    } catch (e) {
      debugPrint('Error clearing local room: $e');
    }
  }

  @override
  Future<void> cleanExpiredRooms() async {
    try {
      // 1. Check if user's last room has expired while app was closed/offline
      final prefs = await SharedPreferences.getInstance();
      final localRoomId = prefs.getString('last_active_room_id');
      final localExpiresAt = prefs.getInt('last_active_room_expires_at');

      if (localRoomId != null) {
        final nowMs = DateTime.now().millisecondsSinceEpoch;
        if (localExpiresAt != null && nowMs >= localExpiresAt) {
          debugPrint('Locally tracked room $localRoomId has expired. Deleting from Firestore...');
          await deleteRoom(localRoomId);
          await clearActiveRoomLocally();
        }
      }

      // 2. Query Firestore for any other rooms that have expired
      final nowTimestamp = Timestamp.now();
      final snapshot = await _firestore
          .collection('rooms')
          .where('expiresAt', isLessThan: nowTimestamp)
          .limit(10)
          .get();

      for (final doc in snapshot.docs) {
        debugPrint('Auto-cleaning expired room from database: ${doc.id}');
        await deleteRoom(doc.id);
      }
    } catch (e) {
      debugPrint('Error cleaning expired rooms: $e');
    }
  }
}

class MockRoomRepository implements BaseRoomRepository {
  static final Map<String, Room> _sharedRooms = {};

  @override
  Future<void> createRoom(Room room) async {
    _sharedRooms[room.id] = room;
    _sharedRooms[room.name.toLowerCase()] = room;
  }

  @override
  Future<Room?> getRoom(String id) async {
    final cleanId = id.trim().replaceAll(RegExp(r'\s+'), '').toUpperCase();
    if (_sharedRooms.containsKey(cleanId)) return _sharedRooms[cleanId];
    if (_sharedRooms.containsKey(id.trim().toLowerCase()))
      return _sharedRooms[id.trim().toLowerCase()];
    return null;
  }

  @override
  Stream<Room?> watchRoom(String id) async* {
    final cleanId = id.trim().replaceAll(RegExp(r'\s+'), '').toUpperCase();
    yield _sharedRooms[cleanId];
  }

  @override
  Future<void> deleteRoom(String id) async {
    final cleanId = id.trim().replaceAll(RegExp(r'\s+'), '').toUpperCase();
    _sharedRooms.remove(cleanId);
  }

  @override
  Future<void> saveActiveRoomLocally(String roomId, DateTime expiresAt) async {}

  @override
  Future<void> clearActiveRoomLocally() async {}

  @override
  Future<void> cleanExpiredRooms() async {
    final now = DateTime.now();
    _sharedRooms.removeWhere((id, room) => now.isAfter(room.expiresAt));
  }
}

final mockRoomRepositoryProvider = Provider<MockRoomRepository>((ref) {
  return MockRoomRepository();
});

final roomRepositoryProvider = Provider<BaseRoomRepository>((ref) {
  if (Firebase.apps.isEmpty) {
    return ref.watch(mockRoomRepositoryProvider);
  }
  return RoomRepository(ref.watch(firestoreProvider));
});

class RoomNotifier extends AsyncNotifier<Room?> {
  @override
  FutureOr<Room?> build() => null;

  Future<void> closeAndDestroyRoom(String id) async {
    state = const AsyncLoading();
    try {
      await ref.read(roomRepositoryProvider).deleteRoom(id);
      await ref.read(roomRepositoryProvider).clearActiveRoomLocally();
      state = const AsyncData(null);
    } catch (e, st) {
      debugPrint('Error closing room: $e\n$st');
      state = AsyncError(e, st);
    }
  }

  Future<bool> createAndJoinRoom(Room room) async {
    state = const AsyncLoading();
    try {
      await ref.read(roomRepositoryProvider).createRoom(room);
      await ref.read(roomRepositoryProvider).saveActiveRoomLocally(room.id, room.expiresAt);
      state = AsyncData(room);
      return true;
    } catch (e, st) {
      debugPrint('Error creating room: $e\n$st');
      state = AsyncError(e, st);
      return false;
    }
  }

  Future<bool> joinRoom(String id) async {
    state = const AsyncLoading();
    try {
      final cleanId = id.trim().replaceAll(RegExp(r'\s+'), '').toUpperCase();
      debugPrint('Attempting to join room. Raw: "$id", Clean: "$cleanId"');

      final room = await ref.read(roomRepositoryProvider).getRoom(id);
      if (room == null) {
        debugPrint('Room not found for "$id"');
        state = AsyncError(
          "Invalid room ID. Please check the 6-character code.",
          StackTrace.current,
        );
        return false;
      }

      if (room.status != RoomStatus.active) {
        debugPrint('Room found but inactive: ${room.status}');
        state = AsyncError(
          "This room is no longer active.",
          StackTrace.current,
        );
        return false;
      }

      if (DateTime.now().isAfter(room.expiresAt)) {
        debugPrint('Room found but expired at ${room.expiresAt}. Purging...');
        await ref.read(roomRepositoryProvider).deleteRoom(room.id);
        await ref.read(roomRepositoryProvider).clearActiveRoomLocally();
        state = AsyncError("This room has expired and has been deleted.", StackTrace.current);
        return false;
      }

      await ref.read(roomRepositoryProvider).saveActiveRoomLocally(room.id, room.expiresAt);
      state = AsyncData(room);
      return true;
    } catch (e, st) {
      debugPrint('Error joining room: $e\n$st');
      state = AsyncError(e, st);
      return false;
    }
  }
}

final currentRoomProvider = AsyncNotifierProvider<RoomNotifier, Room?>(() {
  return RoomNotifier();
});
