import 'package:flutter/services.dart';

/// Haptic feedback for key actions, one vocabulary for both apps (see mobile/DESIGN.md → Haptics).
class FgHaptics {
  const FgHaptics._();

  /// Selection changed (chip, segment, tab, checklist answer).
  static void tap() => HapticFeedback.selectionClick();

  /// A light confirmation (pull-to-refresh started, sheet opened).
  static void light() => HapticFeedback.lightImpact();

  /// A command was sent or queued (start, finish, submit, approve).
  static void success() => HapticFeedback.mediumImpact();

  /// A warning or a refused command.
  static void warning() => HapticFeedback.heavyImpact();

  /// A code was read by the scanner.
  static void scan() => HapticFeedback.vibrate();
}
