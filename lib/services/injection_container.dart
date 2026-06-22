import 'package:get_it/get_it.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import '../core/settings/settings_repository.dart';
import '../core/theme/theme_cubit.dart';

/// Global service locator. Repositories, blocs/cubits, and stream controllers
/// are registered here. See CLAUDE.md for the per-feature registration recipe.
final getIt = GetIt.instance;

/// Call once at startup (after `Hive.initFlutter()`), before `runApp`.
Future<void> configureDependencies() async {
  // --- Local persistence ---
  final settingsBox = await Hive.openBox(HiveSettingsRepository.boxName);

  // --- Repositories ---
  getIt.registerLazySingleton<SettingsRepository>(
    () => HiveSettingsRepository(settingsBox),
  );

  // --- Cubits / Blocs (app-wide singletons) ---
  getIt.registerLazySingleton<ThemeCubit>(
    () => ThemeCubit(getIt<SettingsRepository>()),
  );
}
