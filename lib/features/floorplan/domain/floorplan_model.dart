import 'package:equatable/equatable.dart';

/// Represents a floor plan with measurement points
class FloorPlanModel extends Equatable {
  final String id;
  final String name;
  final List<FloorPlanPoint> points;
  final DateTime createdAt;

  const FloorPlanModel({
    required this.id,
    required this.name,
    required this.points,
    required this.createdAt,
  });

  @override
  List<Object?> get props => [id, name, points, createdAt];
}

/// Represents a point in the floor plan
class FloorPlanPoint extends Equatable {
  final double x;
  final double y;
  final double? distance;
  final double? angle;

  const FloorPlanPoint({
    required this.x,
    required this.y,
    this.distance,
    this.angle,
  });

  @override
  List<Object?> get props => [x, y, distance, angle];
}
