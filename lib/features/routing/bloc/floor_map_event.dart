part of 'floor_map_bloc.dart';

sealed class FloorMapEvent extends Equatable {
  const FloorMapEvent();

  @override
  List<Object?> get props => [];
}

/// Load a building's landmarks and recorded walks and merge them into a map.
final class FloorMapRequested extends FloorMapEvent {
  const FloorMapRequested(this.buildingId, {this.destinationRoomId});

  final String buildingId;

  /// Preselects the destination, for arriving from a room tile on the building
  /// screen rather than through the pickers. Null when the user opened the map
  /// to browse, in which case they choose both ends themselves.
  final String? destinationRoomId;

  @override
  List<Object?> get props => [buildingId, destinationRoomId];
}

/// Where the walk starts. Defaults to the first contributor's starting point.
final class FloorMapFromSelected extends FloorMapEvent {
  const FloorMapFromSelected(this.landmarkId);

  final String landmarkId;

  @override
  List<Object?> get props => [landmarkId];
}

/// Where the walk ends. Setting both ends runs A* over the merged graph.
final class FloorMapToSelected extends FloorMapEvent {
  const FloorMapToSelected(this.landmarkId);

  final String landmarkId;

  @override
  List<Object?> get props => [landmarkId];
}

/// Draw a different floor.
///
/// Only the picture changes — the graph spans every floor and A* routes across
/// them, so switching planes never alters the plan being shown.
final class FloorMapFloorSelected extends FloorMapEvent {
  const FloorMapFloorSelected(this.floorId);

  final String floorId;

  @override
  List<Object?> get props => [floorId];
}
