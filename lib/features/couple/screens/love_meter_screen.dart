import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import 'dart:math';

class LoveMeterScreen extends StatefulWidget {
  const LoveMeterScreen({super.key});

  @override
  State<LoveMeterScreen> createState() => _LoveMeterScreenState();
}

class _LoveMeterScreenState extends State<LoveMeterScreen> with SingleTickerProviderStateMixin {
  int _score = 0;
  bool _isCalculating = false;
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
       vsync: this, 
       duration: const Duration(seconds: 2)
    );
    _animation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut)
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _calculateScore() {
    setState(() {
      _isCalculating = true;
      _score = Random().nextInt(50) + 50; // Random score between 50 and 100 for fun
    });
    _controller.reset();
    _controller.forward().then((_) {
      setState(() => _isCalculating = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Love Meter')),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [AppTheme.backgroundDark, AppTheme.backgroundLight],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
               AnimatedBuilder(
                  animation: _animation,
                  builder: (context, child) {
                    final currentScore = (_score * _animation.value).toInt();
                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          height: 200,
                          width: 200,
                          child: CircularProgressIndicator(
                            value: _animation.value * (_score / 100),
                            strokeWidth: 16,
                            color: AppTheme.primaryNeon,
                            backgroundColor: Colors.white12,
                          ),
                        ),
                        Text(
                          '$currentScore%',
                          style: const TextStyle(
                            fontSize: 48,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryNeon,
                          ),
                        ),
                      ],
                    );
                  },
               ),
               const SizedBox(height: 60),
               if (!_isCalculating)
                 ElevatedButton.icon(
                   icon: const Icon(Icons.favorite),
                   label: const Text('Calculate Compatibility'),
                   onPressed: _calculateScore,
                 )
               else
                 const Text('Analyzing vibes...', style: TextStyle(color: Colors.white54)),
            ],
          ),
        ),
      ),
    );
  }
}
