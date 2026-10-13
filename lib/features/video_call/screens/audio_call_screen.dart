import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../auth/providers/auth_provider.dart';
import '../../room/models/room_model.dart';
import '../../room/providers/room_provider.dart';
import '../../room/widgets/smart_expiry_timer.dart';
import '../providers/webrtc_provider.dart';
import '../../../core/theme/app_theme.dart';

class AudioCallScreen extends ConsumerStatefulWidget {
  const AudioCallScreen({super.key});

  @override
  ConsumerState<AudioCallScreen> createState() => _AudioCallScreenState();
}

class _AudioCallScreenState extends ConsumerState<AudioCallScreen>
    with SingleTickerProviderStateMixin {
  bool _isMicMuted = false;
  bool _isSpeakerOn = true;
  bool _isConnecting = true;
  bool _isConnected = false;
  String _statusText = 'Connecting encrypted audio...';
  int _callDurationSeconds = 0;
  Timer? _durationTimer;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _initCall();
  }

  Future<void> _initCall() async {
    final audioRepo = ref.read(audioWebRTCProvider);
    final roomState = ref.read(currentRoomProvider);
    final userId = ref.read(userIdProvider);
    final roomId = roomState.value?.id;

    if (roomId == null) {
      if (mounted) context.pop();
      return;
    }

    audioRepo.onAddRemoteStream = (stream) {
      if (mounted) {
        setState(() {
          _isConnecting = false;
          _isConnected = true;
          _statusText = 'Connected';
        });
        audioRepo.toggleSpeaker(_isSpeakerOn);
        _startDurationTimer();
      }
    };

    audioRepo.onCallStatusChanged = (status) {
      if (!mounted) return;
      setState(() {
        switch (status) {
          case CallStatus.calling:
            _statusText = 'Calling partner...';
            _isConnecting = true;
            _isConnected = false;
            break;
          case CallStatus.connected:
            _statusText = 'Connected';
            _isConnecting = false;
            _isConnected = true;
            audioRepo.toggleSpeaker(_isSpeakerOn);
            _startDurationTimer();
            break;
          case CallStatus.rejected:
            _statusText = 'Call declined by partner';
            _isConnecting = false;
            _isConnected = false;
            _durationTimer?.cancel();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Audio call was declined by partner.'),
                backgroundColor: Colors.orangeAccent,
              ),
            );
            context.pop();
            break;
          case CallStatus.ended:
            _statusText = 'Call ended';
            _isConnecting = false;
            _isConnected = false;
            _durationTimer?.cancel();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Audio call has ended')),
            );
            context.pop();
            break;
          case CallStatus.error:
            _statusText = 'Connection error';
            _isConnecting = false;
            _durationTimer?.cancel();
            break;
          default:
            break;
        }
      });
    };

    audioRepo.onError = (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error), backgroundColor: Colors.redAccent),
        );
      }
    };

    final hasMedia = await audioRepo.initLocalStream();
    if (!hasMedia) {
      if (mounted) {
        setState(() {
          _statusText = 'Microphone permission denied';
          _isConnecting = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please grant microphone permission in phone settings.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return;
    }

    // Audio starts unmuted & loudspeaker enabled by default
    audioRepo.toggleAudio(true);
    await audioRepo.toggleSpeaker(true);

    if (mounted) {
      setState(() => _statusText = 'Connecting to safe room...');
    }

    await audioRepo.startOrJoinCall(roomId, userId);
  }

  void _startDurationTimer() {
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => _callDurationSeconds++);
      }
    });
  }

  String _formatDuration(int seconds) {
    final mins = (seconds ~/ 60).toString().padLeft(2, '0');
    final secs = (seconds % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  void _endCall() {
    final roomState = ref.read(currentRoomProvider);
    _durationTimer?.cancel();
    ref.read(audioWebRTCProvider).endCall(roomState.value?.id);
    if (mounted) {
      context.pop();
    }
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final room = ref.watch(currentRoomProvider).value;
    final audioRepo = ref.watch(audioWebRTCProvider);

    if (room == null) return const Scaffold(body: Center(child: Text('No room data')));

    ref.listen<AsyncValue<Room?>>(
      roomStreamProvider(room.id),
      (previous, next) {
        if (next.hasValue && next.value == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _endCall();
          });
        }
      },
    );

    return Scaffold(
          backgroundColor: const Color(0xFF0F0B18),
          body: Container(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, -0.2),
                radius: 1.2,
                colors: [Color(0xFF2A0845), Color(0xFF0F0B18)],
              ),
            ),
            child: SafeArea(
              child: Column(
                children: [
                  // Top Bar
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back, color: Colors.white),
                          onPressed: _endCall,
                        ),
                        Column(
                          children: [
                            const Text(
                              'Private Voice Call',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            Text(
                              'Room: ${room.name}',
                              style: const TextStyle(
                                color: AppTheme.secondaryNeon,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        SmartExpiryTimer(
                          expiresAt: room.expiresAt,
                          onExpired: _endCall,
                        ),
                      ],
                    ),
                  ),

                  const Spacer(flex: 2),

                  // Center Glowing Pulse Avatar
                  AnimatedBuilder(
                    animation: _pulseController,
                    builder: (context, child) {
                      final scale = 1.0 + (_pulseController.value * 0.12);
                      return Transform.scale(
                        scale: scale,
                        child: child,
                      );
                    },
                    child: Container(
                      width: 140,
                      height: 140,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFF2A5F), Color(0xFF8A2387)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFFF2A5F).withOpacity(0.4),
                            blurRadius: 28,
                            spreadRadius: 6,
                          ),
                          BoxShadow(
                            color: const Color(0xFF00FF88).withOpacity(0.2),
                            blurRadius: 36,
                            spreadRadius: 10,
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.phone_in_talk_rounded,
                          size: 64,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Partner Name
                  const Text(
                    'Partner',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),

                  const SizedBox(height: 10),

                  // Call Status / Duration
                  if (_isConnected)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFF00FF88).withOpacity(0.4)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.fiber_manual_record,
                              size: 10, color: Color(0xFF00FF88)),
                          const SizedBox(width: 6),
                          Text(
                            _formatDuration(_callDurationSeconds),
                            style: const TextStyle(
                              color: Color(0xFF00FF88),
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (_isConnecting)
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppTheme.secondaryNeon,
                            ),
                          ),
                        if (_isConnecting) const SizedBox(width: 8),
                        Text(
                          _statusText,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),

                  const Spacer(flex: 3),

                  // Bottom Call Controls
                  Padding(
                    padding: const EdgeInsets.only(bottom: 36.0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1E2C).withOpacity(0.9),
                        borderRadius: BorderRadius.circular(44),
                        border: Border.all(color: Colors.white12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.4),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Mic Mute / Unmute
                          _buildControlButton(
                            icon: _isMicMuted ? Icons.mic_off : Icons.mic,
                            color: _isMicMuted ? Colors.redAccent : Colors.white24,
                            tooltip: _isMicMuted ? 'Unmute Mic' : 'Mute Mic',
                            onPressed: () {
                              setState(() => _isMicMuted = !_isMicMuted);
                              audioRepo.toggleAudio(!_isMicMuted);
                            },
                          ),

                          const SizedBox(width: 20),

                          // End Call
                          _buildControlButton(
                            icon: Icons.call_end,
                            color: Colors.red,
                            size: 60,
                            tooltip: 'End Call',
                            onPressed: _endCall,
                          ),

                          const SizedBox(width: 20),

                          // Speaker Toggle
                          _buildControlButton(
                            icon: _isSpeakerOn ? Icons.volume_up : Icons.volume_down,
                            color: _isSpeakerOn ? const Color(0xFF00FF88) : Colors.white24,
                            tooltip: _isSpeakerOn ? 'Speaker ON' : 'Speaker OFF',
                            onPressed: () {
                              setState(() => _isSpeakerOn = !_isSpeakerOn);
                              audioRepo.toggleSpeaker(_isSpeakerOn);
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
  }

  Widget _buildControlButton({
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
    double size = 48,
    String? tooltip,
  }) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
      child: IconButton(
        icon: Icon(icon, color: Colors.white, size: size * 0.48),
        tooltip: tooltip,
        onPressed: onPressed,
      ),
    );
  }
}
