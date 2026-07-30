import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Typography for EchoLocate — Lexend.
///
/// Lexend was designed around reading-fluency research, which matches the
/// app's low-vision audience; body sizes run slightly larger than Material
/// defaults for the same reason. Uses `google_fonts` for now; can be swapped
/// for bundled font files later (preferred for fully-offline use).
class AppTypography {
  AppTypography._();

  static TextTheme textTheme(Color onSurface, Color muted) {
    final base = GoogleFonts.lexendTextTheme();
    return base.copyWith(
      displaySmall: base.displaySmall?.copyWith(
        fontSize: 30,
        fontWeight: FontWeight.w700,
        color: onSurface,
        height: 1.15,
      ),
      headlineMedium: base.headlineMedium?.copyWith(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: onSurface,
      ),
      titleLarge: base.titleLarge?.copyWith(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: onSurface,
      ),
      titleMedium: base.titleMedium?.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: onSurface,
      ),
      bodyLarge: base.bodyLarge?.copyWith(
        fontSize: 17,
        fontWeight: FontWeight.w400,
        color: onSurface,
      ),
      bodyMedium: base.bodyMedium?.copyWith(
        fontSize: 15,
        fontWeight: FontWeight.w400,
        color: muted,
      ),
      labelLarge: base.labelLarge?.copyWith(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: onSurface,
      ),
      labelSmall: base.labelSmall?.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: muted,
        letterSpacing: 0.4,
      ),
    );
  }
}
