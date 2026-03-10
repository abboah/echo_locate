import 'package:equatable/equatable.dart';
import 'package:echo_locate/shared/models/measurement_point.dart';

/// Represents a floor plan with measurement points and metadata
class FloorPlan extends Equatable {
  final String id;
  final String name;
  final String? description;
  final List<FloorPlanPoint> points;
  final DateTime createdAt;
  final DateTime updatedAt;
  final FloorPlanMetadata metadata;

  const FloorPlan({
    required this.id,
    required this.name,
    this.description,
    required this.points,
    required this.createdAt,
    required this.updatedAt,
    required this.metadata,
  });

  @override
  List<Object?> get props => [
    id,
    name,
    description,
    points,
    createdAt,
    updatedAt,
    metadata,
  ];

  /// Create a new floor plan from measurements
  factory FloorPlan.fromMeasurements({
    required String name,
    String? description,
    required List<MeasurementPoint> measurements,
  }) {
    final now = DateTime.now();
    final points = measurements
        .map((m) => FloorPlanPoint.fromMeasurement(m))
        .toList();

    return FloorPlan(
      id: _generateId(),
      name: name,
      description: description,
      points: points,
      createdAt: now,
      updatedAt: now,
      metadata: FloorPlanMetadata(
        totalPoints: points.length,
        areaEstimate: _estimateArea(points),
        measurementDate: now,
      ),
    );
  }

  /// Add a point to the floor plan
  FloorPlan addPoint(FloorPlanPoint point) {
    return copyWith(
      points: [...points, point],
      updatedAt: DateTime.now(),
      metadata: metadata.copyWith(totalPoints: points.length + 1),
    );
  }

  /// Create a copy with updated fields
  FloorPlan copyWith({
    String? id,
    String? name,
    String? description,
    List<FloorPlanPoint>? points,
    DateTime? createdAt,
    DateTime? updatedAt,
    FloorPlanMetadata? metadata,
  }) {
    return FloorPlan(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      points: points ?? this.points,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      metadata: metadata ?? this.metadata,
    );
  }

  static String _generateId() {
    return DateTime.now().millisecondsSinceEpoch.toString();
  }

  static double _estimateArea(List<FloorPlanPoint> points) {
    if (points.length < 3) return 0.0;

    // Simple convex hull area estimation
    // In a real implementation, this would use more sophisticated algorithms
    double minX = double.infinity;
    double maxX = double.negativeInfinity;
    double minY = double.infinity;
    double maxY = double.negativeInfinity;

    for (final point in points) {
      minX = minX < point.x ? minX : point.x;
      maxX = maxX > point.x ? maxX : point.x;
      minY = minY < point.y ? minY : point.y;
      maxY = maxY > point.y ? maxY : point.y;
    }

    return (maxX - minX) * (maxY - minY);
  }
}

/// Represents a point in the floor plan with measurement data
class FloorPlanPoint extends Equatable {
  final String id;
  final double x;
  final double y;
  final double? distance;
  final double? angle;
  final double? signalStrength;
  final DateTime measuredAt;
  final PointType type;

  const FloorPlanPoint({
    required this.id,
    required this.x,
    required this.y,
    this.distance,
    this.angle,
    this.signalStrength,
    required this.measuredAt,
    this.type = PointType.measurement,
  });

  @override
  List<Object?> get props => [
    id,
    x,
    y,
    distance,
    angle,
    signalStrength,
    measuredAt,
    type,
  ];

  /// Create from a measurement point
  factory FloorPlanPoint.fromMeasurement(MeasurementPoint measurement) {
    return FloorPlanPoint(
      id: measurement.timestamp.millisecondsSinceEpoch.toString(),
      x: measurement.x,
      y: measurement.y,
      distance: measurement.distance,
      angle: measurement.angle,
      signalStrength: measurement.signalStrength,
      measuredAt: measurement.timestamp,
      type: PointType.measurement,
    );
  }

  /// Create a reference point (corner, door, etc.)
  factory FloorPlanPoint.reference({
    required double x,
    required double y,
    required PointType type,
    String? label,
  }) {
    return FloorPlanPoint(
      id: '${type.name}_${DateTime.now().millisecondsSinceEpoch}',
      x: x,
      y: y,
      measuredAt: DateTime.now(),
      type: type,
    );
  }
}

/// Types of points in a floor plan
enum PointType {
  measurement, // Regular distance measurement
  reference, // Known reference point (corner, door, etc.)
  wall, // Wall boundary point
  obstacle, // Furniture or obstacle
}

/// Metadata for a floor plan
class FloorPlanMetadata extends Equatable {
  final int totalPoints;
  final double areaEstimate; // in square meters
  final DateTime measurementDate;
  final Duration? scanDuration;
  final String? deviceInfo;

  const FloorPlanMetadata({
    required this.totalPoints,
    required this.areaEstimate,
    required this.measurementDate,
    this.scanDuration,
    this.deviceInfo,
  });

  @override
  List<Object?> get props => [
    totalPoints,
    areaEstimate,
    measurementDate,
    scanDuration,
    deviceInfo,
  ];

  FloorPlanMetadata copyWith({
    int? totalPoints,
    double? areaEstimate,
    DateTime? measurementDate,
    Duration? scanDuration,
    String? deviceInfo,
  }) {
    return FloorPlanMetadata(
      totalPoints: totalPoints ?? this.totalPoints,
      areaEstimate: areaEstimate ?? this.areaEstimate,
      measurementDate: measurementDate ?? this.measurementDate,
      scanDuration: scanDuration ?? this.scanDuration,
      deviceInfo: deviceInfo ?? this.deviceInfo,
    );
  }
}
