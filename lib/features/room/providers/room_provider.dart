import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/room_model.dart';
import 'dart:async';

final firestoreProvider = Provider<FirebaseFirestore>((ref) {
  return FirebaseFirestore.instance;
});

final roomRepositoryProvider = Provider<RoomRepository>((ref) {
  return RoomRepository(ref.watch(firestoreProvider));
});

class RoomRepository {
  final FirebaseFirestore _firestore;
  RoomRepository(this._firestore);

  Future<void> createRoom(Room room) async {
    await _firestore.collection('rooms').doc(room.id).set(room.toMap());
  }

  Future<Room?> getRoom(String id) async {
    final doc = await _firestore.collection('rooms').doc(id).get();
    if (doc.exists && doc.data() != null) {
      return Room.fromMap(doc.data()!, doc.id);
    }
    return null;
  }
  
  Stream<Room?> watchRoom(String id) {
    return _firestore.collection('rooms').doc(id).snapshots().map((doc) {
      if (doc.exists && doc.data() != null) {
        return Room.fromMap(doc.data()!, doc.id);
      }
      return null;
    });
  }
}

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

  Future<bool> joinRoom(String id, String passcode) async {
    state = const AsyncLoading();
    try {
      final room = await ref.read(roomRepositoryProvider).getRoom(id);
      if (room != null && room.status == RoomStatus.active && room.passcode == passcode) {
        if (DateTime.now().isBefore(room.expiresAt)) {
          state = AsyncData(room);
          return true;
        } else {
          state = AsyncError("Room has expired.", StackTrace.current);
          return false;
        }
      } else {
        state = AsyncError("Invalid room ID or passcode.", StackTrace.current);
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
