/// Route paths + names. Use these constants only — never raw strings.
///
/// Guest tree (onboarding/auth) and user tree (shell + detail flows) are
/// swapped by the router redirect based on [AuthBloc] state.
class AppRoutes {
  AppRoutes._();

  // Guest
  static const String onboarding = '/onboarding';
  static const String welcome = '/welcome';
  static const String signIn = '/sign-in';
  static const String signUp = '/sign-up';

  // User — shell tabs
  static const String home = '/';
  static const String explore = '/explore';
  static const String maps = '/maps';
  static const String profile = '/profile';

  // User — full-screen flows (pushed above the shell)
  static const String assist = '/assist';
  static const String scan = '/scan';
  static const String sonar = '/sonar';
  static const String acoustic = '/acoustic';
  static const String depthProbe = '/depth-probe';
  static const String cameraPrimer = '/camera-primer';
  static const String locationPrimer = '/location-primer';
  static const String buildingDetail = '/building/:id';
  static const String navigate = '/building/:id/navigate';
}

/// go_router route names (for pushNamed/goNamed).
class RouteNames {
  RouteNames._();

  static const String onboarding = 'onboarding';
  static const String welcome = 'welcome';
  static const String signIn = 'signIn';
  static const String signUp = 'signUp';

  static const String home = 'home';
  static const String explore = 'explore';
  static const String maps = 'maps';
  static const String profile = 'profile';

  static const String assist = 'assist';
  static const String scan = 'scan';
  static const String sonar = 'sonar';
  static const String acoustic = 'acoustic';
  static const String depthProbe = 'depthProbe';
  static const String cameraPrimer = 'cameraPrimer';
  static const String locationPrimer = 'locationPrimer';
  static const String buildingDetail = 'buildingDetail';
  static const String navigate = 'navigate';
}
