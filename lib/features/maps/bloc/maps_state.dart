part of 'maps_bloc.dart';

enum MapsStatus { initial, loading, success, failure }

/// One traced floor, ready to be listed and walked.
final class MappedFloor extends Equatable {
  const MappedFloor({required this.plan, this.storedLabel});

  final RoomPlan plan;

  /// The label the building index gives this floor, when the index could be
  /// reached. Null offline, or for a floor traced before it was listed.
  final String? storedLabel;

  /// What to call this floor on screen — the index's label where there is one,
  /// read off the floor id otherwise. See [floorLabelFromId].
  String get label {
    final stored = storedLabel?.trim();
    if (stored != null && stored.isNotEmpty) return stored;
    return floorLabelFromId(plan.floorId);
  }

  /// "Ground floor" / "Floor 2" — the label as a sentence, for the row title
  /// and for the screen reader.
  String get title => floorTitleFor(label);

  int get roomCount => plan.drawableRooms.length;

  /// How far along this floor is — the same derivation the contributor hub
  /// uses, so a floor cannot read "Ready" on one screen and "Needs doors" on
  /// the other. The floor is rebuilt from the plan because the index that
  /// would have supplied it may be unreachable, and none of the stage
  /// derivation looks at anything but the geometry.
  FloorMappingStatus get status => FloorMappingStatus.of(
    BuildingFloor(id: plan.floorId, label: label, rooms: const []),
    plan,
  );

  /// Whether tapping this row can lead anywhere.
  ///
  /// A floor with rooms and no doors is drawn correctly and routes nowhere, so
  /// it is listed — somebody has to be able to see it and go finish it — but
  /// it does not offer a walk it cannot deliver.
  bool get isWalkable => status.stage.isNavigable;

  /// Said on the row, because it changes what guidance can say out loud: a
  /// floor with no scale routes and speaks its turns, and cannot speak a
  /// distance or lay an arrow into the building.
  bool get hasScale => plan.isMetric;

  @override
  List<Object?> get props => [plan, storedLabel];
}

/// One building's traced floors.
final class MappedBuilding extends Equatable {
  const MappedBuilding({
    required this.id,
    required this.name,
    required this.floors,
    this.area,
  });

  final String id;

  /// The building's name, or its id when the index could not be reached.
  final String name;
  final String? area;
  final List<MappedFloor> floors;

  int get roomCount =>
      floors.fold(0, (total, floor) => total + floor.roomCount);

  bool get hasWalkableFloor => floors.any((floor) => floor.isWalkable);

  @override
  List<Object?> get props => [id, name, area, floors];
}

final class MapsState extends Equatable {
  const MapsState({
    this.status = MapsStatus.initial,
    this.buildings = const [],
    this.error,
  });

  final MapsStatus status;

  /// Buildings with at least one traced floor on this device.
  final List<MappedBuilding> buildings;
  final String? error;

  int get floorCount =>
      buildings.fold(0, (total, building) => total + building.floors.length);

  MapsState copyWith({
    MapsStatus? status,
    List<MappedBuilding>? buildings,
    String? error,
  }) {
    return MapsState(
      status: status ?? this.status,
      buildings: buildings ?? this.buildings,
      error: error ?? this.error,
    );
  }

  @override
  List<Object?> get props => [status, buildings, error];
}
