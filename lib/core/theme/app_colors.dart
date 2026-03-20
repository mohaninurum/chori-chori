import 'package:flutter/material.dart';

class AppColors {
  // Dark mode optimized, romantic & private neon aesthetic
  static const Color backgroundDark = Color(0xFF0F0F13);
  static const Color backgroundLight = Color(0xFF1C1C23);
  
  static const Color primaryNeonPink = Color(0xFFFF2E93);
  static const Color primaryNeonPurple = Color(0xFF9D4EDD);
  static const Color primaryNeonBlue = Color(0xFF00F0FF);
  
  static const Color textBright = Color(0xFFFFFFFF);
  static const Color textMuted = Color(0xFFA0A0AB);
  
  static const Color successGreen = Color(0xFF00FF66);
  static const Color warningOrange = Color(0xFFFFB000);
  static const Color errorRed = Color(0xFFFF3366);

  static const Color inputBackground = Color(0xFF2A2A35);
  static const Color dividerColor = Color(0xFF3A3A4A);

  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primaryNeonPurple, primaryNeonPink],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
