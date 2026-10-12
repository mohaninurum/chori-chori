import 'package:cloud_firestore/cloud_firestore.dart';

enum RoomStatus { active, expired }

class Room {
  final String id;
  final String name;
  final DateTime createdAt;
  final DateTime expiresAt;
  final RoomStatus status;

  Room({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.expiresAt,
    this.status = RoomStatus.active,
  });

  Room copyWith({
    String? id,
    String? name,
    DateTime? createdAt,
    DateTime? expiresAt,
    RoomStatus? status,
  }) {
    return Room(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      expiresAt: expiresAt ?? this.expiresAt,
      status: status ?? this.status,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'createdAt': Timestamp.fromDate(createdAt),
      'expiresAt': Timestamp.fromDate(expiresAt),
      'status': status.name,
    };
  }

  factory Room.fromMap(Map<String, dynamic> map, String documentId) {
    DateTime parseDate(dynamic val, DateTime fallback) {
      if (val is Timestamp) return val.toDate();
      if (val is DateTime) return val;
      if (val is int) return DateTime.fromMillisecondsSinceEpoch(val);
      if (val is String) {
        final parsed = DateTime.tryParse(val);
        if (parsed != null) return parsed;
      }
      return fallback;
    }

    final now = DateTime.now();
    return Room(
      id: documentId,
      name: map['name'] as String? ?? '',
      createdAt: parseDate(map['createdAt'], now),
      expiresAt: parseDate(map['expiresAt'], now.add(const Duration(hours: 1))),
      status: RoomStatus.values.firstWhere(
        (e) => e.name == (map['status'] as String? ?? 'active'),
        orElse: () => RoomStatus.active,
      ),
    );
  }
}
