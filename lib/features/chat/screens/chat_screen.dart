import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import '../../auth/providers/auth_provider.dart';
import '../../room/models/presence_model.dart';
import '../../room/providers/presence_provider.dart';
import '../../room/providers/room_provider.dart';
import '../../room/widgets/partner_presence_badge.dart';
import '../../room/widgets/smart_expiry_timer.dart';
import '../../video_call/providers/webrtc_provider.dart';
import '../providers/chat_provider.dart';
import '../models/message_model.dart';
import '../widgets/message_bubble.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/router/routes.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> with WidgetsBindingObserver {
  final _messageController = TextEditingController();
  bool _isSecretMode = false;
  int _expiresInSeconds = 0;
  Timer? _heartbeatTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ensureAuth();
    _startHeartbeat();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setPresence(true);
    });
  }

  void _startHeartbeat() {
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      _setPresence(true);
    });
  }

  void _setPresence(bool isOnline) {
    final room = ref.read(currentRoomProvider).value;
    final user = ref.read(authStateChangesProvider).value ?? FirebaseAuth.instance.currentUser;
    final roomId = room?.id;
    final userId = user?.uid ?? 'guest_user';

    if (roomId != null) {
      ref.read(presenceRepositoryProvider).updatePresence(
            roomId,
            userId,
            isOnline: isOnline,
          );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _setPresence(true);
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _setPresence(false);
    }
  }

  void _ensureAuth() async {
    try {
      if (Firebase.apps.isNotEmpty && FirebaseAuth.instance.currentUser == null) {
        await FirebaseAuth.instance.signInAnonymously();
      }
    } catch (e) {
      debugPrint('Anonymous sign-in in ChatScreen failed: $e');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _heartbeatTimer?.cancel();
    _setPresence(false);
    _messageController.dispose();
    super.dispose();
  }

  void _confirmCloseRoom() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.backgroundDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: Colors.redAccent.withOpacity(0.5), width: 1.5),
        ),
        title: const Row(
          children: [
            Icon(Icons.delete_forever, color: Colors.redAccent, size: 28),
            SizedBox(width: 10),
            Text('Close & Delete Room?', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text(
          'Room close karne par:\n\n'
          '• Chat se dono users turant bahar ho jayenge.\n'
          '• Database se saare messages, notes aur data permanently delete ho jayenge.',
          style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            icon: const Icon(Icons.delete_forever, size: 18),
            label: const Text('Close & Delete Data', style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: () {
              Navigator.pop(ctx);
              _destroyRoom();
            },
          ),
        ],
      ),
    );
  }

  void _destroyRoom() async {
    final room = ref.read(currentRoomProvider).value;
    _setPresence(false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Room closing... Database se saara data delete ho raha hai.'),
          backgroundColor: Colors.redAccent,
          duration: Duration(seconds: 2),
        ),
      );
    }

    if (room != null) {
      await ref.read(currentRoomProvider.notifier).closeAndDestroyRoom(room.id);
    }

    if (mounted) {
      context.go(Routes.home);
    }
  }

  void _onRoomExpiredOrDeleted() {
    _setPresence(false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Room close ho chuka hai aur database se data delete ho gaya hai.'),
          backgroundColor: Colors.redAccent,
          duration: Duration(seconds: 3),
        ),
      );
      context.go(Routes.home);
    }
  }

  void _onRoomExpired() {
    final room = ref.read(currentRoomProvider).value;
    if (room != null) {
      ref.read(currentRoomProvider.notifier).closeAndDestroyRoom(room.id);
    }
    _onRoomExpiredOrDeleted();
  }

  void _sendMessage() {
    if (_messageController.text.trim().isEmpty) return;

    final roomState = ref.read(currentRoomProvider);
    final user = ref.read(authStateChangesProvider).value ?? FirebaseAuth.instance.currentUser;
    final roomId = roomState.value?.id;
    final userId = user?.uid ?? 'guest_user';

    if (roomId != null) {
      final message = ChatMessage(
        id: const Uuid().v4(),
        senderId: userId,
        text: _messageController.text.trim(),
        type: MessageType.text,
        createdAt: DateTime.now(),
        expiresInSeconds: _expiresInSeconds,
        isSecret: _isSecretMode,
      );

      ref.read(chatRepositoryProvider).sendMessage(roomId, message);
      _messageController.clear();
      _setPresence(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final roomState = ref.watch(currentRoomProvider);
    final room = roomState.value;
    final user = ref.watch(authStateChangesProvider).value ?? FirebaseAuth.instance.currentUser;

    if (room == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final currentUserId = user?.uid ?? 'guest_user';

    final liveRoomAsync = ref.watch(roomRepositoryProvider).watchRoom(room.id);
    final messagesAsync = ref.watch(messagesStreamProvider(room.id));
    final partnerPresenceAsync = ref.watch(
      partnerPresenceProvider(
        PartnerPresenceQuery(roomId: room.id, currentUserId: currentUserId),
      ),
    );
    final callSessionAsync = ref.watch(callSessionStreamProvider(room.id));
    final callData = callSessionAsync.value;
    final isIncomingCall = callData != null &&
        callData['status'] == 'calling' &&
        callData['callerId'] != currentUserId;

    return StreamBuilder(
      stream: liveRoomAsync,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.active && (!snapshot.hasData || snapshot.data == null)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _onRoomExpiredOrDeleted();
          });
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        return Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        room.name,
                        style: const TextStyle(fontSize: 17, color: AppTheme.textPrimary),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    PartnerPresenceBadge(
                      presence: partnerPresenceAsync.value,
                      compact: true,
                    ),
                  ],
                ),
                InkWell(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: room.name));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Room Name "${room.name}" copied to clipboard!'),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Room: ${room.name}', style: const TextStyle(fontSize: 12, color: AppTheme.secondaryNeon)),
                      const SizedBox(width: 4),
                      const Icon(Icons.copy, size: 12, color: AppTheme.secondaryNeon),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              Center(
                child: Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: SmartExpiryTimer(
                    expiresAt: room.expiresAt,
                    onExpired: _onRoomExpired,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.favorite, color: Colors.pinkAccent),
                onPressed: () => context.push(Routes.loveMeter),
              ),
              IconButton(
                icon: const Icon(Icons.note_alt, color: AppTheme.secondaryNeon),
                onPressed: () => context.push(Routes.sharedNotes),
              ),
              IconButton(
                icon: Icon(
                  Icons.videocam,
                  color: isIncomingCall ? const Color(0xFF00FF88) : AppTheme.primaryNeon,
                ),
                onPressed: () {
                  context.push(Routes.videoCall);
                },
              ),
              IconButton(
                icon: const Icon(Icons.delete_forever, color: Colors.redAccent),
                tooltip: 'Close & Delete Room',
                onPressed: _confirmCloseRoom,
              ),
            ],
          ),
          body: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [AppTheme.backgroundDark, AppTheme.backgroundLight],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: Column(
              children: [
                if (isIncomingCall)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF2A0845), Color(0xFF6441A5)],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFF00FF88), width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF00FF88).withOpacity(0.3),
                          blurRadius: 10,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white12,
                          ),
                          child: const Icon(Icons.videocam, color: Color(0xFF00FF88), size: 22),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Incoming Video Call',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                              Text(
                                'Partner is calling you...',
                                style: TextStyle(color: Colors.white70, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00FF88),
                            foregroundColor: Colors.black87,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          ),
                          icon: const Icon(Icons.call, size: 16),
                          label: const Text('Join', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                          onPressed: () => context.push(Routes.videoCall),
                        ),
                      ],
                    ),
                  ),
                PartnerConnectionBanner(
                  roomId: room.id,
                  presence: partnerPresenceAsync.value,
                ),
                Expanded(
                  child: messagesAsync.when(
                    data: (messages) {
                      if (messages.isEmpty) {
                         return const Center(child: Text('Be the first to say something secret...', style: TextStyle(color: Colors.white54)));
                      }
                      return ListView.builder(
                        reverse: true,
                        itemCount: messages.length,
                        itemBuilder: (context, index) {
                          final msg = messages[index];
                          return MessageBubble(
                            message: msg,
                            isMe: msg.senderId == currentUserId,
                            roomId: room.id,
                          );
                        },
                      );
                    },
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (error, stack) => Center(child: Text('Error: $error')),
                  ),
                ),
                _buildMessageInput(),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMessageInput() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: Colors.black26,
      child: SafeArea(
        child: Column(
          children: [
             Row(
               children: [
                 const Text('Secret Mode', style: TextStyle(color: AppTheme.secondaryNeon, fontSize: 12)),
                 Switch(
                   value: _isSecretMode,
                   activeColor: AppTheme.secondaryNeon,
                   onChanged: (val) => setState(() => _isSecretMode = val),
                 ),
                 const Spacer(),
                 const Text('Self-destruct: ', style: TextStyle(color: Colors.white54, fontSize: 12)),
                 DropdownButton<int>(
                   value: _expiresInSeconds,
                   dropdownColor: AppTheme.backgroundDark,
                   style: const TextStyle(color: AppTheme.primaryNeon),
                   items: const [
                     DropdownMenuItem(value: 0, child: Text("Never")),
                     DropdownMenuItem(value: 5, child: Text("5s")),
                     DropdownMenuItem(value: 10, child: Text("10s")),
                     DropdownMenuItem(value: 30, child: Text("30s")),
                   ],
                   onChanged: (val) => setState(() => _expiresInSeconds = val ?? 0),
                 ),
               ],
             ),
             Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: _isSecretMode ? 'Tap to reveal later...' : 'Type message...',
                      hintStyle: const TextStyle(color: Colors.white54),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Colors.white12,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                CircleAvatar(
                  backgroundColor: AppTheme.primaryNeon,
                  child: IconButton(
                    icon: const Icon(Icons.send, color: Colors.white),
                    onPressed: _sendMessage,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
