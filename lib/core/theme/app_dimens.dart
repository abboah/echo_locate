/// Spacing, radius, and elevation tokens for EchoLocate.
///
/// Derived from the Figma layouts: generous padding, ~16r rounded cards,
/// soft shadows. Use these instead of magic numbers in widgets.
class AppDimens {
  AppDimens._();

  // Spacing scale (4pt base)
  static const double space2 = 2;
  static const double space4 = 4;
  static const double space8 = 8;
  static const double space12 = 12;
  static const double space16 = 16;
  static const double space20 = 20;
  static const double space24 = 24;
  static const double space32 = 32;
  static const double space48 = 48;

  // Corner radii
  static const double radiusSm = 8;
  static const double radiusMd = 12;
  static const double radiusLg = 16; // default card radius
  static const double radiusXl = 24;
  static const double radiusPill = 999;

  // Standard page gutter
  static const double pageGutter = 22;

  // Elevation (soft shadows; no gradients)
  static const double cardElevation = 0; // we use subtle shadow, flat fills
}
