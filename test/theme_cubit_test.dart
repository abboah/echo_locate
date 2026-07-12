import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:echo_locate/core/settings/settings_repository.dart';
import 'package:echo_locate/core/theme/theme_cubit.dart';

/// In-memory fake of the settings repository (no Hive needed).
class _FakeSettingsRepository implements SettingsRepository {
  ThemeMode mode = ThemeMode.light;

  @override
  ThemeMode getThemeMode() => mode;

  @override
  Future<void> setThemeMode(ThemeMode m) async => mode = m;

  @override
  bool onboardingSeen = false;

  @override
  Future<void> setOnboardingSeen() async => onboardingSeen = true;

  @override
  bool cameraPrimerSeen = false;

  @override
  Future<void> setCameraPrimerSeen() async => cameraPrimerSeen = true;

  @override
  bool locationPrimerSeen = false;

  @override
  Future<void> setLocationPrimerSeen() async => locationPrimerSeen = true;
}

void main() {
  test('ThemeCubit seeds from the repository', () {
    final settings = _FakeSettingsRepository()..mode = ThemeMode.dark;
    final cubit = ThemeCubit(settings);
    expect(cubit.state, ThemeMode.dark);
  });

  test('toggle flips light <-> dark and persists', () async {
    final settings = _FakeSettingsRepository()..mode = ThemeMode.light;
    final cubit = ThemeCubit(settings);

    await cubit.toggle();
    expect(cubit.state, ThemeMode.dark);
    expect(settings.mode, ThemeMode.dark);

    await cubit.toggle();
    expect(cubit.state, ThemeMode.light);
    expect(settings.mode, ThemeMode.light);
  });
}
