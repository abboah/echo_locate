part of 'building_detail_bloc.dart';

enum BuildingDetailStatus { initial, loading, success, failure }

final class BuildingDetailState extends Equatable {
  const BuildingDetailState({
    this.status = BuildingDetailStatus.initial,
    this.building,
    this.floors = const [],
    this.selectedFloor = 0,
    this.saved = false,
    this.error,
  });

  final BuildingDetailStatus status;
  final Building? building;
  final List<BuildingFloor> floors;
  final int selectedFloor;

  /// Kept for offline use (a row in `saved_maps`); shown on the Maps tab.
  final bool saved;
  final String? error;

  List<Room> get roomsOnSelectedFloor =>
      selectedFloor < floors.length ? floors[selectedFloor].rooms : const [];

  BuildingDetailState copyWith({
    BuildingDetailStatus? status,
    Building? building,
    List<BuildingFloor>? floors,
    int? selectedFloor,
    bool? saved,
    String? error,
  }) {
    return BuildingDetailState(
      status: status ?? this.status,
      building: building ?? this.building,
      floors: floors ?? this.floors,
      selectedFloor: selectedFloor ?? this.selectedFloor,
      saved: saved ?? this.saved,
      error: error ?? this.error,
    );
  }

  @override
  List<Object?> get props =>
      [status, building, floors, selectedFloor, saved, error];
}
