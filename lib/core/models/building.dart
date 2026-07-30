import 'package:freezed_annotation/freezed_annotation.dart';

part 'building.freezed.dart';
part 'building.g.dart';

/// A mapped (or partially mapped) building in the crowdsourced index.
///
/// `glyph` picks the illustrative icon on cards/tiles ('building', 'door',
/// 'home', 'hall', 'book'); `category` drives the Explore filter chips
/// ('campus', 'hospital', 'mall').
@freezed
class Building with _$Building {
  const factory Building({
    required String id,
    required String name,
    required String area,
    required int floorsCount,
    required int mappers,
    required int mappedPercent,
    required double distanceKm,
    required String category,
    @Default('building') String glyph,
    @Default('updated recently') String updatedLabel,
  }) = _Building;

  factory Building.fromJson(Map<String, dynamic> json) =>
      _$BuildingFromJson(json);
}

/// One floor of a building, with its navigable rooms/POIs.
@freezed
class BuildingFloor with _$BuildingFloor {
  const factory BuildingFloor({
    required String label,
    required List<Room> rooms,
  }) = _BuildingFloor;

  factory BuildingFloor.fromJson(Map<String, dynamic> json) =>
      _$BuildingFloorFromJson(json);
}

/// A room / point of interest on a floor. `kind` picks the tile icon
/// ('room', 'hall', 'desk').
@freezed
class Room with _$Room {
  const factory Room({
    required String id,
    required String name,
    required int distanceM,
    @Default('room') String kind,
  }) = _Room;

  factory Room.fromJson(Map<String, dynamic> json) => _$RoomFromJson(json);
}
