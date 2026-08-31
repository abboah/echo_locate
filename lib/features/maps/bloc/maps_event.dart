part of 'maps_bloc.dart';

sealed class MapsEvent extends Equatable {
  const MapsEvent();

  @override
  List<Object?> get props => [];
}

final class MapsStarted extends MapsEvent {
  const MapsStarted();
}

/// Remove a traced floor from this device.
///
/// Twenty minutes of somebody's work, so the screen confirms first and this
/// event is only raised once they have said yes.
final class MapsFloorDeleted extends MapsEvent {
  const MapsFloorDeleted({required this.buildingId, required this.floorId});

  final String buildingId;
  final String floorId;

  @override
  List<Object?> get props => [buildingId, floorId];
}
