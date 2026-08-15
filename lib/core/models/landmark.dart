import 'package:freezed_annotation/freezed_annotation.dart';

part 'landmark.freezed.dart';
part 'landmark.g.dart';

/// What kind of place a landmark marks. Drives the map glyph and the phrasing
/// of spoken guidance ("take the stairs" vs "go through the door").
enum LandmarkKind {
  entrance,
  junction,
  stairs,
  lift,
  door,
  sign;

  static LandmarkKind fromName(String? value) => LandmarkKind.values.firstWhere(
    (k) => k.name == value,
    orElse: () => LandmarkKind.sign,
  );

  /// Legs into stairs and lifts cannot be step-counted — the pedometer does
  /// not measure climbing — so guidance falls back to landmark-only for them.
  bool get breaksStepCounting =>
      this == LandmarkKind.stairs || this == LandmarkKind.lift;
}

/// A fixed point in a building that the camera can recognise, because it has
/// readable signage: a door plate, a floor number, a directory board.
///
/// Landmarks are the app's positioning system. Rather than tracking where the
/// phone is, guidance waits until OCR reads [labelText] and treats that as
/// arrival — which is why step-count error never accumulates across a route.
@freezed
abstract class Landmark with _$Landmark {
  const factory Landmark({
    required String id,
    required String buildingId,
    required String floorId,
    required LandmarkKind kind,

    /// Normalised text OCR must match, e.g. `'204'`. Compared case- and
    /// whitespace-insensitively, with a Levenshtein tolerance of 1.
    required String labelText,

    /// Human-facing name, e.g. `'Reading Hall door'`. Spoken on arrival.
    required String displayName,

    /// Systematic misreads seen in the field (`'2O4'`, `'2 04'`). The fuzzy
    /// matcher covers single-character slips; this is for the rest.
    @Default(<String>[]) List<String> aliases,

    /// Set when this landmark is a room's door — how a route ends.
    String? roomId,
  }) = _Landmark;

  const Landmark._();

  factory Landmark.fromJson(Map<String, dynamic> json) =>
      _$LandmarkFromJson(json);

  /// Whether an OCR read denotes this landmark. Exact and alias matches only;
  /// fuzzy tolerance lives in the matcher so it can be tuned in one place.
  bool matchesExactly(String read) {
    final normalised = normalise(read);
    return normalised == normalise(labelText) ||
        aliases.any((a) => normalise(a) == normalised);
  }

  /// Upper-case, single-spaced, trimmed — the form stored in `label_text`.
  static String normalise(String value) =>
      value.toUpperCase().replaceAll(RegExp(r'\s+'), ' ').trim();
}
