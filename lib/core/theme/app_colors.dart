import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // Purple - Blue Ticket Palette
  static const Color primaryPurple = Color(0xFF6C5CE7);
  static const Color primaryPurpleDark = Color(0xFF4834D4);
  static const Color primaryBlue = Color(0xFF0984E3);
  static const Color accentCyan = Color(0xFF00CEC9);
  static const Color ticketGold = Color(0xFFFFA801);
  static const Color successGreen = Color(0xFF00B894);
  static const Color errorRed = Color(0xFFD63031);

  // Light Theme
  static const Color lightBackground = Color(0xFFF7F8FC);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightCard = Color(0xFFF0F3FA);
  static const Color lightTextPrimary = Color(0xFF1E272E);
  static const Color lightTextSecondary = Color(0xFF808E9B);
  static const Color lightBorder = Color(0xFFE2E8F0);

  // Dark Theme
  static const Color darkBackground = Color(0xFF0F111A);
  static const Color darkSurface = Color(0xFF181B26);
  static const Color darkCard = Color(0xFF222636);
  static const Color darkTextPrimary = Color(0xFFF5F6FA);
  static const Color darkTextSecondary = Color(0xFF9BA4B5);
  static const Color darkBorder = Color(0xFF2E3447);

  // Gradient
  static const LinearGradient ticketGradient = LinearGradient(
    colors: [primaryPurple, primaryBlue],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient accentGradient = LinearGradient(
    colors: [primaryBlue, accentCyan],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
