import 'package:equatable/equatable.dart';

/// Represents a single measurement point in acoustic sonar
class MeasurementModel extends Equatable {
  final String id;
  final double distance; // in meters
  final double angle; // in degrees
  final double signalStrength; // 0.0 to 1.0
  final DateTime timestamp;

  const MeasurementModel({
    required this.id,
    required this.distance,
    required this.angle,
    required this.signalStrength,
    required this.timestamp,
  });

  @override
  List<Object?> get props => [id, distance, angle, signalStrength, timestamp];
}
