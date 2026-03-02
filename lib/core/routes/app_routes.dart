import 'package:go_router/go_router.dart';

import '../../features/home/presentation/home_screen.dart';
import '../../features/measurement/presentation/measurement_screen.dart';
import '../../features/floorplan/presentation/floorplan_screen.dart';

/// Application route paths
class AppRoutes {
  AppRoutes._();

  static const String home = '/';
  static const String measure = '/measure';
  static const String floorplan = '/floorplan';
}

/// GoRouter configuration for the application
final GoRouter appRouter = GoRouter(
  initialLocation: AppRoutes.home,
  routes: [
    GoRoute(
      path: AppRoutes.home,
      builder: (context, state) => const HomeScreen(),
    ),
    GoRoute(
      path: AppRoutes.measure,
      builder: (context, state) => const MeasurementScreen(),
    ),
    GoRoute(
      path: AppRoutes.floorplan,
      builder: (context, state) => const FloorPlanScreen(),
    ),
  ],
);
