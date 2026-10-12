import 'dart:convert';
import 'package:flutter/material.dart';

class ImageMessageView extends StatelessWidget {
  final String base64Image;
  final String? caption;
  final bool isMe;

  const ImageMessageView({
    super.key,
    required this.base64Image,
    this.caption,
    required this.isMe,
  });

  void _openFullScreen(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black.withOpacity(0.95),
        insetPadding: EdgeInsets.zero,
        child: Stack(
          alignment: Alignment.center,
          children: [
            InteractiveViewer(
              panEnabled: true,
              minScale: 0.5,
              maxScale: 4.0,
              child: Image.memory(
                base64Decode(base64Image),
                fit: BoxFit.contain,
              ),
            ),
            Positioned(
              top: 40,
              right: 20,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 28),
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ),
            if (caption != null && caption!.isNotEmpty)
              Positioned(
                bottom: 30,
                left: 20,
                right: 20,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    caption!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _openFullScreen(context),
      child: Column(
        crossAxisAlignment:
            isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxHeight: 240,
                maxWidth: 220,
              ),
              child: Image.memory(
                base64Decode(base64Image),
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  height: 120,
                  width: 120,
                  color: Colors.white10,
                  child: const Center(
                    child: Icon(Icons.broken_image, color: Colors.white38),
                  ),
                ),
              ),
            ),
          ),
          if (caption != null && caption!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6.0),
              child: Text(
                caption!,
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            ),
        ],
      ),
    );
  }
}
