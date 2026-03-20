import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:go_router/go_router.dart';
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

  @override
  void initState() {
    super.initState();
    _initRenderers();
  }

  Future<void> _initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();

    final webrtcRepo = ref.read(webRTCProvider);
    final roomState = ref.read(currentRoomProvider);
    final roomId = roomState.value?.id;

    if (roomId != null) {
      webrtcRepo.onAddLocalStream = (stream) {
        if (mounted) setState(() => _localRenderer.srcObject = stream);
      };

      webrtcRepo.onAddRemoteStream = (stream) {
        if (mounted) setState(() => _remoteRenderer.srcObject = stream);
      };

      await webrtcRepo.initLocalStream();
      
      // Determine if caller or callee by checking if offer exists
      // For simplicity here, try joining. If no offer, start call.
      // (A real app would use a more robust "incoming call" signal)
      webrtcRepo.joinCall(roomId).catchError((e) {
        webrtcRepo.startCall(roomId);
      });
    }
  }

  @override
  void dispose() {
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  void _onRoomExpired() {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Room expired. Call ended.')));
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final room = ref.watch(currentRoomProvider).value;
    final liveRoomAsync = room != null ? ref.watch(roomRepositoryProvider).watchRoom(room.id) : null;

    if (room == null) return const Scaffold(body: Center(child: Text('No room data')));

    return StreamBuilder(
      stream: liveRoomAsync,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.active && !snapshot.hasData) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _onRoomExpired();
          });
        }
        return Scaffold(
          backgroundColor: Colors.black, // Dark mode optimized
          body: Stack(
            children: [
              // Remote video (full screen)
              Positioned.fill(
                child: RTCVideoView(_remoteRenderer, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),
              ),
              
              // Top Bar (Expiry & Back)
              SafeArea(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => context.pop(),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 16.0),
                      child: SmartExpiryTimer(
                        expiresAt: room.expiresAt,
                        onExpired: _onRoomExpired,
                      ),
                    ),
                  ],
                ),
              ),

              // Local View (Picture in Picture)
              Positioned(
                right: 20,
                bottom: 120,
                width: 100,
                height: 150,
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: AppTheme.primaryNeon, width: 2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: RTCVideoView(_localRenderer, mirror: true, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),
                  ),
                ),
              ),

              // Bottom Controls
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 32.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildControlButton(
                        icon: _isMicMuted ? Icons.mic_off : Icons.mic,
                        color: _isMicMuted ? Colors.redAccent : Colors.white24,
                        onPressed: () {
                          setState(() => _isMicMuted = !_isMicMuted);
                          ref.read(webRTCProvider).toggleAudio(!_isMicMuted);
                        },
                      ),
                      _buildControlButton(
                        icon: Icons.call_end,
                        color: Colors.red,
                        size: 64,
                        iconSize: 32,
                        onPressed: () => context.pop(),
                      ),
                      _buildControlButton(
                        icon: _isVideoMuted ? Icons.videocam_off : Icons.videocam,
                        color: _isVideoMuted ? Colors.redAccent : Colors.white24,
                        onPressed: () {
                          setState(() => _isVideoMuted = !_isVideoMuted);
                          ref.read(webRTCProvider).toggleVideo(!_isVideoMuted);
                        },
                      ),
                      _buildControlButton(
                        icon: Icons.cameraswitch,
                        color: Colors.white24,
                        onPressed: () => ref.read(webRTCProvider).switchCamera(),
                      ),
                    ],
                  ),
                ),
              )
            ],
          ),
        );
      }
    );
  }

  Widget _buildControlButton({required IconData icon, required Color color, required VoidCallback onPressed, double size = 56, double iconSize = 28}) {
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
