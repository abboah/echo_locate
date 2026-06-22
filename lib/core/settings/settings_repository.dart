import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';

/// Small persistent settings store (Achieve-style repository over a Hive box).
///
/// Kept deliberately tiny; it's the first concrete example of the
/// repository pattern the rest of the app follows.
abstract class SettingsRepository {
  ThemeMode getThemeMode();
  Future<void> setThemeMode(ThemeMode mode);
}

class HiveSettingsRepository implements SettingsRepository {
  HiveSettingsRepository(this._box);

  static const boxName = 'settings';
  static const _themeKey = 'themeMode';

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
}
