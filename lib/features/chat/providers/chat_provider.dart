import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/message_model.dart';
import '../../room/providers/room_provider.dart';

abstract class BaseChatRepository {
  Future<void> sendMessage(String roomId, ChatMessage message);
  Stream<List<ChatMessage>> watchMessages(String roomId);
  Future<void> deleteMessage(String roomId, String messageId);
}

final chatRepositoryProvider = Provider<BaseChatRepository>((ref) {
  if (Firebase.apps.isEmpty) {
    return ref.watch(mockChatRepositoryProvider);
  }
  return ChatRepository(ref.watch(firestoreProvider));
});

class ChatRepository implements BaseChatRepository {
  final FirebaseFirestore _firestore;

  ChatRepository(this._firestore);

  @override
  Future<void> sendMessage(String roomId, ChatMessage message) async {
    final cleanRoomId = roomId.trim().toUpperCase();
    await _firestore
        .collection('rooms')
        .doc(cleanRoomId)
        .collection('messages')
        .doc(message.id)
        .set(message.toMap());
  }

  @override
  Stream<List<ChatMessage>> watchMessages(String roomId) {
    final cleanRoomId = roomId.trim().toUpperCase();
    return _firestore
        .collection('rooms')
        .doc(cleanRoomId)
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => ChatMessage.fromMap(doc.data(), doc.id)).toList();
    });
  }

  @override
  Future<void> deleteMessage(String roomId, String messageId) async {
    final cleanRoomId = roomId.trim().toUpperCase();
    await _firestore
        .collection('rooms')
        .doc(cleanRoomId)
        .collection('messages')
        .doc(messageId)
        .delete();
  }
}

class MockChatRepository implements BaseChatRepository {
  final Map<String, List<ChatMessage>> _roomMessages = {};
  final _controller = StreamController<List<ChatMessage>>.broadcast();

  @override
  Future<void> sendMessage(String roomId, ChatMessage message) async {
    final cleanRoomId = roomId.trim().toUpperCase();
    _roomMessages.putIfAbsent(cleanRoomId, () => []);
    _roomMessages[cleanRoomId]!.insert(0, message);
    _controller.add(List.from(_roomMessages[cleanRoomId]!));
  }

  @override
  Stream<List<ChatMessage>> watchMessages(String roomId) async* {
    final cleanRoomId = roomId.trim().toUpperCase();
    yield _roomMessages[cleanRoomId] ?? [];
    yield* _controller.stream;
  }

  @override
  Future<void> deleteMessage(String roomId, String messageId) async {
    final cleanRoomId = roomId.trim().toUpperCase();
    _roomMessages[cleanRoomId]?.removeWhere((m) => m.id == messageId);
    _controller.add(List.from(_roomMessages[cleanRoomId] ?? []));
  }
}

final mockChatRepositoryProvider = Provider<MockChatRepository>((ref) {
  return MockChatRepository();
});

final messagesStreamProvider = StreamProvider.autoDispose.family<List<ChatMessage>, String>((ref, roomId) {
  return ref.watch(chatRepositoryProvider).watchMessages(roomId);
});
