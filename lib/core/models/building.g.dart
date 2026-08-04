// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'building.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_Building _$BuildingFromJson(Map<String, dynamic> json) => _Building(
  id: json['id'] as String,
  name: json['name'] as String,
  area: json['area'] as String,
  floorsCount: (json['floorsCount'] as num).toInt(),
  mappers: (json['mappers'] as num).toInt(),
  mappedPercent: (json['mappedPercent'] as num).toInt(),
  distanceKm: (json['distanceKm'] as num).toDouble(),
  category: json['category'] as String,
  glyph: json['glyph'] as String? ?? 'building',
  updatedLabel: json['updatedLabel'] as String? ?? 'updated recently',
);

Map<String, dynamic> _$BuildingToJson(_Building instance) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'area': instance.area,
  'floorsCount': instance.floorsCount,
  'mappers': instance.mappers,
  'mappedPercent': instance.mappedPercent,
  'distanceKm': instance.distanceKm,
  'category': instance.category,
  'glyph': instance.glyph,
  'updatedLabel': instance.updatedLabel,
};

_BuildingFloor _$BuildingFloorFromJson(Map<String, dynamic> json) =>
    _BuildingFloor(
      label: json['label'] as String,
      rooms: (json['rooms'] as List<dynamic>)
          .map((e) => Room.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$BuildingFloorToJson(_BuildingFloor instance) =>
    <String, dynamic>{'label': instance.label, 'rooms': instance.rooms};

_Room _$RoomFromJson(Map<String, dynamic> json) => _Room(
  id: json['id'] as String,
  name: json['name'] as String,
  distanceM: (json['distanceM'] as num).toInt(),
  kind: json['kind'] as String? ?? 'room',
);

Map<String, dynamic> _$RoomToJson(_Room instance) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'distanceM': instance.distanceM,
  'kind': instance.kind,
};
