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
import '../features/room_trace/bloc/room_trace_bloc.dart';
import '../features/room_trace/room_plan_repository.dart';
import '../features/room_trace/supabase_room_plan_repository.dart';
import '../features/buildings/supabase_building_repository.dart';
import '../features/capture/bloc/capture_bloc.dart';
import '../features/explore/bloc/explore_bloc.dart';
import '../features/guidance/bloc/guidance_bloc.dart';
import '../features/home/bloc/home_bloc.dart';
import '../features/maps/bloc/maps_bloc.dart';
import '../features/profile/bloc/profile_bloc.dart';
import '../features/profile/bloc/stride_calibration_cubit.dart';
import '../features/profile/profile_repository.dart';
import '../features/map_building/bloc/map_building_cubit.dart';
import '../features/plan_trace/bloc/plan_trace_bloc.dart';
import '../features/routing/bloc/floor_map_bloc.dart';
import '../features/routing/route_repository.dart';
import '../features/routing/supabase_route_repository.dart';
import '../features/scan/bloc/scan_capability_cubit.dart';
import '../features/acoustic/bloc/acoustic_bloc.dart';
import '../features/sonar/bloc/sonar_bloc.dart';
import 'acoustic/acoustic_fallback_service.dart';
import 'audio/audio_arbiter.dart';
import 'audio/sonar_audio_service.dart';
import 'haptics/haptic_service.dart';
import 'mapping/plan_photo_service.dart';
import '../features/profile/supabase_profile_repository.dart';
import 'motion/step_service.dart';
import 'sensing/detection_service.dart';
import 'sensing/landmark_matcher.dart';
import 'sensing/text_recognition_service.dart';
import 'speech/speech_service.dart';
import 'vision/ar_guidance_service.dart';
import 'vision/arcore_capture_service.dart';
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
  // Landmarks + recorded routes. Shared by both work streams: Stream A reads
  // it to lay out the 2D schematic and build the A* graph, Stream B to guide
  // and to upload captures. See docs/landmark-navigation-spec.md.
  getIt.registerLazySingleton<RouteRepository>(
    () => AppConfig.hasSupabase
        ? SupabaseRouteRepository(Supabase.instance.client)
        : MockRouteRepository(),
  );
  getIt.registerLazySingleton<BuildingRepository>(
    () => AppConfig.hasSupabase
        ? SupabaseBuildingRepository(Supabase.instance.client)
        : MockBuildingRepository(),
  );
  // Traced room geometry — the areas the schematic is drawn from and the doors
  // that make "the second door on your left" possible.
  //
  // Falls back to on-device storage rather than to a mock, unlike its
  // neighbours. A contributor tracing a floor has done twenty minutes of work
  // that a mock would drop on the floor, and tracing is the one thing here that
  // is genuinely useful offline: it happens standing in a corridor, in front of
  // a board, on a campus connection.
  getIt.registerLazySingleton<RoomPlanRepository>(
    () => AppConfig.hasSupabase
        ? SupabaseRoomPlanRepository(Supabase.instance.client)
        : const LocalRoomPlanRepository(),
  );
  getIt.registerLazySingleton<ProfileRepository>(
    () => AppConfig.hasSupabase
        ? SupabaseProfileRepository(Supabase.instance.client)
        : MockProfileRepository(getIt<AuthRepository>()),
  );

  // --- Sensing / speech engines (hardware owners; Blocs subscribe) ---
  // Sign reading (Stream B). A singleton because it is fed by the one camera
  // stream DetectionService owns: a per-screen copy would sit idle while
  // frames went to the instance nobody was listening to.
  getIt.registerLazySingleton<TextRecognitionService>(
    () => TextRecognitionService(),
  );
  // AR guidance owns a session whose camera frames DetectionService can use.
  // Registered before it, and handed to it, because the choice of frame source
  // is made inside `DetectionService.start()`: an AR session that is already
  // streaming wins, since ARCore holds the camera exclusively and the plugin
  // could not open it anyway.
  getIt.registerLazySingleton<ArGuidanceService>(() => ArGuidanceService());
  getIt.registerLazySingleton<DetectionService>(
    () => DetectionService(
      textRecognition: getIt<TextRecognitionService>(),
      arFrames: getIt<ArGuidanceService>(),
    ),
  );
  // Pure matching rules, no hardware — see LandmarkMatcher for why the spec's
  // plain Levenshtein tolerance was tightened.
  getIt.registerLazySingleton<LandmarkMatcher>(() => const LandmarkMatcher());
  // Step counting (Stream B). A singleton because the baseline it holds *is*
  // the leg's progress — a per-screen copy would restart the count every time
  // the guidance screen rebuilt.
  getIt.registerLazySingleton<StepService>(() => StepService());
  // Single arbiter shared by everything that drives the mic or speaker; it is
  // the thing that makes "shared" safe, so it must be a singleton.
  getIt.registerLazySingleton<AudioArbiter>(() => AudioArbiter());
  // Stateless wrapper round the platform channel; a singleton only to save
  // allocating one per screen.
  getIt.registerLazySingleton<HapticService>(() => const HapticService());
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
  // AR room capture. A separate session from the depth spike — ARCore holds
  // the camera exclusively, so the two are never running at once, and the
  // screens that own them stop one before starting the other.
  getIt.registerLazySingleton<ArCoreCaptureService>(
    () => ArCoreCaptureService(),
  );

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
  // Landmark navigation. The map bloc merges recorded walks into one graph;
  // guidance and capture share the camera, the counter and the voice, which is
  // why all three take the same singletons rather than opening their own.
  getIt.registerFactory<FloorMapBloc>(
    () => FloorMapBloc(
      getIt<RouteRepository>(),
      buildings: getIt<BuildingRepository>(),
    ),
  );
  getIt.registerFactory<GuidanceBloc>(
    () => GuidanceBloc(
      detection: getIt<DetectionService>(),
      textRecognition: getIt<TextRecognitionService>(),
      steps: getIt<StepService>(),
      speech: getIt<SpeechService>(),
      haptics: getIt<HapticService>(),
      matcher: getIt<LandmarkMatcher>(),
    ),
  );
  // Tracing owns its own camera rather than sharing DetectionService's: that
  // one streams medium-resolution frames for ML Kit, and a floor plan needs one
  // still at full detail, because the contributor reads room numbers off it.
  getIt.registerFactory<PlanTraceBloc>(
    () => PlanTraceBloc(
      getIt<RouteRepository>(),
      PlanPhotoService(),
      getIt<BuildingRepository>(),
    ),
  );
  // Room tracing, the same shape as PlanTraceBloc above and for the same
  // reason: a factory, so each tracing session gets its own camera service
  // with its own start/stop lifecycle rather than sharing one that a previous
  // screen may have left holding the camera.
  getIt.registerFactory<RoomTraceBloc>(
    () => RoomTraceBloc(
      getIt<RoomPlanRepository>(),
      PlanPhotoService(),
      getIt<BuildingRepository>(),
    ),
  );
  getIt.registerFactory<MapBuildingCubit>(
    () => MapBuildingCubit(getIt<BuildingRepository>()),
  );
  getIt.registerFactory<CaptureBloc>(
    () => CaptureBloc(
      detection: getIt<DetectionService>(),
      textRecognition: getIt<TextRecognitionService>(),
      steps: getIt<StepService>(),
      routes: getIt<RouteRepository>(),
      matcher: getIt<LandmarkMatcher>(),
    ),
  );
  getIt.registerFactory<StrideCalibrationCubit>(
    () => StrideCalibrationCubit(
      getIt<StepService>(),
      getIt<ProfileRepository>(),
    ),
  );
  // Shares the sonar's audio service: same speaker, mic and chirp, captured
  // differently (one pulse plus a long decay, rather than a train).
  getIt.registerFactory<AcousticBloc>(
    () => AcousticBloc(getIt<SonarAudioService>()),
  );
}
