import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Small persistent settings store (repository over shared_preferences).
///
/// Kept deliberately tiny; it's the first concrete example of the
/// repository pattern the rest of the app follows. shared_preferences is
/// the one deliberate exception to the hive_ce rule: tiny scalar flags
/// (onboarding/theme/primers) are what it exists for, and supabase_flutter
/// already persists its session through it.
abstract class SettingsRepository {
  ThemeMode getThemeMode();
  Future<void> setThemeMode(ThemeMode mode);

  /// Whether the 3-step intro has been completed (router gate).
  bool get onboardingSeen;
  Future<void> setOnboardingSeen();

  /// Clears the intro flag so it plays again ("View the intro" on Profile).
  Future<void> resetOnboarding();

  /// Whether the camera permission primer was shown before the first scan.
  bool get cameraPrimerSeen;
  Future<void> setCameraPrimerSeen();

  /// Whether the location permission primer was shown before first Explore.
  bool get locationPrimerSeen;
  Future<void> setLocationPrimerSeen();
}

class SharedPrefsSettingsRepository implements SettingsRepository {
  SharedPrefsSettingsRepository(this._prefs);

  static const _themeKey = 'themeMode';
  static const _onboardingKey = 'onboardingSeen';
  static const _cameraPrimerKey = 'cameraPrimerSeen';
  static const _locationPrimerKey = 'locationPrimerSeen';

  final SharedPreferences _prefs;

  @override
  ThemeMode getThemeMode() {
    final raw = _prefs.getString(_themeKey);
    return switch (raw) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  @override
  Future<void> setThemeMode(ThemeMode mode) async =>
      _prefs.setString(_themeKey, mode.name);

  @override
  bool get onboardingSeen => _prefs.getBool(_onboardingKey) ?? false;

  @override
  Future<void> setOnboardingSeen() async =>
      _prefs.setBool(_onboardingKey, true);

  @override
  Future<void> resetOnboarding() async =>
      _prefs.setBool(_onboardingKey, false);

  @override
  bool get cameraPrimerSeen => _prefs.getBool(_cameraPrimerKey) ?? false;

  @override
  Future<void> setCameraPrimerSeen() async =>
      _prefs.setBool(_cameraPrimerKey, true);

  @override
  bool get locationPrimerSeen => _prefs.getBool(_locationPrimerKey) ?? false;

  @override
  Future<void> setLocationPrimerSeen() async =>
      _prefs.setBool(_locationPrimerKey, true);
}
