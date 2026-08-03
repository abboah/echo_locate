import 'dart:async';

import 'package:get_it/get_it.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/app_config.dart';
import '../core/settings/settings_repository.dart';
import '../core/theme/theme_cubit.dart';
import '../data/repository_mixin.dart';
import '../features/assist/bloc/assist_bloc.dart';
import '../features/auth/auth_repository.dart';
import '../features/auth/bloc/auth_bloc.dart';
import '../features/auth/supabase_auth_repository.dart';
import '../features/building_detail/bloc/building_detail_bloc.dart';
import '../features/buildings/building_repository.dart';
import '../features/explore/bloc/explore_bloc.dart';
import '../features/home/bloc/home_bloc.dart';
import '../features/maps/bloc/maps_bloc.dart';
import '../features/profile/bloc/profile_bloc.dart';
import '../features/profile/profile_repository.dart';
import '../features/scan/bloc/scan_capability_cubit.dart';
import '../features/acoustic/bloc/acoustic_bloc.dart';
import '../features/sonar/bloc/sonar_bloc.dart';
import 'acoustic/acoustic_fallback_service.dart';
import 'audio/audio_arbiter.dart';
import 'audio/sonar_audio_service.dart';
import 'sensing/detection_service.dart';
import 'speech/speech_service.dart';
import 'vision/arcore_depth_service.dart';
import 'vision/depth_reliability.dart';

/// Global service locator. Repositories, blocs/cubits, and stream controllers
/// are registered here. See CLAUDE.md for the per-feature registration recipe.
final getIt = GetIt.instance;

/// Call once at startup (after `Hive.initFlutter()`), before `runApp`.
Future<void> configureDependencies() async {
  // --- Local persistence ---
  final prefs = await SharedPreferences.getInstance(); // settings/onboarding
  await Hive.openBox(
    repoCacheBoxName,
  ); // backs RepositoryMixin persisted queries
  // Mock auth keeps its session in a Hive box; only needed without Supabase.
  final mockAuthBox = AppConfig.hasSupabase
      ? null
      : await Hive.openBox(MockAuthRepository.boxName);
  // Sonar's clutter profile: an array, so hive_ce rather than prefs.
  final sonarCalibrationBox = await Hive.openBox(
    SonarAudioService.calibrationBoxName,
  );

  // --- Repositories (mock impls behind abstract interfaces; Supabase
  //     versions swap in per-line here in Phase 2 without touching UI) ---
  getIt.registerLazySingleton<SettingsRepository>(
    () => SharedPrefsSettingsRepository(prefs),
  );
  getIt.registerLazySingleton<AuthRepository>(
    () => AppConfig.hasSupabase
        ? SupabaseAuthRepository(Supabase.instance.client)
        : MockAuthRepository(mockAuthBox!),
  );
  getIt.registerLazySingleton<BuildingRepository>(
    () => MockBuildingRepository(),
  );
  getIt.registerLazySingleton<ProfileRepository>(
    () => MockProfileRepository(getIt<AuthRepository>()),
  );

  // --- Sensing / speech engines (hardware owners; Blocs subscribe) ---
  getIt.registerLazySingleton<DetectionService>(() => DetectionService());
  // Single arbiter shared by everything that drives the mic or speaker; it is
  // the thing that makes "shared" safe, so it must be a singleton.
  getIt.registerLazySingleton<AudioArbiter>(() => AudioArbiter());
  getIt.registerLazySingleton<SpeechService>(
    () => SpeechService(arbiter: getIt<AudioArbiter>()),
  );
  getIt.registerLazySingleton<SonarAudioService>(
    () => SonarAudioService(
      calibrationBox: sonarCalibrationBox,
      arbiter: getIt<AudioArbiter>(),
    ),
  );
  getIt.registerLazySingleton<ArCoreDepthService>(() => ArCoreDepthService());

  // The camera↔sound hand-off (M5). Registered as a pair: DepthReliability
  // decides when camera depth has failed, AcousticFallbackService answers
  // with sound. Singletons because the fallback carries the measurement
  // throttle — a per-screen copy would let two screens chirp over each other.
  getIt.registerLazySingleton<DepthReliability>(() => const DepthReliability());
  getIt.registerLazySingleton<AcousticFallbackService>(
    () => AcousticFallbackService(getIt<SonarAudioService>()),
  );

  // --- App-wide cubits/blocs (singletons) ---
  getIt.registerLazySingleton<ThemeCubit>(
    () => ThemeCubit(getIt<SettingsRepository>()),
  );
  getIt.registerLazySingleton<AuthBloc>(
    () => AuthBloc(getIt<AuthRepository>()),
  );
  getIt.registerLazySingleton<ScanCapabilityCubit>(
    () => ScanCapabilityCubit(getIt<ArCoreDepthService>()),
  );
  // Kicked off, not awaited: the ARCore query can take a moment on first call
  // and nothing should hold up first paint for it. The cubit starts in
  // `checking`, which hides scan entry points until the answer lands.
  unawaited(getIt<ScanCapabilityCubit>().resolve());

  // --- Feature blocs (one fresh instance per screen visit) ---
  getIt.registerFactory<AssistBloc>(
    () => AssistBloc(getIt<DetectionService>(), getIt<SpeechService>()),
  );
  getIt.registerFactory<HomeBloc>(() => HomeBloc(getIt<BuildingRepository>()));
  getIt.registerFactory<ExploreBloc>(
    () => ExploreBloc(getIt<BuildingRepository>()),
  );
  getIt.registerFactory<BuildingDetailBloc>(
    () => BuildingDetailBloc(getIt<BuildingRepository>()),
  );
  getIt.registerFactory<MapsBloc>(() => MapsBloc(getIt<BuildingRepository>()));
  getIt.registerFactory<ProfileBloc>(
    () => ProfileBloc(getIt<ProfileRepository>()),
  );
  getIt.registerFactory<SonarBloc>(() => SonarBloc(getIt<SonarAudioService>()));
  // Shares the sonar's audio service: same speaker, mic and chirp, captured
  // differently (one pulse plus a long decay, rather than a train).
  getIt.registerFactory<AcousticBloc>(
    () => AcousticBloc(getIt<SonarAudioService>()),
  );
}
