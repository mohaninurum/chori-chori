import 'package:cloud_firestore/cloud_firestore.dart';

class UserPresence {
  final String userId;
  final bool isOnline;
  final DateTime lastSeen;
  final String? device;

  const UserPresence({
    required this.userId,
    required this.isOnline,
    required this.lastSeen,
    this.device,
  });

  /// Check if user is actively online (within 2-3 minute window for heartbeat)
  bool get isActive {
    if (!isOnline) return false;
    final diff = DateTime.now().difference(lastSeen);
    return diff.inMinutes < 3;
  }

  String get statusText {
    if (isActive) return 'Online';
    final diff = DateTime.now().difference(lastSeen);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return 'Offline';
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'isOnline': isOnline,
      'lastSeen': Timestamp.fromDate(lastSeen),
      if (device != null) 'device': device,
    };
  }

  factory UserPresence.fromMap(Map<String, dynamic> map, String docId) {
    DateTime parseDate(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is DateTime) return val;
      if (val is int) return DateTime.fromMillisecondsSinceEpoch(val);
      return DateTime.now();
    }

    return UserPresence(
      userId: map['userId'] ?? docId,
      isOnline: map['isOnline'] as bool? ?? false,
      lastSeen: parseDate(map['lastSeen']),
      device: map['device'] as String?,
    );
  }

  UserPresence copyWith({
    String? userId,
    bool? isOnline,
    DateTime? lastSeen,
    String? device,
  }) {
    return UserPresence(
      userId: userId ?? this.userId,
      isOnline: isOnline ?? this.isOnline,
      lastSeen: lastSeen ?? this.lastSeen,
      device: device ?? this.device,
    );
  }
}
