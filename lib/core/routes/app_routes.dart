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
  static const String sonar = '/sonar';
  static const String acoustic = '/acoustic';
  static const String depthProbe = '/depth-probe';
  static const String roomPlanProbe = '/room-plan-probe';
  static const String cameraPrimer = '/camera-primer';
  static const String locationPrimer = '/location-primer';
  static const String buildingDetail = '/building/:id';
  static const String navigate = '/building/:id/navigate';


  /// Mapping a building by tracing the floor plan posted on its wall
  /// (contributor). Takes the floor id as `extra`.
  static const String planTrace = '/building/:id/trace';
  static const String roomTrace = '/building/:id/trace-rooms';
  static const String planEditor = '/building/:id/edit-plan';

  /// Mapping a building floor by floor — the hub the capture screens hang off.
  static const String buildingMapping = '/building/:id/map';

  /// Walking a mapped floor. Takes the floor id as `extra`.
  static const String roomNavigate = '/building/:id/walk';

  /// Choosing what to map — a building nobody has listed, or one that is.
  static const String mapBuilding = '/map-building';

  /// Following a route by voice. Takes a GuidanceSession as `extra`.
  static const String guidance = '/guidance';

  /// Measuring the user's step length, so stored metres convert to their
  /// steps rather than the contributor's.
  static const String strideCalibration = '/stride-calibration';
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
  static const String sonar = 'sonar';
  static const String acoustic = 'acoustic';
  static const String depthProbe = 'depthProbe';
  static const String roomPlanProbe = 'roomPlanProbe';
  static const String cameraPrimer = 'cameraPrimer';
  static const String locationPrimer = 'locationPrimer';
  static const String buildingDetail = 'buildingDetail';
  static const String navigate = 'navigate';
  static const String planTrace = 'planTrace';
  static const String roomTrace = 'roomTrace';
  static const String planEditor = 'planEditor';
  static const String buildingMapping = 'buildingMapping';
  static const String roomNavigate = 'roomNavigate';
  static const String mapBuilding = 'mapBuilding';
  static const String guidance = 'guidance';
  static const String strideCalibration = 'strideCalibration';
}
