import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import '../../auth/providers/auth_provider.dart';
import '../../room/providers/room_provider.dart';
import '../../room/widgets/smart_expiry_timer.dart';
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

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _messageController = TextEditingController();
  bool _isSecretMode = false;
  int _expiresInSeconds = 0;

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  void _leaveRoom() {
    if (mounted) {
      context.go(Routes.home);
    }
  }

  void _onRoomExpired() {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Room has expired and self-destructed.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      _leaveRoom();
    }
  }

  void _sendMessage() {
    if (_messageController.text.trim().isEmpty) return;

    final roomState = ref.read(currentRoomProvider);
    final user = ref.read(authStateChangesProvider).value;
    final roomId = roomState.value?.id;
    final userId = user?.uid;

    if (roomId != null && userId != null) {
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
    }
  }

  @override
  Widget build(BuildContext context) {
    final roomState = ref.watch(currentRoomProvider);
    final room = roomState.value;
    final user = ref.watch(authStateChangesProvider).value;

    if (room == null || user == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final liveRoomAsync = ref.watch(roomRepositoryProvider).watchRoom(room.id);
    final messagesAsync = ref.watch(messagesStreamProvider(room.id));

    return StreamBuilder(
      stream: liveRoomAsync,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.active && !snapshot.hasData) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _onRoomExpired();
          });
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        return Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(room.name, style: const TextStyle(fontSize: 18, color: AppTheme.textPrimary)),
                Text('ID: ${room.id}', style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
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
                icon: const Icon(Icons.videocam, color: AppTheme.primaryNeon),
                onPressed: () {
                  context.push(Routes.videoCall);
                },
              ),
              IconButton(
                icon: const Icon(Icons.exit_to_app, color: Colors.grey),
                onPressed: _leaveRoom,
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
                            isMe: msg.senderId == user.uid,
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
