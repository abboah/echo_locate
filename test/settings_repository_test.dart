import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:echo_locate/core/settings/settings_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<SharedPrefsSettingsRepository> repoWith(
      [Map<String, Object> seed = const {}]) async {
    SharedPreferences.setMockInitialValues(seed);
    return SharedPrefsSettingsRepository(
        await SharedPreferences.getInstance());
  }

  test('fresh install: onboarding unseen, theme follows system', () async {
    final repo = await repoWith();
    expect(repo.onboardingSeen, isFalse);
    expect(repo.cameraPrimerSeen, isFalse);
    expect(repo.locationPrimerSeen, isFalse);
    expect(repo.getThemeMode(), ThemeMode.system);
  });

  test('onboarding flag persists and resets', () async {
    final repo = await repoWith();
    await repo.setOnboardingSeen();
    expect(repo.onboardingSeen, isTrue);
    await repo.resetOnboarding();
    expect(repo.onboardingSeen, isFalse);
  });

  test('reads flags written by a previous session', () async {
    final repo = await repoWith({'onboardingSeen': true, 'themeMode': 'dark'});
    expect(repo.onboardingSeen, isTrue);
    expect(repo.getThemeMode(), ThemeMode.dark);
  });

  test('theme round-trips through prefs', () async {
    final repo = await repoWith();
    await repo.setThemeMode(ThemeMode.dark);
    expect(repo.getThemeMode(), ThemeMode.dark);
    await repo.setThemeMode(ThemeMode.light);
    expect(repo.getThemeMode(), ThemeMode.light);
  });
}
