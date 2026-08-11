import 'package:freezed_annotation/freezed_annotation.dart';

part 'building.freezed.dart';
part 'building.g.dart';

/// A mapped (or partially mapped) building in the crowdsourced index.
///
/// `glyph` picks the illustrative icon on cards/tiles ('building', 'door',
/// 'home', 'hall', 'book'); `category` drives the Explore filter chips
/// ('campus', 'hospital', 'mall').
@freezed
abstract class Building with _$Building {
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
abstract class BuildingFloor with _$BuildingFloor {
  const factory BuildingFloor({
    required String label,
    required List<Room> rooms,

    /// The `floors` row this came from. Every landmark belongs to a floor, so
    /// recording a route cannot start without one.
    ///
    /// Defaulted rather than required so a floor list cached by an older build
    /// still decodes — an empty id means "cached before floors were
    /// identified", and capture asks the contributor to reload rather than
    /// uploading landmarks attached to nothing.
    @Default('') String id,
  }) = _BuildingFloor;

  factory BuildingFloor.fromJson(Map<String, dynamic> json) =>
      _$BuildingFloorFromJson(json);
}

/// A room / point of interest on a floor. `kind` picks the tile icon
/// ('room', 'hall', 'desk').
@freezed
abstract class Room with _$Room {
  const factory Room({
    required String id,
    required String name,
    required int distanceM,
    @Default('room') String kind,
  }) = _Room;

  factory Room.fromJson(Map<String, dynamic> json) => _$RoomFromJson(json);
}
