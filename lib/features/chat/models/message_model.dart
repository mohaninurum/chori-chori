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
    this.expiresInSeconds = 0,
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
    DateTime parseDate(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is DateTime) return val;
      if (val is int) return DateTime.fromMillisecondsSinceEpoch(val);
      if (val is String) {
        final d = DateTime.tryParse(val);
        if (d != null) return d;
      }
      return DateTime.now();
    }

    return ChatMessage(
      id: documentId,
      senderId: map['senderId']?.toString() ?? '',
      text: map['text']?.toString() ?? '',
      type: MessageType.values.firstWhere(
        (e) => e.name == map['type'],
        orElse: () => MessageType.text,
      ),
      createdAt: parseDate(map['createdAt']),
      expiresInSeconds: (map['expiresInSeconds'] as num?)?.toInt() ?? 0,
      isSecret: map['isSecret'] as bool? ?? false,
    );
  }
}
