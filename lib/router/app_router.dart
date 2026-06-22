import 'package:go_router/go_router.dart';

import '../core/routes/app_routes.dart';
import '../ui/pages/foundation/foundation_home_page.dart';

/// App router. Single router for the foundation shell; will split into
/// guest/user routers once auth lands.
final GoRouter appRouter = GoRouter(
  initialLocation: AppRoutes.home,
  routes: [
    GoRoute(
      path: AppRoutes.home,
      builder: (context, state) => const FoundationHomePage(),
    ),
  ],
);
