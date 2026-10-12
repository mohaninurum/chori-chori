import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_theme.dart';
import '../models/presence_model.dart';

class PartnerPresenceBadge extends StatefulWidget {
  final UserPresence? presence;
  final bool compact;

  const PartnerPresenceBadge({
    super.key,
    required this.presence,
    this.compact = false,
  });

  @override
  State<PartnerPresenceBadge> createState() => _PartnerPresenceBadgeState();
}

class _PartnerPresenceBadgeState extends State<PartnerPresenceBadge>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isOnline = widget.presence?.isActive ?? false;
    final hasJoined = widget.presence != null;

    final Color statusColor;
    final String statusText;

    if (isOnline) {
      statusColor = const Color(0xFF00FF88); // Neon Green
      statusText = 'Online';
    } else if (hasJoined) {
      statusColor = Colors.white38;
      statusText = widget.presence!.statusText;
    } else {
      statusColor = Colors.amberAccent;
      statusText = 'Waiting...';
    }

    if (widget.compact) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: statusColor,
                  boxShadow: isOnline
                      ? [
                          BoxShadow(
                            color: statusColor.withOpacity(_pulseAnimation.value * 0.8),
                            blurRadius: 6,
                            spreadRadius: 2,
                          )
                        ]
                      : null,
                ),
              );
            },
          ),
          const SizedBox(width: 5),
          Text(
            statusText,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isOnline ? statusColor : AppTheme.textSecondary,
              letterSpacing: 0.3,
            ),
          ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: statusColor.withOpacity(0.3), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: statusColor,
                  boxShadow: isOnline
                      ? [
                          BoxShadow(
                            color: statusColor.withOpacity(_pulseAnimation.value),
                            blurRadius: 5,
                            spreadRadius: 2,
                          )
                        ]
                      : null,
                ),
              );
            },
          ),
          const SizedBox(width: 6),
          Text(
            statusText,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: statusColor,
            ),
          ),
        ],
      ),
    );
  }
}

class PartnerConnectionBanner extends StatelessWidget {
  final String roomId;
  final UserPresence? presence;

  const PartnerConnectionBanner({
    super.key,
    required this.roomId,
    required this.presence,
  });

  @override
  Widget build(BuildContext context) {
    final isOnline = presence?.isActive ?? false;
    final hasJoined = presence != null;

    if (isOnline) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF00FF88).withOpacity(0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF00FF88).withOpacity(0.4)),
        ),
        child: const Row(
          children: [
            Icon(Icons.check_circle_outline, color: Color(0xFF00FF88), size: 18),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Partner is connected and online now!',
                style: TextStyle(
                  color: Color(0xFF00FF88),
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: hasJoined
            ? Colors.white.withOpacity(0.06)
            : AppTheme.secondaryNeon.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: hasJoined
              ? Colors.white24
              : AppTheme.secondaryNeon.withOpacity(0.4),
        ),
      ),
      child: Row(
        children: [
          Icon(
            hasJoined ? Icons.schedule : Icons.hourglass_top,
            color: hasJoined ? Colors.white60 : AppTheme.secondaryNeon,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              hasJoined
                  ? 'Partner is currently ${presence!.statusText.toLowerCase()}'
                  : 'Waiting for partner to join (Room: $roomId)',
              style: TextStyle(
                color: hasJoined ? Colors.white70 : AppTheme.secondaryNeon,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (!hasJoined)
            TextButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: roomId));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Room ID "$roomId" copied to clipboard!'),
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
              icon: const Icon(Icons.copy, size: 14, color: AppTheme.secondaryNeon),
              label: const Text(
                'Share',
                style: TextStyle(fontSize: 12, color: AppTheme.secondaryNeon),
              ),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
        ],
      ),
    );
  }
}
