import 'package:equatable/equatable.dart';

/// Where a [StrideProfile] came from, worst last. Kept because guidance says
/// different things depending on how much it trusts the number — an assumed
/// stride is a reason to lean on landmarks rather than step counts.
enum StrideSource {
  /// The user walked a measured distance and the counter counted.
  calibrated,

  /// Estimated from the user's height.
  height,

  /// Neither given, or a stored value that could not be believed.
  assumed,
}

/// How far this user travels per step, and how much that figure is trusted.
///
/// Named "stride" to match the spec and the `profiles.stride_length_m` column,
/// but this is **step length** — one footfall to the next — not the clinical
/// stride of two steps. It is the number `distanceM / stride` needs, and
/// mixing the two would halve every count guidance speaks.
///
/// Routes store metres, never steps: a contributor with a 78cm step and a user
/// with a 65cm step do not share a count (spec §4). This class is the only
/// place that converts between them.
class StrideProfile extends Equatable {
  const StrideProfile({required this.metres, required this.source});

  final double metres;
  final StrideSource source;

  /// Ratio of step length to height, the standard anthropometric estimate.
  static const double heightFactor = 0.415;

  /// Used when the user offers neither a calibration walk nor a height —
  /// roughly the step of a 1.7m adult.
  static const StrideProfile fallback =
      StrideProfile(metres: 0.7055, source: StrideSource.assumed);

  /// Plausible human step length. Wide enough to cover a short child and a
  /// tall adult striding out, tight enough that a miscount cannot get through:
  /// the failure being guarded against is a counter that missed most steps,
  /// which produces metres-per-step, not centimetres.
  static const double minMetres = 0.30;
  static const double maxMetres = 1.20;

  /// From a walk over a known distance: `stride = distance / steps`.
  factory StrideProfile.fromWalk({
    required double distanceM,
    required int steps,
  }) {
    if (steps <= 0 || distanceM <= 0) {
      // Not a measurement. Carries the implausible value through rather than
      // silently substituting a default, so callers can tell the user the
      // calibration failed instead of pretending it worked.
      return const StrideProfile(metres: 0, source: StrideSource.calibrated);
    }
    return StrideProfile(
      metres: distanceM / steps,
      source: StrideSource.calibrated,
    );
  }

  factory StrideProfile.fromHeight(double heightM) => StrideProfile(
        metres: heightM * heightFactor,
        source: StrideSource.height,
      );

  /// Whether this figure is worth guiding with. Checked before storing and
  /// again after restoring — the same discipline as [SonarLatencyProfile].
  bool get isPlausible => metres >= minMetres && metres <= maxMetres;

  /// How many steps *this* user should expect over [distanceM].
  int stepsFor(double distanceM) =>
      metres <= 0 ? 0 : (distanceM / metres).round();

  /// How far this user has travelled in [steps].
  double distanceFor(int steps) => steps * metres;

  Map<String, dynamic> toJson() => {
        'metres': metres,
        'source': source.name,
      };

  /// Restores a stored profile, or null when it is malformed or no longer
  /// believable. A bad stored stride is worse than none: it silently
  /// mis-scales every leg of every route.
  static StrideProfile? fromJson(Object? value) {
    if (value is! Map) return null;
    final metres = value['metres'];
    if (metres is! num) return null;

    // An unrecognised source is not a reason to discard a good measurement —
    // only the number actually guides anyone.
    final source = StrideSource.values.asNameMap()[value['source']] ??
        StrideSource.assumed;

    final profile =
        StrideProfile(metres: metres.toDouble(), source: source);
    return profile.isPlausible ? profile : null;
  }

  @override
  String toString() =>
      '${metres.toStringAsFixed(3)}m/step (${source.name})';

  @override
  List<Object?> get props => [metres, source];
}
