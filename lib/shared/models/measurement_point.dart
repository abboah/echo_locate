import 'package:equatable/equatable.dart';

/// Represents a measurement point with position and signal data
class MeasurementPoint extends Equatable {
  final double x; // X coordinate in meters
  final double y; // Y coordinate in meters
  final double distance; // Distance in meters
  final double angle; // Angle in degrees
  final double signalStrength; // 0.0 to 1.0
  final DateTime timestamp;

  const MeasurementPoint({
    required this.x,
    required this.y,
    required this.distance,
    required this.angle,
    required this.signalStrength,
    required this.timestamp,
  });

  @override
  List<Object?> get props => [x, y, distance, angle, signalStrength, timestamp];

  /// Create from polar coordinates (distance and angle)
  factory MeasurementPoint.fromPolar({
    required double distance,
    required double angle,
    required double signalStrength,
  }) {
    // Placeholder calculation - needs device orientation integration
    return MeasurementPoint(
      x: distance, // Placeholder - needs device orientation
      y: distance, // Placeholder - needs device orientation
      distance: distance,
      angle: angle,
      signalStrength: signalStrength,
      timestamp: DateTime.now(),
    );
  }
}
