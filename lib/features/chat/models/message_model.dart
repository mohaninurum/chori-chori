import 'package:cloud_firestore/cloud_firestore.dart';

enum MessageType { text, image, voice }

class ChatMessage {
  final String id;
  final String senderId;
  final String text;
  final MessageType type;
  final DateTime createdAt;
  final int expiresInSeconds; // Self-destruct timer per message
  final bool isSecret; // Secret Mode tap-to-reveal

  ChatMessage({
    required this.id,
    required this.senderId,
    required this.text,
    required this.type,
    required this.createdAt,
    this.expiresInSeconds = 0, // 0 means it expires with the room
    this.isSecret = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'senderId': senderId,
      'text': text,
      'type': type.name,
      'createdAt': Timestamp.fromDate(createdAt),
      'expiresInSeconds': expiresInSeconds,
      'isSecret': isSecret,
    };
  }

  factory ChatMessage.fromMap(Map<String, dynamic> map, String documentId) {
    return ChatMessage(
      id: documentId,
      senderId: map['senderId'] ?? '',
      text: map['text'] ?? '',
      type: MessageType.values.firstWhere((e) => e.name == map['type'], orElse: () => MessageType.text),
      createdAt: (map['createdAt'] as Timestamp).toDate(),
      expiresInSeconds: map['expiresInSeconds'] ?? 0,
      isSecret: map['isSecret'] ?? false,
    );
  }
}
