import 'package:flutter/material.dart';

/// EchoLocate color tokens.
///
/// From the Figma design system (`MGYeyWGqLMH3rSaabjvfvI`):
/// "clean, one warm accent, white surfaces, no gradients."
/// Light values are taken directly from the token sheet; dark values are
/// derived from the same Ink family with Coral kept as the single accent.
class AppColors {
  AppColors._();

  // --- Brand accent (shared across light & dark) ---
  static const Color coral = Color(0xFFFB5B47);
  static const Color coralPressed = Color(0xFFE24C3A);
  static const Color coralSoft = Color(0xFFFFE9E5); // tinted accent backgrounds

  // --- Light palette (from Figma tokens) ---
  static const Color ink = Color(0xFF1C1B1A); // primary text / dark surfaces
  static const Color surface = Color(0xFFF6F5F2); // cards, muted panels
  static const Color white = Color(0xFFFFFFFF); // page background
  static const Color inkMuted = Color(0xFF6B6966); // secondary text
  static const Color hairline = Color(0xFFE7E5E1); // dividers / borders

  // --- Dark palette (derived from the Ink family) ---
  static const Color darkBackground = Color(0xFF141312);
  static const Color darkSurface = Color(0xFF1F1E1C);
  static const Color darkElevated = Color(0xFF272522);
  static const Color darkOnSurface = Color(0xFFF6F5F2);
  static const Color darkMuted = Color(0xFF9A9794);
  static const Color darkHairline = Color(0xFF332F2B);

  // --- Semantic (shared) ---
  static const Color warning = Color(0xFFE6A23C);
  static const Color warningSoft = Color(0xFFFDF6EC);
  static const Color error = Color(0xFFE5484D);
  static const Color errorSoft = Color(0xFFFDECEC);
  static const Color success = coral; // brand uses coral for confirmations
}
