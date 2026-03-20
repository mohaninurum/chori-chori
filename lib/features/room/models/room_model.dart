import 'package:cloud_firestore/cloud_firestore.dart';

enum RoomStatus { active, expired }

class Room {
  final String id;
  final String name;
  final String passcode;
  final DateTime createdAt;
  final DateTime expiresAt;
  final RoomStatus status;

  Room({
    required this.id,
    required this.name,
    required this.passcode,
    required this.createdAt,
    required this.expiresAt,
    this.status = RoomStatus.active,
  });

  Room copyWith({
    String? id,
    String? name,
    String? passcode,
    DateTime? createdAt,
    DateTime? expiresAt,
    RoomStatus? status,
  }) {
    return Room(
      id: id ?? this.id,
      name: name ?? this.name,
      passcode: passcode ?? this.passcode,
      createdAt: createdAt ?? this.createdAt,
      expiresAt: expiresAt ?? this.expiresAt,
      status: status ?? this.status,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'passcode': passcode,
      'createdAt': Timestamp.fromDate(createdAt),
      'expiresAt': Timestamp.fromDate(expiresAt),
      'status': status.name,
    };
  }

  factory Room.fromMap(Map<String, dynamic> map, String documentId) {
    return Room(
      id: documentId,
      name: map['name'] ?? '',
      passcode: map['passcode'] ?? '',
      createdAt: (map['createdAt'] as Timestamp).toDate(),
      expiresAt: (map['expiresAt'] as Timestamp).toDate(),
      status: RoomStatus.values.firstWhere(
        (e) => e.name == map['status'],
        orElse: () => RoomStatus.active,
      ),
    );
  }
}
