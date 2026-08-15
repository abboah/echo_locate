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
    // Colour every style before overriding individual ones.
    //
    // `GoogleFonts.lexendTextTheme()` returns Material's **light** palette —
    // near-black text — for any style not named below. In dark mode that is
    // near-black on near-black, and the text is not dim but *invisible*.
    //
    // It bit `bodySmall` and `titleSmall` in particular, which between them
    // carry almost every hint, warning and summary line in the app: the wing
    // drift warning, "rooms with no door yet", the mapping hub's next-floor
    // line, the door-count caution. All of them silently unreadable on a dark
    // phone, which is the one place the guidance they carry matters most.
    //
    // Applying the palette up front means a style added to the app later
    // inherits a readable colour instead of inheriting the bug.
    final base = GoogleFonts.lexendTextTheme().apply(
      bodyColor: onSurface,
      displayColor: onSurface,
    );
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
      // Secondary body copy: hints, captions, the line under a heading. Muted
      // like bodyMedium, and stated rather than inherited.
      bodySmall: base.bodySmall?.copyWith(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        color: muted,
      ),
      titleSmall: base.titleSmall?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: onSurface,
      ),
    );
  }
}
