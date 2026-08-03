import 'package:equatable/equatable.dart';

import 'reverb_features.dart';

/// The space types the acoustic classifier distinguishes, per the build
/// plan's M5 scope.
enum RoomType {
  /// Long, narrow, hard parallel surfaces. Acoustically distinctive less for
  /// how long it rings than for ringing unevenly — see
  /// [RoomClassifier.maxDiffuseRatio].
  corridor,

  /// Office, classroom, small lab. Furnishings absorb quickly.
  smallRoom,

  /// Lecture theatre, atrium, stairwell. Large volume, long decay.
  hall,

  /// Not determinable — the measurement was unreliable, or the features fell
  /// between classes. Reported rather than forced into a class, because a
  /// confidently wrong room label is worse than none.
  unknown,
}

/// A room type, how strongly the evidence supports it, and the measurement it
/// came from.
class RoomClassification extends Equatable {
  const RoomClassification({
    required this.type,
    required this.confidence,
    required this.features,
    required this.reason,
  });

  final RoomType type;

  /// 0 to 1. How far the features sat from the nearest class boundary,
  /// normalised — a measurement deep inside a class scores high, one just
  /// over a threshold scores low.
  final double confidence;

  /// The acoustics this conclusion was drawn from. Kept so the UI, the logs
  /// and the evaluation chapter can all show the evidence, not just the
  /// verdict.
  final ReverbFeatures? features;

  /// Short human-readable justification, for logs and for explaining the
  /// classifier in a viva.
  final String reason;

  @override
  List<Object?> get props => [type, confidence, features, reason];

  @override
  String toString() => 'RoomClassification(${type.name} '
      'confidence=${confidence.toStringAsFixed(2)} :: $reason)';
}
