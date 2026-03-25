import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/room_model.dart';
import 'dart:async';

final firestoreProvider = Provider<FirebaseFirestore>((ref) {
  return FirebaseFirestore.instance;
});

abstract class BaseRoomRepository {
  Future<void> createRoom(Room room);
  Future<Room?> getRoom(String id);
  Stream<Room?> watchRoom(String id);
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
    final doc = await _firestore.collection('rooms').doc(id).get();
    if (doc.exists && doc.data() != null) {
      return Room.fromMap(doc.data()!, doc.id);
    }
    return null;
  }
  
  @override
  Stream<Room?> watchRoom(String id) {
    return _firestore.collection('rooms').doc(id).snapshots().map((doc) {
      if (doc.exists && doc.data() != null) {
        return Room.fromMap(doc.data()!, doc.id);
      }
      return null;
    });
  }
}

class MockRoomRepository implements BaseRoomRepository {
  final Map<String, Room> _rooms = {};

  @override
  Future<void> createRoom(Room room) async {
    _rooms[room.id] = room;
  }

  @override
  Future<Room?> getRoom(String id) async {
    return _rooms[id];
  }

  @override
  Stream<Room?> watchRoom(String id) async* {
    yield _rooms[id];
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

  Future<bool> createAndJoinRoom(Room room) async {
    state = const AsyncLoading();
    try {
      await ref.read(roomRepositoryProvider).createRoom(room);
      state = AsyncData(room);
      return true;
    } catch (e, st) {
      state = AsyncError(e, st);
      return false;
    }
  }

  Future<bool> joinRoom(String id) async {
    state = const AsyncLoading();
    try {
      final room = await ref.read(roomRepositoryProvider).getRoom(id);
      if (room != null && room.status == RoomStatus.active) {
        if (DateTime.now().isBefore(room.expiresAt)) {
          state = AsyncData(room);
          return true;
        } else {
          state = AsyncError("Room has expired.", StackTrace.current);
          return false;
        }
      } else {
        state = AsyncError("Invalid room ID.", StackTrace.current);
        return false;
      }
    } catch (e, st) {
      state = AsyncError(e, st);
      return false;
    }
  }
}

final currentRoomProvider = AsyncNotifierProvider<RoomNotifier, Room?>(() {
  return RoomNotifier();
});
