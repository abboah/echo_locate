import 'package:flutter/material.dart';

/// Application theme configuration for EchoLocate
class AppTheme {
  AppTheme._();

  // Color Palette
  static const Color primaryBackground = Color(0xFF0A0E1A);
  static const Color primaryAccent = Color(0xFF00E5CC);
  static const Color secondaryAccent = Color(0xFFE8EAF0);
  static const Color surfaceColor = Color(0xFF151B2E);
  static const Color errorColor = Color(0xFFFF5252);

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: primaryBackground,
      colorScheme: const ColorScheme.dark(
        primary: primaryAccent,
        secondary: secondaryAccent,
        surface: surfaceColor,
        error: errorColor,
        onPrimary: primaryBackground,
        onSecondary: primaryBackground,
        onSurface: secondaryAccent,
        onError: secondaryAccent,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: primaryBackground,
        foregroundColor: secondaryAccent,
        elevation: 0,
        centerTitle: true,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryAccent,
          foregroundColor: primaryBackground,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      cardTheme: CardThemeData(
        color: surfaceColor,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          color: secondaryAccent,
          fontSize: 32,
          fontWeight: FontWeight.bold,
        ),
        headlineMedium: TextStyle(
          color: secondaryAccent,
          fontSize: 24,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: TextStyle(color: secondaryAccent, fontSize: 16),
        bodyMedium: TextStyle(color: secondaryAccent, fontSize: 14),
      ),
    );
  }
}
