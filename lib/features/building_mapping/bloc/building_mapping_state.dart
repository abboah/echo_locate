part of 'building_mapping_cubit.dart';

enum BuildingMappingStatus { loading, ready, failed }

class BuildingMappingState extends Equatable {
  const BuildingMappingState({
    this.status = BuildingMappingStatus.loading,
    this.buildingId = '',
    this.building,
    this.saved = false,
    this.progress = const BuildingMappingProgress([]),
    this.error,
  });

  final BuildingMappingStatus status;
  final String buildingId;

  /// The index row, for the header. Null when the index could not be reached —
  /// the floors are still listed, named from whatever the screen was opened
  /// with, because a traced floor does not stop existing when the network does.
  final Building? building;

  /// Kept for offline use (a row in `saved_maps`); surfaced under Explore's
  /// "Saved" chip.
  final bool saved;

  final BuildingMappingProgress progress;

  final String? error;

  List<FloorMappingStatus> get floors => progress.floors;

  /// The floor to point somebody at, or null when there is nothing left.
  FloorMappingStatus? get nextFloor => progress.nextFloor;

  bool get isComplete => progress.isComplete;

  /// Whether any floor here can be walked — what decides whether this screen
  /// is a map to follow or a job to start.
  bool get hasWalkableFloor => floors.any((floor) => floor.stage.isNavigable);

  BuildingMappingState copyWith({
    BuildingMappingStatus? status,
    String? buildingId,
    Building? building,
    bool? saved,
    BuildingMappingProgress? progress,
    String? error,
  }) => BuildingMappingState(
    status: status ?? this.status,
    buildingId: buildingId ?? this.buildingId,
    building: building ?? this.building,
    saved: saved ?? this.saved,
    progress: progress ?? this.progress,
    // Not sticky: an error from a failed load must not outlive the reload
    // that worked.
    error: error,
  );

  @override
  List<Object?> get props => [
    status,
    buildingId,
    building,
    saved,
    // Compared by the floors themselves — BuildingMappingProgress is a
    // plain holder, and a new instance with the same floors is not a
    // change worth rebuilding for.
    [for (final floor in floors) (floor.floor.id, floor.stage)],
    error,
  ];
}
