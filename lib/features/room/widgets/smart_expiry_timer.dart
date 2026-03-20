import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

class SmartExpiryTimer extends StatefulWidget {
  final DateTime expiresAt;
  final VoidCallback onExpired;

  const SmartExpiryTimer({
    super.key,
    required this.expiresAt,
    required this.onExpired,
  });

  @override
  State<SmartExpiryTimer> createState() => _SmartExpiryTimerState();
}

class _SmartExpiryTimerState extends State<SmartExpiryTimer> {
  Timer? _timer;
  Duration _remainingTime = Duration.zero;

  @override
  void initState() {
    super.initState();
    _calculateRemainingTime();
    _startTimer();
  }

  void _calculateRemainingTime() {
    final now = DateTime.now();
    if (now.isAfter(widget.expiresAt)) {
      _remainingTime = Duration.zero;
      widget.onExpired();
    } else {
      _remainingTime = widget.expiresAt.difference(now);
    }
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _calculateRemainingTime();
      });
      if (_remainingTime.inSeconds <= 0) {
        timer.cancel();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_remainingTime.inSeconds <= 0) {
      return const Text('Expired', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold));
    }

    final minutes = _remainingTime.inMinutes.toString().padLeft(2, '0');
    final seconds = (_remainingTime.inSeconds % 60).toString().padLeft(2, '0');
    final isWarning = _remainingTime.inMinutes < 5; // Highlight red when < 5 mins left

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isWarning ? Colors.redAccent.withOpacity(0.2) : Colors.white10,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isWarning ? Colors.redAccent : AppTheme.secondaryNeon),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.timer, size: 16, color: isWarning ? Colors.redAccent : AppTheme.secondaryNeon),
          const SizedBox(width: 8),
          Text(
            '$minutes:$seconds',
            style: TextStyle(
              color: isWarning ? Colors.redAccent : AppTheme.secondaryNeon,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}
