/// Named route paths. Use these constants only — never raw path strings.
///
/// Dual routers (guest/user) arrive with auth in Phase 1; for now a single
/// router serves the foundation shell.
class AppRoutes {
  AppRoutes._();

  static const String home = '/';
  static const String explore = '/explore';
  static const String scan = '/scan';
  static const String maps = '/maps';
  static const String profile = '/profile';
}
