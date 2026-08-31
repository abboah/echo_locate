part of 'building_mapping_cubit.dart';

enum BuildingMappingStatus { loading, ready, failed }

class BuildingMappingState extends Equatable {
  const BuildingMappingState({
    this.status = BuildingMappingStatus.loading,
    this.buildingId = '',
    this.progress = const BuildingMappingProgress([]),
    this.error,
  });

  final BuildingMappingStatus status;
  final String buildingId;
  final BuildingMappingProgress progress;

  /// Whether this phone can capture in AR.
  ///
  /// Decided once, up front, so the floor list offers the methods that will
  /// actually work rather than sending somebody to a corridor to find out.

  final String? error;

  List<FloorMappingStatus> get floors => progress.floors;

  /// The floor to point somebody at, or null when there is nothing left.
  FloorMappingStatus? get nextFloor => progress.nextFloor;

  bool get isComplete => progress.isComplete;

  BuildingMappingState copyWith({
    BuildingMappingStatus? status,
    String? buildingId,
    BuildingMappingProgress? progress,
    String? error,
  }) => BuildingMappingState(
    status: status ?? this.status,
    buildingId: buildingId ?? this.buildingId,
    progress: progress ?? this.progress,
    // Not sticky: an error from a failed load must not outlive the reload
    // that worked.
    error: error,
  );

  @override
  List<Object?> get props => [
    status,
    buildingId,
    // Compared by the floors themselves — BuildingMappingProgress is a
    // plain holder, and a new instance with the same floors is not a
    // change worth rebuilding for.
    [for (final floor in floors) (floor.floor.id, floor.stage)],
    error,
  ];
}
