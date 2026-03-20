import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/message_model.dart';
import '../providers/chat_provider.dart';
import '../../../core/theme/app_theme.dart';

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
  bool _isHidden = false;
  Timer? _destructTimer;
  double _opacity = 1.0;

  @override
  void initState() {
    super.initState();
    _isHidden = widget.message.isSecret;
    _setupSelfDestruct();
  }

  void _setupSelfDestruct() {
    if (widget.message.expiresInSeconds > 0) {
      final expireTime = widget.message.createdAt.add(Duration(seconds: widget.message.expiresInSeconds));
      final now = DateTime.now();
      final diff = expireTime.difference(now);

      if (diff.isNegative) {
        // Already expired
        _deleteSelf();
      } else {
        _destructTimer = Timer(diff, () {
          if (mounted) {
            setState(() {
              _opacity = 0.0;
            });
            // Give 500ms for fade out animation before deleting
            Future.delayed(const Duration(milliseconds: 500), _deleteSelf);
          }
        });
      }
    }
  }

  void _deleteSelf() {
    if (mounted) {
      ref.read(chatRepositoryProvider).deleteMessage(widget.roomId, widget.message.id);
    }
  }

  @override
  void dispose() {
    _destructTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 500),
      opacity: _opacity,
      child: Align(
        alignment: widget.isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: GestureDetector(
          onTap: () {
            if (_isHidden && widget.message.isSecret) {
              setState(() {
                _isHidden = false;
              });
              // Optionally re-hide after a few seconds
              Future.delayed(const Duration(seconds: 3), () {
                if (mounted) setState(() => _isHidden = true);
              });
            }
          },
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
            decoration: BoxDecoration(
              color: widget.isMe ? AppTheme.primaryNeon : AppTheme.backgroundLight,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(widget.isMe ? 16 : 0),
                bottomRight: Radius.circular(widget.isMe ? 0 : 16),
              ),
              border: Border.all(
                color: widget.isMe ? AppTheme.primaryNeon : AppTheme.secondaryNeon,
                width: widget.message.isSecret ? 2 : 0,
              ),
              boxShadow: widget.isMe
                  ? [BoxShadow(color: AppTheme.primaryNeon.withOpacity(0.5), blurRadius: 8, spreadRadius: 1)]
                  : [],
            ),
            child: _isHidden
                ? const Icon(Icons.visibility_off, color: Colors.white54, size: 20)
                : Text(
                    widget.message.text,
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                  ),
          ),
        ),
      ),
    );
  }
}
