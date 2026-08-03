import 'package:equatable/equatable.dart';

/// Why no acoustic range was produced.
///
/// Named causes rather than a bare null because the fusion layer must treat
/// them differently: [noEcho] is evidence about the scene, [throttled] means
/// ask again shortly, and the rest are about the device.
enum RangeRefusal {
  /// The microphone or audio engine is not up.
  audioUnavailable,

  /// The speaker and mic were in use — speech, or a measurement already in
  /// flight.
  audioBusy,

  /// Asked again before the previous measurement had time to be useful. See
  /// [AcousticFallbackService.cooldown].
  throttled,

  /// The chirp went out and nothing came back above the noise floor. The
  /// honest reading of an open space, a heavily absorbing surface, or a
  /// target beyond usable range.
  noEcho,

  /// An echo was found, but too close to be distinguishable from the phone's
  /// own speaker ringing without a clutter profile. See
  /// [AcousticFallbackService.uncalibratedFloorMeters].
  belowUncalibratedFloor,
}

/// A distance measured by sound, for fusion with camera depth.
///
/// Carries its provenance in its type: a consumer holding one of these knows
/// the number came from a chirp and not from ARCore, which matters because the
/// two fail in unrelated ways — that non-overlap is the entire reason the
/// project pairs them.
class AcousticRange extends Equatable {
  const AcousticRange({
    required this.distanceMeters,
    required this.confidence,
    required this.capturedAt,
    required this.calibrated,
  });

  final double distanceMeters;

  /// 0..1, from how far the echo stood above the correlation noise floor.
  ///
  /// Deliberately blunt, like the room classifier's: it separates "a wall"
  /// from "possibly something", and is not a probability. A fusion rule
  /// should weight with it, not threshold hard on it.
  final double confidence;

  /// When the chirp was emitted — the field that lets this be paired with the
  /// camera depth frame it is meant to stand in for. The two sensors run on
  /// independent schedules, so without it there is no way to know which frame
  /// a range describes.
  final DateTime capturedAt;

  /// Whether a clutter profile was applied. Uncalibrated ranges are still
  /// usable, but only past [AcousticFallbackService.uncalibratedFloorMeters];
  /// a consumer that cares about near targets needs to know which it has.
  final bool calibrated;

  @override
  List<Object?> get props =>
      [distanceMeters, confidence, capturedAt, calibrated];

  @override
  String toString() => 'AcousticRange('
      '${distanceMeters.toStringAsFixed(2)}m '
      'confidence=${confidence.toStringAsFixed(2)} '
      '${calibrated ? "calibrated" : "uncalibrated"})';
}

/// The outcome of one fallback request: a range, or why not.
///
/// Exactly one of [range] and [refusal] is non-null.
class AcousticRangeResult extends Equatable {
  const AcousticRangeResult.measured(AcousticRange this.range) : refusal = null;

  const AcousticRangeResult.refused(RangeRefusal this.refusal) : range = null;

  final AcousticRange? range;
  final RangeRefusal? refusal;

  bool get succeeded => range != null;

  @override
  List<Object?> get props => [range, refusal];

  @override
  String toString() =>
      succeeded ? 'AcousticRangeResult($range)' : 'AcousticRangeResult(${refusal!.name})';
}
