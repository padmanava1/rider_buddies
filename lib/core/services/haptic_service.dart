import 'package:flutter/services.dart';

class HapticService {
  static Future<void> lightImpact() async {
    await HapticFeedback.lightImpact();
  }

  static Future<void> mediumImpact() async {
    await HapticFeedback.mediumImpact();
  }

  static Future<void> heavyImpact() async {
    await HapticFeedback.heavyImpact();
  }

  static Future<void> selection() async {
    await HapticFeedback.selectionClick();
  }

  static Future<void> success() async {
    await HapticFeedback.lightImpact();
  }

  static Future<void> error() async {
    await HapticFeedback.heavyImpact();
  }

  static Future<void> warning() async {
    await HapticFeedback.mediumImpact();
  }
}
