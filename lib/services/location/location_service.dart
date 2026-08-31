import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/utils/logger.dart';

/// Where the user is, and what that place is called.
///
/// Two callers, both of which had been faking it. Explore sorts buildings by
/// distance through `nearby_buildings(p_lat, p_lng, …)`, which has accepted a
/// position since the first migration and never received one — so every
/// distance in the app was measured from the server's default origin, the same
/// for everybody. And Home's header read `KNUST, Kumasi` as a literal, on every
/// phone, wherever it was.
///
/// **Nothing here is required for the app to work.** A refused permission, a
/// disabled location service, a phone with no fix: every method returns null
/// and the callers fall back to what they did before. Indoor navigation is the
/// point of this app and GPS stops at the front door — location is here to
/// order a list and name a place, and neither is worth an error dialog.
class LocationService {
  LocationService();

  /// Cached so the header and the building list agree, and so a cold Explore
  /// does not wait on a fresh fix it does not need.
  UserLocation? _last;

  /// The last position this session, if there is one.
  UserLocation? get lastKnown => _last;

  /// Whether the user has already granted location.
  ///
  /// Distinct from asking: this is what lets a screen decide whether to show
  /// the primer without triggering the system dialog as a side effect.
  Future<bool> get isGranted async {
    try {
      final permission = await Geolocator.checkPermission();
      return permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse;
    } catch (_) {
      return false;
    }
  }

  /// Asks for location, returning whether it was granted.
  ///
  /// The primer screen calls this. Before, that screen's "Allow while using
  /// app" button and its "Don't allow" button ran identical code — it set a
  /// flag saying the primer had been seen and never asked Android anything, so
  /// the permission was never granted however many times somebody allowed it.
  Future<bool> request() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return false;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      return permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse;
    } catch (error, stack) {
      AppLogger.error('Location permission request failed', error, stack);
      return false;
    }
  }

  /// The current position, or null when it cannot be had.
  ///
  /// Never prompts. A screen that wants the dialog calls [request] first —
  /// otherwise opening Explore would throw a system permission sheet over a
  /// list the user is already reading.
  Future<UserLocation?> current({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    try {
      if (!await isGranted) return null;
      if (!await Geolocator.isLocationServiceEnabled()) return null;

      final position = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          // Kilometres is the unit every consumer of this works in, so metre
          // accuracy would cost battery to answer a question nobody asked.
          accuracy: LocationAccuracy.low,
          timeLimit: timeout,
        ),
      );
      final location = UserLocation(
        latitude: position.latitude,
        longitude: position.longitude,
      );
      _last = location;
      return location;
    } catch (error, stack) {
      // A timeout indoors is the normal case for this app, not an incident.
      AppLogger.warn('No position available: $error');
      AppLogger.debug('$stack');
      return null;
    }
  }

  /// A human place name for [location] — "Kumasi, Ashanti" — or null.
  ///
  /// Reverse geocoding is a platform call that needs a network on Android, so
  /// this is the first thing to fail on a campus connection. It failing means
  /// the header keeps whatever it had, which is why nothing here throws.
  Future<String?> placeName(UserLocation location) async {
    try {
      final places = await placemarkFromCoordinates(
        location.latitude,
        location.longitude,
      );
      if (places.isEmpty) return null;
      final place = places.first;
      // Most specific first, and only two parts: this sits above "Where to?"
      // in a header, not on a map pin.
      final parts = <String>[
        for (final part in [
          place.subLocality,
          place.locality,
          place.administrativeArea,
        ])
          if (part != null && part.trim().isNotEmpty) part.trim(),
      ];
      if (parts.isEmpty) return place.country?.trim();
      return parts.take(2).join(', ');
    } catch (error) {
      AppLogger.warn('Could not name this place: $error');
      return null;
    }
  }
}

/// A position, as everything above the service layer wants it.
///
/// Its own type rather than geolocator's `Position`, so the package stays
/// behind this file: blocs and repositories take two doubles, and can be
/// tested with a literal instead of a mocked plugin.
class UserLocation {
  const UserLocation({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;

  @override
  bool operator ==(Object other) =>
      other is UserLocation &&
      other.latitude == latitude &&
      other.longitude == longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);

  @override
  String toString() =>
      'UserLocation(${latitude.toStringAsFixed(5)}, '
      '${longitude.toStringAsFixed(5)})';
}
