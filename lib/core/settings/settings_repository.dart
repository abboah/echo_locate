import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';

/// Small persistent settings store (Achieve-style repository over a Hive box).
///
/// Kept deliberately tiny; it's the first concrete example of the
/// repository pattern the rest of the app follows.
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

class HiveSettingsRepository implements SettingsRepository {
  HiveSettingsRepository(this._box);

  static const boxName = 'settings';
  static const _themeKey = 'themeMode';
  static const _onboardingKey = 'onboardingSeen';
  static const _cameraPrimerKey = 'cameraPrimerSeen';
  static const _locationPrimerKey = 'locationPrimerSeen';

  final Box _box;

  @override
  ThemeMode getThemeMode() {
    final raw = _box.get(_themeKey) as String?;
    return switch (raw) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  @override
  Future<void> setThemeMode(ThemeMode mode) =>
      _box.put(_themeKey, mode.name);

  @override
  bool get onboardingSeen => _box.get(_onboardingKey, defaultValue: false) as bool;

  @override
  Future<void> setOnboardingSeen() => _box.put(_onboardingKey, true);

  @override
  Future<void> resetOnboarding() => _box.put(_onboardingKey, false);

  @override
  bool get cameraPrimerSeen =>
      _box.get(_cameraPrimerKey, defaultValue: false) as bool;

  @override
  Future<void> setCameraPrimerSeen() => _box.put(_cameraPrimerKey, true);

  @override
  bool get locationPrimerSeen =>
      _box.get(_locationPrimerKey, defaultValue: false) as bool;

  @override
  Future<void> setLocationPrimerSeen() => _box.put(_locationPrimerKey, true);
}
