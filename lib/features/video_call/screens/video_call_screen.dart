import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../auth/providers/auth_provider.dart';
import '../../room/providers/room_provider.dart';
import '../../room/widgets/smart_expiry_timer.dart';
import '../providers/webrtc_provider.dart';
import '../../../core/theme/app_theme.dart';

class VideoCallScreen extends ConsumerStatefulWidget {
  const VideoCallScreen({super.key});

  @override
  ConsumerState<VideoCallScreen> createState() => _VideoCallScreenState();
}

class _VideoCallScreenState extends ConsumerState<VideoCallScreen> {
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();

  bool _isMicMuted = false;
  bool _isVideoMuted = false;
  bool _isConnecting = true;
  String _statusText = 'Initializing camera & audio...';

  @override
  void initState() {
    super.initState();
    _initCall();
  }

  Future<void> _initCall() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();

    final webrtcRepo = ref.read(webRTCProvider);
    final roomState = ref.read(currentRoomProvider);
    final user = ref.read(authStateChangesProvider).value ?? FirebaseAuth.instance.currentUser;
    final roomId = roomState.value?.id;
    final userId = user?.uid ?? 'guest_user';

    if (roomId == null) {
      if (mounted) context.pop();
      return;
    }

    webrtcRepo.onAddLocalStream = (stream) {
      if (mounted) {
        setState(() {
          _localRenderer.srcObject = stream;
        });
      }
    };

    webrtcRepo.onAddRemoteStream = (stream) {
      if (mounted) {
        setState(() {
          _remoteRenderer.srcObject = stream;
          _isConnecting = false;
          _statusText = 'Connected';
        });
      }
    };

    webrtcRepo.onCallStatusChanged = (status) {
      if (!mounted) return;
      setState(() {
        switch (status) {
          case CallStatus.calling:
            _statusText = 'Calling partner...';
            _isConnecting = true;
            break;
          case CallStatus.connected:
            _statusText = 'Connected';
            _isConnecting = false;
            break;
          case CallStatus.ended:
            _statusText = 'Call ended';
            _isConnecting = false;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Call has ended')),
            );
            context.pop();
            break;
          case CallStatus.error:
            _statusText = 'Connection error';
            _isConnecting = false;
            break;
          default:
            break;
        }
      });
    };

    webrtcRepo.onError = (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error), backgroundColor: Colors.redAccent),
        );
      }
    };

    final hasMedia = await webrtcRepo.initLocalStream();
    if (!hasMedia) {
      if (mounted) {
        setState(() {
          _statusText = 'Camera/Microphone permission denied';
          _isConnecting = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please grant camera and microphone permissions in phone settings.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return;
    }

    if (mounted) {
      setState(() => _statusText = 'Connecting to safe room...');
    }

    await webrtcRepo.startOrJoinCall(roomId, userId);
  }

  @override
  void dispose() {
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  void _endCall() {
    final roomState = ref.read(currentRoomProvider);
    ref.read(webRTCProvider).endCall(roomState.value?.id);
    if (mounted) {
      context.pop();
    }
  }

  void _onRoomExpired() {
    _endCall();
  }

  @override
  Widget build(BuildContext context) {
    // Watch provider to keep it active
    final webrtcRepo = ref.watch(webRTCProvider);
    final room = ref.watch(currentRoomProvider).value;
    final liveRoomAsync = room != null ? ref.watch(roomRepositoryProvider).watchRoom(room.id) : null;

    if (room == null) return const Scaffold(body: Center(child: Text('No room data')));

    final hasRemoteVideo = _remoteRenderer.srcObject != null;

    return StreamBuilder(
      stream: liveRoomAsync,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.active && !snapshot.hasData) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _onRoomExpired();
          });
        }
        return Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            children: [
              // Remote video or Connecting View
              Positioned.fill(
                child: hasRemoteVideo
                    ? RTCVideoView(
                        _remoteRenderer,
                        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                      )
                    : Container(
                        color: Colors.black87,
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 100,
                                height: 100,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: AppTheme.primaryNeon.withOpacity(0.15),
                                  border: Border.all(color: AppTheme.primaryNeon, width: 2),
                                ),
                                child: const Icon(
                                  Icons.videocam,
                                  size: 48,
                                  color: AppTheme.primaryNeon,
                                ),
                              ),
                              const SizedBox(height: 24),
                              Text(
                                _statusText,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 12),
                              if (_isConnecting)
                                const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: AppTheme.primaryNeon,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
              ),

              // Top Bar (Expiry & Back)
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.black45,
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.arrow_back, color: Colors.white),
                          onPressed: _endCall,
                        ),
                      ),
                      SmartExpiryTimer(
                        expiresAt: room.expiresAt,
                        onExpired: _onRoomExpired,
                      ),
                    ],
                  ),
                ),
              ),

              // Local View (Picture in Picture)
              Positioned(
                right: 20,
                bottom: 120,
                width: 110,
                height: 160,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black,
                    border: Border.all(color: AppTheme.primaryNeon, width: 2),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.5),
                        blurRadius: 8,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: _localRenderer.srcObject != null
                        ? RTCVideoView(
                            _localRenderer,
                            mirror: true,
                            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                          )
                        : const Center(
                            child: Icon(Icons.person, color: Colors.white30, size: 40),
                          ),
                  ),
                ),
              ),

              // Bottom Controls
              Align(
                alignment: Alignment.bottomCenter,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 24.0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(40),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildControlButton(
                            icon: _isMicMuted ? Icons.mic_off : Icons.mic,
                            color: _isMicMuted ? Colors.redAccent : Colors.white24,
                            onPressed: () {
                              setState(() => _isMicMuted = !_isMicMuted);
                              webrtcRepo.toggleAudio(!_isMicMuted);
                            },
                          ),
                          const SizedBox(width: 16),
                          _buildControlButton(
                            icon: Icons.call_end,
                            color: Colors.red,
                            size: 64,
                            iconSize: 32,
                            onPressed: _endCall,
                          ),
                          const SizedBox(width: 16),
                          _buildControlButton(
                            icon: _isVideoMuted ? Icons.videocam_off : Icons.videocam,
                            color: _isVideoMuted ? Colors.redAccent : Colors.white24,
                            onPressed: () {
                              setState(() => _isVideoMuted = !_isVideoMuted);
                              webrtcRepo.toggleVideo(!_isVideoMuted);
                            },
                          ),
                          const SizedBox(width: 16),
                          _buildControlButton(
                            icon: Icons.cameraswitch,
                            color: Colors.white24,
                            onPressed: () => webrtcRepo.switchCamera(),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
    double size = 52,
    double iconSize = 26,
  }) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(size / 2),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        child: Icon(icon, color: Colors.white, size: iconSize),
      ),
    );
  }
}
