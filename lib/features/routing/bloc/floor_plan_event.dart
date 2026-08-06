part of 'floor_plan_bloc.dart';

sealed class FloorPlanEvent extends Equatable {
  const FloorPlanEvent();

  @override
  List<Object?> get props => [];
}

/// Loads a building's landmarks and routes and merges them into a plan.
final class FloorPlanStarted extends FloorPlanEvent {
  const FloorPlanStarted(this.buildingId, {this.destinationRoomId});

  final String buildingId;

  /// Opened straight from a room tile on the building detail screen, so the
  /// route is planned before the map is first drawn.
  final String? destinationRoomId;

  @override
  List<Object?> get props => [buildingId, destinationRoomId];
}

final class FloorPlanFloorSelected extends FloorPlanEvent {
  const FloorPlanFloorSelected(this.floorId);

  final String floorId;

  @override
  List<Object?> get props => [floorId];
}

/// Plans a route to a room, from the building entrance or from wherever
/// guidance says the user currently is.
final class FloorPlanDestinationSelected extends FloorPlanEvent {
  const FloorPlanDestinationSelected(this.roomId);

  final String roomId;

  @override
  List<Object?> get props => [roomId];
}

/// The user has reached a landmark — an OCR confirmation from Stream B's
/// guidance, or a contributor tapping a node to say "I am here".
///
/// The map follows them: the active floor changes when they climb, and any
/// route planned afterwards starts from where they now are rather than from
/// the front door.
final class FloorPlanPositionChanged extends FloorPlanEvent {
  const FloorPlanPositionChanged(this.landmarkId);

  final String landmarkId;

  @override
  List<Object?> get props => [landmarkId];
}

final class FloorPlanRouteCleared extends FloorPlanEvent {
  const FloorPlanRouteCleared();
}
