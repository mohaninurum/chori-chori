import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/message_model.dart';
import '../providers/chat_provider.dart';
import '../../../core/theme/app_theme.dart';
import 'image_message_view.dart';
import 'voice_message_player.dart';

class MessageBubble extends ConsumerStatefulWidget {
  final ChatMessage message;
  final bool isMe;
  final String roomId;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    required this.roomId,
  });

  @override
  ConsumerState<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends ConsumerState<MessageBubble> {
  bool _isRevealed = false;
  int _remainingSeconds = 0;
  Timer? _countdownTimer;
  Timer? _concealTimer;
  double _opacity = 1.0;
  bool _isDeleting = false;

  @override
  void initState() {
    super.initState();
    // Non-secret messages are revealed by default. Secret messages start concealed.
    _isRevealed = !widget.message.isSecret;
    _initSelfDestruct();
  }

  @override
  void didUpdateWidget(covariant MessageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.id != widget.message.id) {
      _countdownTimer?.cancel();
      _concealTimer?.cancel();
      _isDeleting = false;
      _opacity = 1.0;
      _isRevealed = !widget.message.isSecret;
      _initSelfDestruct();
    }
  }

  void _initSelfDestruct() {
    if (widget.message.expiresInSeconds <= 0) return;

    // For secret messages, countdown only starts once tapped/revealed!
    if (widget.message.isSecret && !_isRevealed) {
      _remainingSeconds = widget.message.expiresInSeconds;
      return;
    }

    _startCountdown();
  }

  void _startCountdown() {
    if (_countdownTimer != null) return;
    _countdownTimer?.cancel();

    _remainingSeconds = widget.message.expiresInSeconds;

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_remainingSeconds > 1) {
        setState(() {
          _remainingSeconds--;
        });
      } else {
        timer.cancel();
        setState(() {
          _remainingSeconds = 0;
        });
        _triggerDestruction();
      }
    });
  }

  void _triggerDestruction() {
    if (_isDeleting || !mounted) return;
    _isDeleting = true;
    setState(() {
      _opacity = 0.0;
    });

    Future.delayed(const Duration(milliseconds: 350), () {
      if (mounted) {
        ref.read(chatRepositoryProvider).deleteMessage(widget.roomId, widget.message.id);
      }
    });
  }

  void _toggleSecretReveal() {
    if (!widget.message.isSecret) return;

    setState(() {
      _isRevealed = !_isRevealed;
    });

    if (_isRevealed) {
      // If message has self-destruct, start the countdown now that it is opened!
      if (widget.message.expiresInSeconds > 0 && _countdownTimer == null) {
        _startCountdown();
      } else if (widget.message.expiresInSeconds == 0) {
        // Auto re-conceal secret message after 6 seconds if no self-destruct timer
        _concealTimer?.cancel();
        _concealTimer = Timer(const Duration(seconds: 6), () {
          if (mounted) {
            setState(() {
              _isRevealed = false;
            });
          }
        });
      }
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _concealTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMe = widget.isMe;
    final hasSelfDestruct = widget.message.expiresInSeconds > 0;
    final isSecret = widget.message.isSecret;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 350),
      opacity: _opacity,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 10),
        child: Align(
          // Sender is on RIGHT, Receiver is on LEFT
          alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.78,
            ),
            child: GestureDetector(
              onTap: isSecret ? _toggleSecretReveal : null,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                decoration: BoxDecoration(
                  gradient: isMe
                      ? const LinearGradient(
                          colors: [Color(0xFFFF2A5F), Color(0xFFFF527B)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : null,
                  color: isMe ? null : const Color(0xFF1E1E2C),
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(18),
                    topRight: const Radius.circular(18),
                    bottomLeft: Radius.circular(isMe ? 18 : 4),
                    bottomRight: Radius.circular(isMe ? 4 : 18),
                  ),
                  border: Border.all(
                    color: isMe
                        ? const Color(0xFFFF527B)
                        : (isSecret ? AppTheme.secondaryNeon : const Color(0xFF2C2C3E)),
                    width: isSecret ? 1.5 : 1.0,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: isMe
                          ? const Color(0xFFFF2A5F).withOpacity(0.3)
                          : Colors.black.withOpacity(0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment:
                      isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Partner label on received messages
                    if (!isMe)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4.0),
                        child: Text(
                          'Partner',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                            color: AppTheme.secondaryNeon.withOpacity(0.8),
                          ),
                        ),
                      ),

                    // Message Content (Secret concealed or revealed)
                    if (isSecret && !_isRevealed)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            widget.message.type == MessageType.image
                                ? Icons.photo_camera_back_outlined
                                : (widget.message.type == MessageType.voice
                                    ? Icons.mic_none_outlined
                                    : Icons.lock_outline_rounded),
                            color: isMe ? Colors.white : AppTheme.secondaryNeon,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.message.type == MessageType.image
                                    ? 'Secret Photo'
                                    : (widget.message.type == MessageType.voice
                                        ? 'Secret Voice Note'
                                        : 'Secret Message'),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                              Text(
                                'Tap to reveal',
                                style: TextStyle(
                                  color: isMe ? Colors.white70 : Colors.white54,
                                  fontSize: 11,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ],
                          ),
                        ],
                      )
                    else if (widget.message.type == MessageType.image &&
                        widget.message.mediaData != null)
                      ImageMessageView(
                        base64Image: widget.message.mediaData!,
                        caption: widget.message.text.isNotEmpty ? widget.message.text : null,
                        isMe: isMe,
                      )
                    else if (widget.message.type == MessageType.voice &&
                        widget.message.mediaData != null)
                      VoiceMessagePlayer(
                        base64Audio: widget.message.mediaData!,
                        durationSeconds: widget.message.durationSeconds ?? 1,
                        isMe: isMe,
                      )
                    else
                      Column(
                        crossAxisAlignment:
                            isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.message.text,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              height: 1.3,
                            ),
                          ),
                          if (isSecret)
                            Padding(
                              padding: const EdgeInsets.only(top: 4.0),
                              child: Text(
                                '(Tap to hide)',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: isMe ? Colors.white70 : Colors.white54,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                        ],
                      ),

                    // Badges row: Secret indicator & Self-destruct countdown
                    if (isSecret || hasSelfDestruct)
                      Padding(
                        padding: const EdgeInsets.only(top: 6.0),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isSecret)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                margin: const EdgeInsets.only(right: 6),
                                decoration: BoxDecoration(
                                  color: Colors.black26,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.visibility_off,
                                        size: 11, color: Colors.amberAccent),
                                    SizedBox(width: 3),
                                    Text(
                                      'Secret',
                                      style: TextStyle(
                                          fontSize: 10, color: Colors.amberAccent),
                                    ),
                                  ],
                                ),
                              ),
                            if (hasSelfDestruct)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isMe
                                      ? Colors.white24
                                      : (_remainingSeconds <= 3
                                          ? Colors.red.withOpacity(0.3)
                                          : Colors.black26),
                                  borderRadius: BorderRadius.circular(8),
                                  border: (!isMe && _remainingSeconds <= 3)
                                      ? Border.all(color: Colors.redAccent, width: 1)
                                      : null,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.timer_outlined,
                                      size: 11,
                                      color: isMe
                                          ? Colors.white
                                          : (_remainingSeconds <= 3
                                              ? Colors.redAccent
                                              : Colors.white70),
                                    ),
                                    const SizedBox(width: 3),
                                    Text(
                                      '${_remainingSeconds}s',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: isMe
                                            ? Colors.white
                                            : (_remainingSeconds <= 3
                                                ? Colors.redAccent
                                                : Colors.white70),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
