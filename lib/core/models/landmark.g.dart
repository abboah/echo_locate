// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'landmark.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_Landmark _$LandmarkFromJson(Map<String, dynamic> json) => _Landmark(
  id: json['id'] as String,
  buildingId: json['buildingId'] as String,
  floorId: json['floorId'] as String,
  kind: $enumDecode(_$LandmarkKindEnumMap, json['kind']),
  labelText: json['labelText'] as String,
  displayName: json['displayName'] as String,
  aliases:
      (json['aliases'] as List<dynamic>?)?.map((e) => e as String).toList() ??
      const <String>[],
  roomId: json['roomId'] as String?,
);

Map<String, dynamic> _$LandmarkToJson(_Landmark instance) => <String, dynamic>{
  'id': instance.id,
  'buildingId': instance.buildingId,
  'floorId': instance.floorId,
  'kind': _$LandmarkKindEnumMap[instance.kind]!,
  'labelText': instance.labelText,
  'displayName': instance.displayName,
  'aliases': instance.aliases,
  'roomId': instance.roomId,
};

const _$LandmarkKindEnumMap = {
  LandmarkKind.entrance: 'entrance',
  LandmarkKind.junction: 'junction',
  LandmarkKind.stairs: 'stairs',
  LandmarkKind.lift: 'lift',
  LandmarkKind.door: 'door',
  LandmarkKind.sign: 'sign',
};
