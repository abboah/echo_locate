part of 'floor_map_bloc.dart';

sealed class FloorMapEvent extends Equatable {
  const FloorMapEvent();

  @override
  List<Object?> get props => [];
}

/// Load a building's landmarks and recorded walks and merge them into a map.
final class FloorMapRequested extends FloorMapEvent {
  const FloorMapRequested(this.buildingId);

  final String buildingId;

  @override
  List<Object?> get props => [buildingId];
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
