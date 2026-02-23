import 'package:flutter/material.dart';

class AppColors {
  // Primary Theme Colors
  static const Color tealGreen = Color(0xFF20B2AA); // Main teal green
  static const Color darkTeal = Color(0xFF008080); // Darker teal for emphasis
  static const Color lightTeal = Color(
    0xFF48C9B0,
  ); // Lighter teal for highlights

  // Neutral Colors
  static const Color white = Color(0xFFFFFFFF);
  static const Color black = Color(0xFF000000);
  static const Color darkGrey = Color(0xFF222831);
  static const Color mediumGrey = Color(0xFF6C757D);
  static const Color lightGrey = Color(0xFFF5F5F5);
  static const Color veryLightGrey = Color(0xFFF8F9FA);

  // Status Colors
  static const Color success = Color(0xFF28A745); // Green for success
  static const Color error = Color(0xFFDC3545); // Red for error
  static const Color warning = Color(
    0xFFFFC107,
  ); // Orange for warning/break points
  static const Color info = Color(0xFF17A2B8); // Blue for info
  static const Color leader = Color(0xFFFFB74D); // Amber for leader status

  // Primary and secondary colors for consistency
  static const Color primary = tealGreen;
  static const Color secondary = darkTeal;

  // Opacity variations
  static Color tealGreenWithOpacity(double opacity) =>
      tealGreen.withValues(alpha: opacity);
  static Color whiteWithOpacity(double opacity) => white.withValues(alpha: opacity);
  static Color blackWithOpacity(double opacity) => black.withValues(alpha: opacity);
  static Color greyWithOpacity(double opacity) =>
      mediumGrey.withValues(alpha: opacity);
}
