import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../settings/settings_repository.dart';

/// Owns the app's [ThemeMode], persisted via [SettingsRepository].
///
/// `MaterialApp` rebuilds through `BlocBuilder<ThemeCubit, ThemeMode>`.
class ThemeCubit extends Cubit<ThemeMode> {
  ThemeCubit(this._settings) : super(_settings.getThemeMode());

  final SettingsRepository _settings;

  Future<void> setMode(ThemeMode mode) async {
    await _settings.setThemeMode(mode);
    emit(mode);
  }

  /// Convenience toggle between light and dark.
  Future<void> toggle() => setMode(
        state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark,
      );
}
