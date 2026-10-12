import 'dart:convert';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

class VoiceMessagePlayer extends StatefulWidget {
  final String base64Audio;
  final int durationSeconds;
  final bool isMe;

  const VoiceMessagePlayer({
    super.key,
    required this.base64Audio,
    required this.durationSeconds,
    required this.isMe,
  });

  @override
  State<VoiceMessagePlayer> createState() => _VoiceMessagePlayerState();
}

class _VoiceMessagePlayerState extends State<VoiceMessagePlayer> {
  late final AudioPlayer _player;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _totalDuration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _totalDuration = Duration(seconds: widget.durationSeconds);
    _player = AudioPlayer();

    _player.onPlayerStateChanged.listen((state) {
      if (!mounted) return;
      setState(() {
        _isPlaying = state == PlayerState.playing;
      });
    });

    _player.onPositionChanged.listen((pos) {
      if (!mounted) return;
      setState(() {
        _position = pos;
      });
    });

    _player.onPlayerComplete.listen((_) {
      if (!mounted) return;
      setState(() {
        _isPlaying = false;
        _position = Duration.zero;
      });
    });
  }

  Future<void> _togglePlay() async {
    if (_isPlaying) {
      await _player.pause();
    } else {
      try {
        final bytes = base64Decode(widget.base64Audio);
        await _player.play(BytesSource(bytes));
      } catch (e) {
        debugPrint('Error playing voice note: $e');
      }
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final mins = d.inMinutes.toString().padLeft(2, '0');
    final secs = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  @override
  Widget build(BuildContext context) {
    final isMe = widget.isMe;
    final primaryColor = isMe ? Colors.white : AppTheme.secondaryNeon;
    final currentPos = _position.inSeconds > 0
        ? _formatDuration(_position)
        : _formatDuration(_totalDuration);

    final maxVal = _totalDuration.inMilliseconds > 0
        ? _totalDuration.inMilliseconds.toDouble()
        : 1000.0;
    final curVal = _position.inMilliseconds.toDouble().clamp(0.0, maxVal);

    return Container(
      constraints: const BoxConstraints(minWidth: 180, maxWidth: 240),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Play / Pause Circle
          GestureDetector(
            onTap: _togglePlay,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isMe ? Colors.white24 : AppTheme.secondaryNeon.withOpacity(0.2),
              ),
              child: Icon(
                _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: primaryColor,
                size: 24,
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Progress & waveform
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                    activeTrackColor: primaryColor,
                    inactiveTrackColor: Colors.white24,
                    thumbColor: primaryColor,
                  ),
                  child: Slider(
                    value: curVal,
                    min: 0.0,
                    max: maxVal,
                    onChanged: (val) async {
                      final seekTo = Duration(milliseconds: val.toInt());
                      await _player.seek(seekTo);
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        currentPos,
                        style: TextStyle(
                          color: isMe ? Colors.white70 : Colors.white60,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.mic, size: 10, color: isMe ? Colors.white70 : AppTheme.secondaryNeon),
                          const SizedBox(width: 2),
                          Text(
                            'Voice note',
                            style: TextStyle(
                              color: isMe ? Colors.white70 : Colors.white60,
                              fontSize: 9,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
