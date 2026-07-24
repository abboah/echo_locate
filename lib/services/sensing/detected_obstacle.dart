import 'package:equatable/equatable.dart';

/// Where an obstacle sits horizontally in the camera frame.
enum ObstaclePosition { left, center, right }

/// One object found in a camera frame, normalized so the callout policy
/// doesn't care about camera resolution or rotation.
class DetectedObstacle extends Equatable {
  const DetectedObstacle({
    required this.label,
    required this.confidence,
    required this.heightFraction,
    required this.position,
  });

  /// Human word for the thing ('chair', 'plant', 'obstacle' when unknown).
  final String label;

  /// Classifier confidence 0–1 (0 when the detector found a shape it
  /// couldn't classify — still an obstacle worth announcing).
  final double confidence;

  /// Bounding-box height / frame height. Our proximity proxy: things that
  /// fill the frame are close.
  final double heightFraction;

  final ObstaclePosition position;

  @override
  List<Object?> get props => [label, confidence, heightFraction, position];
}
