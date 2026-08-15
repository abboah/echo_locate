// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'room_plan.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_RoomCorner _$RoomCornerFromJson(Map<String, dynamic> json) => _RoomCorner(
  x: (json['x'] as num).toDouble(),
  y: (json['y'] as num).toDouble(),
);

Map<String, dynamic> _$RoomCornerToJson(_RoomCorner instance) =>
    <String, dynamic>{'x': instance.x, 'y': instance.y};

_WingPlacement _$WingPlacementFromJson(Map<String, dynamic> json) =>
    _WingPlacement(
      dx: (json['dx'] as num?)?.toDouble() ?? 0,
      dy: (json['dy'] as num?)?.toDouble() ?? 0,
      rotation: (json['rotation'] as num?)?.toDouble() ?? 0,
    );

Map<String, dynamic> _$WingPlacementToJson(_WingPlacement instance) =>
    <String, dynamic>{
      'dx': instance.dx,
      'dy': instance.dy,
      'rotation': instance.rotation,
    };

_Room _$RoomFromJson(Map<String, dynamic> json) => _Room(
  id: json['id'] as String,
  floorId: json['floorId'] as String,
  code: json['code'] as String,
  category: $enumDecode(_$RoomCategoryEnumMap, json['category']),
  polygon:
      (json['polygon'] as List<dynamic>?)
          ?.map((e) => RoomCorner.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const <RoomCorner>[],
  label: json['label'] as String?,
  landmarkId: json['landmarkId'] as String?,
  wingId: json['wingId'] as String?,
  centreline:
      (json['centreline'] as List<dynamic>?)
          ?.map((e) => RoomCorner.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const <RoomCorner>[],
);

Map<String, dynamic> _$RoomToJson(_Room instance) => <String, dynamic>{
  'id': instance.id,
  'floorId': instance.floorId,
  'code': instance.code,
  'category': _$RoomCategoryEnumMap[instance.category]!,
  'polygon': instance.polygon.map((e) => e.toJson()).toList(),
  'label': instance.label,
  'landmarkId': instance.landmarkId,
  'wingId': instance.wingId,
  'centreline': instance.centreline.map((e) => e.toJson()).toList(),
};

const _$RoomCategoryEnumMap = {
  RoomCategory.lectureHall: 'lectureHall',
  RoomCategory.office: 'office',
  RoomCategory.laboratory: 'laboratory',
  RoomCategory.auditorium: 'auditorium',
  RoomCategory.controlRoom: 'controlRoom',
  RoomCategory.commonRoom: 'commonRoom',
  RoomCategory.library: 'library',
  RoomCategory.boardroom: 'boardroom',
  RoomCategory.washroom: 'washroom',
  RoomCategory.staircase: 'staircase',
  RoomCategory.elevator: 'elevator',
  RoomCategory.corridor: 'corridor',
  RoomCategory.balcony: 'balcony',
  RoomCategory.other: 'other',
};

_Opening _$OpeningFromJson(Map<String, dynamic> json) => _Opening(
  id: json['id'] as String,
  roomAId: json['roomAId'] as String,
  roomBId: json['roomBId'] as String?,
  at: RoomCorner.fromJson(json['at'] as Map<String, dynamic>),
  widthM: (json['widthM'] as num?)?.toDouble() ?? 0.9,
  isDoor: json['isDoor'] as bool? ?? true,
);

Map<String, dynamic> _$OpeningToJson(_Opening instance) => <String, dynamic>{
  'id': instance.id,
  'roomAId': instance.roomAId,
  'roomBId': instance.roomBId,
  'at': instance.at.toJson(),
  'widthM': instance.widthM,
  'isDoor': instance.isDoor,
};

_RoomPlan _$RoomPlanFromJson(Map<String, dynamic> json) => _RoomPlan(
  buildingId: json['buildingId'] as String,
  floorId: json['floorId'] as String,
  codePrefix: json['codePrefix'] as String,
  storedRooms:
      (json['rooms'] as List<dynamic>?)
          ?.map((e) => Room.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const <Room>[],
  storedOpenings:
      (json['openings'] as List<dynamic>?)
          ?.map((e) => Opening.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const <Opening>[],
  wings:
      (json['wings'] as Map<String, dynamic>?)?.map(
        (k, e) =>
            MapEntry(k, WingPlacement.fromJson(e as Map<String, dynamic>)),
      ) ??
      const <String, WingPlacement>{},
  declaredDoorCounts:
      (json['declaredDoorCounts'] as Map<String, dynamic>?)?.map(
        (k, e) => MapEntry(k, (e as num).toInt()),
      ) ??
      const <String, int>{},
  metresPerUnit: (json['metresPerUnit'] as num?)?.toDouble(),
);

Map<String, dynamic> _$RoomPlanToJson(_RoomPlan instance) => <String, dynamic>{
  'buildingId': instance.buildingId,
  'floorId': instance.floorId,
  'codePrefix': instance.codePrefix,
  'rooms': instance.storedRooms.map((e) => e.toJson()).toList(),
  'openings': instance.storedOpenings.map((e) => e.toJson()).toList(),
  'wings': instance.wings.map((k, e) => MapEntry(k, e.toJson())),
  'declaredDoorCounts': instance.declaredDoorCounts,
  'metresPerUnit': instance.metresPerUnit,
};
