import 'package:get_it/get_it.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import '../core/settings/settings_repository.dart';
import '../core/theme/theme_cubit.dart';
import '../data/repository_mixin.dart';
import '../features/auth/auth_repository.dart';
import '../features/auth/bloc/auth_bloc.dart';
import '../features/building_detail/bloc/building_detail_bloc.dart';
import '../features/buildings/building_repository.dart';
import '../features/explore/bloc/explore_bloc.dart';
import '../features/home/bloc/home_bloc.dart';
import '../features/maps/bloc/maps_bloc.dart';
import '../features/profile/bloc/profile_bloc.dart';
import '../features/profile/profile_repository.dart';

/// Global service locator. Repositories, blocs/cubits, and stream controllers
/// are registered here. See CLAUDE.md for the per-feature registration recipe.
final getIt = GetIt.instance;

/// Call once at startup (after `Hive.initFlutter()`), before `runApp`.
Future<void> configureDependencies() async {
  // --- Local persistence ---
  final settingsBox = await Hive.openBox(HiveSettingsRepository.boxName);
  await Hive.openBox(repoCacheBoxName); // backs RepositoryMixin persisted queries

  // --- Repositories (mock impls behind abstract interfaces; Supabase
  //     versions swap in per-line here in Phase 2 without touching UI) ---
  getIt.registerLazySingleton<SettingsRepository>(
    () => HiveSettingsRepository(settingsBox),
  );
  getIt.registerLazySingleton<AuthRepository>(
    () => MockAuthRepository(settingsBox),
  );
  getIt.registerLazySingleton<BuildingRepository>(
    () => MockBuildingRepository(),
  );
  getIt.registerLazySingleton<ProfileRepository>(
    () => MockProfileRepository(getIt<AuthRepository>()),
  );

  // --- App-wide cubits/blocs (singletons) ---
  getIt.registerLazySingleton<ThemeCubit>(
    () => ThemeCubit(getIt<SettingsRepository>()),
  );
  getIt.registerLazySingleton<AuthBloc>(
    () => AuthBloc(getIt<AuthRepository>()),
  );

  // --- Feature blocs (one fresh instance per screen visit) ---
  getIt.registerFactory<HomeBloc>(
    () => HomeBloc(getIt<BuildingRepository>()),
  );
  getIt.registerFactory<ExploreBloc>(
    () => ExploreBloc(getIt<BuildingRepository>()),
  );
  getIt.registerFactory<BuildingDetailBloc>(
    () => BuildingDetailBloc(getIt<BuildingRepository>()),
  );
  getIt.registerFactory<MapsBloc>(
    () => MapsBloc(getIt<BuildingRepository>()),
  );
  getIt.registerFactory<ProfileBloc>(
    () => ProfileBloc(getIt<ProfileRepository>()),
  );
}
