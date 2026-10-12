import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import 'package:image_picker/image_picker.dart';
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
import '../services/chat_media_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/router/routes.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> with WidgetsBindingObserver {
  final _messageController = TextEditingController();
  final ChatMediaService _mediaService = ChatMediaService();
  bool _isSecretMode = false;
  int _expiresInSeconds = 0;
  Timer? _heartbeatTimer;
  bool _isCallDialogShowing = false;
  bool _isAudioCallDialogShowing = false;
  bool _isRecordingVoice = false;
  int _recordDurationSeconds = 0;
  Timer? _recordTimer;
  bool _isSendingMedia = false;
  bool _isExitingRoom = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _messageController.addListener(() {
      if (mounted) setState(() {});
    });
    _ensureAuth();
    _startHeartbeat();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setPresence(true);
    });
  }

  void _startHeartbeat() {
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      _setPresence(true);
    });
  }

  void _setPresence(bool isOnline) {
    final room = ref.read(currentRoomProvider).value;
    final userId = ref.read(userIdProvider);
    final roomId = room?.id;

    if (roomId != null && userId.isNotEmpty) {
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
    _recordTimer?.cancel();
    _mediaService.dispose();
    _setPresence(false);
    _messageController.dispose();
    super.dispose();
  }

  void _showIncomingCallDialog(String roomId) {
    if (_isCallDialogShowing || !mounted) return;
    _isCallDialogShowing = true;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2C),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: Color(0xFF00FF88), width: 1.5),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF00FF88).withOpacity(0.15),
              ),
              child: const Icon(Icons.videocam, color: Color(0xFF00FF88), size: 28),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Incoming Video Call',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: const Text(
          'Your partner is requesting a video call in this room.\n\n'
          '• Accept: Join video call immediately\n'
          '• Reject: Decline call and continue chatting',
          style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
        ),
        actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        actions: [
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.redAccent),
              foregroundColor: Colors.redAccent,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.call_end, size: 16),
            label: const Text('Reject Call', style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: () async {
              Navigator.of(ctx).pop();
              _isCallDialogShowing = false;
              await ref.read(webRTCProvider).rejectCall(roomId);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Video call rejected. Chat continues.'),
                    duration: Duration(seconds: 2),
                    backgroundColor: Colors.white24,
                  ),
                );
              }
            },
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00FF88),
              foregroundColor: Colors.black87,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.videocam, size: 18),
            label: const Text('Accept Call', style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: () {
              Navigator.of(ctx).pop();
              _isCallDialogShowing = false;
              context.push(Routes.videoCall);
            },
          ),
        ],
      ),
    ).then((_) {
      _isCallDialogShowing = false;
    });
  }

  void _showIncomingAudioCallDialog(String roomId) {
    if (_isAudioCallDialogShowing || !mounted) return;
    _isAudioCallDialogShowing = true;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2C),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: Color(0xFF00FF88), width: 1.5),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF00FF88).withOpacity(0.15),
              ),
              child: const Icon(Icons.phone_in_talk_rounded, color: Color(0xFF00FF88), size: 28),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Incoming Voice Call',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: const Text(
          'Your partner is requesting a voice call in this room.\n\n'
          '• Accept: Join voice call immediately\n'
          '• Reject: Decline call and continue chatting',
          style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
        ),
        actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        actions: [
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.redAccent),
              foregroundColor: Colors.redAccent,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.call_end, size: 16),
            label: const Text('Reject Call', style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: () async {
              Navigator.of(ctx).pop();
              _isAudioCallDialogShowing = false;
              await ref.read(audioWebRTCProvider).rejectCall(roomId);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Voice call rejected. Chat continues.'),
                    duration: Duration(seconds: 2),
                    backgroundColor: Colors.white24,
                  ),
                );
              }
            },
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00FF88),
              foregroundColor: Colors.black87,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.phone, size: 18),
            label: const Text('Accept Call', style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: () {
              Navigator.of(ctx).pop();
              _isAudioCallDialogShowing = false;
              context.push(Routes.audioCall);
            },
          ),
        ],
      ),
    ).then((_) {
      _isAudioCallDialogShowing = false;
    });
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
    if (_isExitingRoom) return;
    _isExitingRoom = true;
    _heartbeatTimer?.cancel();
    _setPresence(false);

    if (mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Room close ho gaya hai aur data delete ho chuka hai.'),
          backgroundColor: Colors.redAccent,
          duration: Duration(seconds: 2),
        ),
      );
    }

    final room = ref.read(currentRoomProvider).value;
    if (room != null) {
      await ref.read(currentRoomProvider.notifier).closeAndDestroyRoom(room.id);
    }

    if (mounted) {
      context.go(Routes.home);
    }
  }

  void _onRoomExpiredOrDeleted() {
    if (_isExitingRoom) return;
    _isExitingRoom = true;
    _heartbeatTimer?.cancel();
    _setPresence(false);

    if (mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Room close ho chuka hai aur data delete ho gaya hai.'),
          backgroundColor: Colors.redAccent,
          duration: Duration(seconds: 2),
        ),
      );
      context.go(Routes.home);
    }
  }

  void _onRoomExpired() {
    if (_isExitingRoom) return;
    _isExitingRoom = true;
    _heartbeatTimer?.cancel();
    _setPresence(false);

    final room = ref.read(currentRoomProvider).value;
    if (room != null) {
      ref.read(currentRoomProvider.notifier).closeAndDestroyRoom(room.id);
    }
    _onRoomExpiredOrDeleted();
  }

  String _formatDuration(int totalSeconds) {
    final mins = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final secs = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  void _sendMediaMessage({
    required MessageType type,
    required String mediaData,
    String? caption,
    int? durationSeconds,
  }) {
    final roomState = ref.read(currentRoomProvider);
    final userId = ref.read(userIdProvider);
    final roomId = roomState.value?.id;

    if (roomId != null && userId.isNotEmpty) {
      final message = ChatMessage(
        id: const Uuid().v4(),
        senderId: userId,
        text: caption ?? '',
        type: type,
        mediaData: mediaData,
        durationSeconds: durationSeconds,
        createdAt: DateTime.now(),
        expiresInSeconds: _expiresInSeconds,
        isSecret: _isSecretMode,
      );

      ref.read(chatRepositoryProvider).sendMessage(roomId, message);
      _setPresence(true);
    }
  }

  Future<void> _pickAndSendImage(ImageSource source) async {
    Navigator.of(context).pop();
    setState(() => _isSendingMedia = true);
    try {
      final base64Image = await _mediaService.pickImage(source: source);
      if (base64Image != null) {
        _sendMediaMessage(
          type: MessageType.image,
          mediaData: base64Image,
          caption: _messageController.text.trim().isNotEmpty
              ? _messageController.text.trim()
              : null,
        );
        _messageController.clear();
      }
    } catch (e) {
      debugPrint('Error sending image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to load image. Please try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSendingMedia = false);
    }
  }

  void _showImagePickerOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E2C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Send Ephemeral Photo',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _isSecretMode
                    ? '🔒 Secret Mode Active (Tap to reveal on partner device)'
                    : 'Photo vanishes completely when room/message expires',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildPickerOption(
                    icon: Icons.camera_alt_rounded,
                    label: 'Camera',
                    color: AppTheme.primaryNeon,
                    onTap: () => _pickAndSendImage(ImageSource.camera),
                  ),
                  _buildPickerOption(
                    icon: Icons.photo_library_rounded,
                    label: 'Gallery',
                    color: AppTheme.secondaryNeon,
                    onTap: () => _pickAndSendImage(ImageSource.gallery),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPickerOption({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.4)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 36),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _startVoiceRecording() async {
    final success = await _mediaService.startVoiceRecording();
    if (!success) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Microphone permission required to send voice notes.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return;
    }

    setState(() {
      _isRecordingVoice = true;
      _recordDurationSeconds = 0;
    });

    _recordTimer?.cancel();
    _recordTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        _recordDurationSeconds++;
      });
    });
  }

  Future<void> _cancelVoiceRecording() async {
    _recordTimer?.cancel();
    await _mediaService.cancelVoiceRecording();
    if (mounted) {
      setState(() {
        _isRecordingVoice = false;
        _recordDurationSeconds = 0;
      });
    }
  }

  Future<void> _stopAndSendVoiceRecording() async {
    _recordTimer?.cancel();
    setState(() => _isSendingMedia = true);
    final result = await _mediaService.stopVoiceRecording();
    if (mounted) {
      setState(() {
        _isRecordingVoice = false;
        _recordDurationSeconds = 0;
        _isSendingMedia = false;
      });
    }

    if (result != null) {
      _sendMediaMessage(
        type: MessageType.voice,
        mediaData: result.base64Audio,
        durationSeconds: result.durationSeconds,
      );
    }
  }

  void _sendMessage() {
    if (_messageController.text.trim().isEmpty) return;

    final roomState = ref.read(currentRoomProvider);
    final userId = ref.read(userIdProvider);
    final roomId = roomState.value?.id;

    if (roomId != null && userId.isNotEmpty) {
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

    final currentUserId = ref.watch(userIdProvider);

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

    final audioCallSessionAsync = ref.watch(audioCallSessionStreamProvider(room.id));
    final audioCallData = audioCallSessionAsync.value;
    final isIncomingAudioCall = audioCallData != null &&
        audioCallData['status'] == 'calling' &&
        audioCallData['callerId'] != currentUserId;

    ref.listen<AsyncValue<Map<String, dynamic>?>>(
      callSessionStreamProvider(room.id),
      (previous, next) {
        final data = next.value;
        final isCalling = data != null &&
            data['status'] == 'calling' &&
            data['callerId'] != currentUserId;

        if (isCalling && !_isCallDialogShowing) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && !_isCallDialogShowing) {
              _showIncomingCallDialog(room.id);
            }
          });
        } else if (!isCalling && _isCallDialogShowing) {
          if (mounted && Navigator.of(context, rootNavigator: true).canPop()) {
            Navigator.of(context, rootNavigator: true).pop();
            _isCallDialogShowing = false;
          }
        }
      },
    );

    ref.listen<AsyncValue<Map<String, dynamic>?>>(
      audioCallSessionStreamProvider(room.id),
      (previous, next) {
        final data = next.value;
        final isCalling = data != null &&
            data['status'] == 'calling' &&
            data['callerId'] != currentUserId;

        if (isCalling && !_isAudioCallDialogShowing) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && !_isAudioCallDialogShowing) {
              _showIncomingAudioCallDialog(room.id);
            }
          });
        } else if (!isCalling && _isAudioCallDialogShowing) {
          if (mounted && Navigator.of(context, rootNavigator: true).canPop()) {
            Navigator.of(context, rootNavigator: true).pop();
            _isAudioCallDialogShowing = false;
          }
        }
      },
    );

    return StreamBuilder(
      stream: liveRoomAsync,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.active && (!snapshot.hasData || snapshot.data == null)) {
          if (!_isExitingRoom) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _onRoomExpiredOrDeleted();
            });
          }
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
                  Icons.phone,
                  color: isIncomingAudioCall ? const Color(0xFF00FF88) : AppTheme.secondaryNeon,
                ),
                tooltip: 'Voice Call',
                onPressed: () {
                  context.push(Routes.audioCall);
                },
              ),
              IconButton(
                icon: Icon(
                  Icons.videocam,
                  color: isIncomingCall ? const Color(0xFF00FF88) : AppTheme.primaryNeon,
                ),
                tooltip: 'Video Call',
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
                if (isIncomingAudioCall)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF142F43), Color(0xFF0B4F6C)],
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
                          child: const Icon(Icons.phone_in_talk_rounded, color: Color(0xFF00FF88), size: 22),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Incoming Voice Call',
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
                        IconButton(
                          icon: const Icon(Icons.call_end, color: Colors.redAccent, size: 20),
                          tooltip: 'Reject Call',
                          onPressed: () async {
                            await ref.read(audioWebRTCProvider).rejectCall(room.id);
                          },
                        ),
                        const SizedBox(width: 4),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00FF88),
                            foregroundColor: Colors.black87,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          ),
                          icon: const Icon(Icons.phone, size: 16),
                          label: const Text('Accept', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                          onPressed: () => context.push(Routes.audioCall),
                        ),
                      ],
                    ),
                  ),
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
                        IconButton(
                          icon: const Icon(Icons.call_end, color: Colors.redAccent, size: 20),
                          tooltip: 'Reject Call',
                          onPressed: () async {
                            await ref.read(webRTCProvider).rejectCall(room.id);
                          },
                        ),
                        const SizedBox(width: 4),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00FF88),
                            foregroundColor: Colors.black87,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          ),
                          icon: const Icon(Icons.call, size: 16),
                          label: const Text('Accept', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
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
                          final isMe = msg.senderId == currentUserId ||
                              (currentDeviceUserId.isNotEmpty && msg.senderId == currentDeviceUserId) ||
                              (FirebaseAuth.instance.currentUser?.uid != null &&
                                  msg.senderId == FirebaseAuth.instance.currentUser!.uid);
                          return MessageBubble(
                            key: ValueKey(msg.id),
                            message: msg,
                            isMe: isMe,
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
    final hasText = _messageController.text.trim().isNotEmpty;

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

            if (_isRecordingVoice)
              Container(
                margin: const EdgeInsets.symmetric(vertical: 4),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF2A0845), Color(0xFF1E1E2C)],
                  ),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.redAccent.withOpacity(0.6), width: 1.5),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: const BoxDecoration(
                        color: Colors.redAccent,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Recording... ${_formatDuration(_recordDurationSeconds)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 24),
                      tooltip: 'Cancel',
                      onPressed: _cancelVoiceRecording,
                    ),
                    const SizedBox(width: 4),
                    Container(
                      decoration: const BoxDecoration(
                        color: Color(0xFF00FF88),
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.send_rounded, color: Colors.black87, size: 20),
                        tooltip: 'Send Voice Note',
                        onPressed: _stopAndSendVoiceRecording,
                      ),
                    ),
                  ],
                ),
              )
            else
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.add_photo_alternate_outlined, color: AppTheme.secondaryNeon, size: 26),
                    tooltip: 'Send Photo',
                    onPressed: _isSendingMedia ? null : _showImagePickerOptions,
                  ),
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
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (hasText)
                    CircleAvatar(
                      backgroundColor: AppTheme.primaryNeon,
                      child: IconButton(
                        icon: const Icon(Icons.send, color: Colors.white),
                        onPressed: _sendMessage,
                      ),
                    )
                  else
                    CircleAvatar(
                      backgroundColor: const Color(0xFF2C2C3E),
                      child: IconButton(
                        icon: const Icon(Icons.mic_none_rounded, color: AppTheme.secondaryNeon),
                        tooltip: 'Record Voice Note',
                        onPressed: _startVoiceRecording,
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
