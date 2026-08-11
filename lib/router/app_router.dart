import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/models/building.dart';
import '../core/routes/app_routes.dart';
import '../core/settings/settings_repository.dart';
import '../features/auth/bloc/auth_bloc.dart';
import '../features/guidance/guidance_session.dart';
import '../services/injection_container.dart';
import '../ui/pages/assist/assist_page.dart';
import '../ui/pages/capture/capture_page.dart';
import '../ui/pages/map_building/map_building_page.dart';
import '../ui/pages/plan_trace/plan_trace_page.dart';
import '../ui/pages/guidance/guidance_page.dart';
import '../ui/pages/profile/stride_calibration_page.dart';
import '../ui/pages/auth/sign_in_page.dart';
import '../ui/pages/auth/sign_up_page.dart';
import '../ui/pages/auth/welcome_page.dart';
import '../ui/pages/building/building_detail_page.dart';
import '../ui/pages/explore/explore_page.dart';
import '../ui/pages/home/home_page.dart';
import '../ui/pages/maps/maps_page.dart';
import '../ui/pages/navigate/navigation_page.dart';
import '../ui/pages/onboarding/onboarding_page.dart';
import '../ui/pages/primers/camera_primer_page.dart';
import '../ui/pages/depth/depth_probe_page.dart';
import '../ui/pages/primers/location_primer_page.dart';
import '../ui/pages/profile/profile_page.dart';
import '../ui/pages/scan/scan_page.dart';
import '../ui/pages/shell/app_shell.dart';
import '../ui/pages/acoustic/acoustic_page.dart';
import '../ui/pages/sonar/sonar_page.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();

const _guestPaths = {
  AppRoutes.onboarding,
  AppRoutes.welcome,
  AppRoutes.signIn,
  AppRoutes.signUp,
};

/// App router: guest tree (onboarding/auth) vs user tree (shell + flows),
/// swapped by [_redirect] whenever [AuthBloc] emits.
final GoRouter appRouter = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: AppRoutes.home,
  refreshListenable: _StreamListenable(getIt<AuthBloc>().stream),
  redirect: _redirect,
  routes: [
    // --- Guest ---
    GoRoute(
      path: AppRoutes.onboarding,
      name: RouteNames.onboarding,
      builder: (context, state) => const OnboardingPage(),
    ),
    GoRoute(
      path: AppRoutes.welcome,
      name: RouteNames.welcome,
      builder: (context, state) => const WelcomePage(),
    ),
    GoRoute(
      path: AppRoutes.signIn,
      name: RouteNames.signIn,
      builder: (context, state) => const SignInPage(),
    ),
    GoRoute(
      path: AppRoutes.signUp,
      name: RouteNames.signUp,
      builder: (context, state) => const SignUpPage(),
    ),

    // --- User: 5-tab shell (Home · Explore · [Scan FAB] · Maps · Profile) ---
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          AppShell(navigationShell: navigationShell),
      branches: [
        StatefulShellBranch(routes: [
          GoRoute(
            path: AppRoutes.home,
            name: RouteNames.home,
            builder: (context, state) => const HomePage(),
          ),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(
            path: AppRoutes.explore,
            name: RouteNames.explore,
            builder: (context, state) => const ExplorePage(),
          ),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(
            path: AppRoutes.maps,
            name: RouteNames.maps,
            builder: (context, state) => const MapsPage(),
          ),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(
            path: AppRoutes.profile,
            name: RouteNames.profile,
            builder: (context, state) => const ProfilePage(),
          ),
        ]),
      ],
    ),

    // --- User: full-screen flows above the shell ---
    GoRoute(
      path: AppRoutes.assist,
      name: RouteNames.assist,
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const AssistPage(),
    ),
    GoRoute(
      path: AppRoutes.scan,
      name: RouteNames.scan,
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const ScanPage(),
    ),
    GoRoute(
      path: AppRoutes.sonar,
      name: RouteNames.sonar,
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const SonarPage(),
    ),
    GoRoute(
      path: AppRoutes.acoustic,
      name: RouteNames.acoustic,
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const AcousticPage(),
    ),
    GoRoute(
      path: AppRoutes.depthProbe,
      name: RouteNames.depthProbe,
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const DepthProbePage(),
    ),
    GoRoute(
      path: AppRoutes.cameraPrimer,
      name: RouteNames.cameraPrimer,
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => CameraPrimerPage(
        destinationName: state.extra as String? ?? RouteNames.assist,
      ),
    ),
    GoRoute(
      path: AppRoutes.locationPrimer,
      name: RouteNames.locationPrimer,
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const LocationPrimerPage(),
    ),
    GoRoute(
      path: AppRoutes.buildingDetail,
      name: RouteNames.buildingDetail,
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => BuildingDetailPage(
        buildingId: state.pathParameters['id']!,
        building: state.extra as Building?,
      ),
    ),
    GoRoute(
      path: AppRoutes.navigate,
      name: RouteNames.navigate,
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => NavigationPage(
        buildingId: state.pathParameters['id']!,
        building: state.extra as Building?,
        destinationRoomId: state.uri.queryParameters['room'],
      ),
    ),
    GoRoute(
      path: AppRoutes.capture,
      name: RouteNames.capture,
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => CapturePage(
        buildingId: state.pathParameters['id']!,
      ),
    ),
    GoRoute(
      path: AppRoutes.mapBuilding,
      name: RouteNames.mapBuilding,
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const MapBuildingPage(),
    ),
    GoRoute(
      path: AppRoutes.planTrace,
      name: RouteNames.planTrace,
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => PlanTracePage(
        buildingId: state.pathParameters['id']!,
        // Which floor the trace starts on. Changeable on the screen itself,
        // since one plan can span a building.
        floorId: state.extra as String? ?? 'floor-g',
      ),
    ),
    GoRoute(
      path: AppRoutes.guidance,
      name: RouteNames.guidance,
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) {
        // The route to walk is handed over whole rather than re-fetched: the
        // map screen has already merged the graph and planned the path, and
        // repeating that here would be a second chance to disagree with it.
        final session = state.extra as GuidanceSession?;
        if (session == null) return const _MissingRoute();
        return GuidancePage(session: session);
      },
    ),
    GoRoute(
      path: AppRoutes.strideCalibration,
      name: RouteNames.strideCalibration,
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const StrideCalibrationPage(),
    ),
  ],
);

/// Guidance opened without a route — a deep link, or a restored stack. Says so
/// rather than crashing on a null cast.
class _MissingRoute extends StatelessWidget {
  const _MissingRoute();

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Pick a destination on the building map to start guidance.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
        ),
      );
}

String? _redirect(BuildContext context, GoRouterState state) {
  final settings = getIt<SettingsRepository>();
  final authenticated = getIt<AuthBloc>().state is AuthAuthenticated;
  final location = state.matchedLocation;
  final onGuestPath = _guestPaths.contains(location);

  if (!settings.onboardingSeen) {
    return location == AppRoutes.onboarding ? null : AppRoutes.onboarding;
  }
  if (!authenticated) {
    // Allow movement within the auth pages; kick everything else to welcome.
    if (onGuestPath && location != AppRoutes.onboarding) return null;
    return AppRoutes.welcome;
  }
  if (onGuestPath) return AppRoutes.home;
  return null;
}

/// Re-runs the redirect whenever a stream (the AuthBloc's) emits.
class _StreamListenable extends ChangeNotifier {
  _StreamListenable(Stream<dynamic> stream) {
    _subscription = stream.listen((_) => notifyListeners());
  }

  late final StreamSubscription<dynamic> _subscription;

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    super.dispose();
  }
}
