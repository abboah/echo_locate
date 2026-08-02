part of 'building_detail_bloc.dart';

sealed class BuildingDetailEvent extends Equatable {
  const BuildingDetailEvent();

  @override
  List<Object?> get props => [];
}

final class BuildingDetailStarted extends BuildingDetailEvent {
  const BuildingDetailStarted({required this.buildingId, this.building});

  final String buildingId;
  final Building? building;

  @override
  List<Object?> get props => [buildingId, building];
}

/// Save/unsave this building for offline use (the bookmark button).
final class BuildingDetailSaveToggled extends BuildingDetailEvent {
  const BuildingDetailSaveToggled();
}

final class BuildingDetailFloorSelected extends BuildingDetailEvent {
  const BuildingDetailFloorSelected(this.index);

  final int index;

  @override
  List<Object?> get props => [index];
}
