// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'route_draft.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_DraftLandmark _$DraftLandmarkFromJson(Map<String, dynamic> json) =>
    _DraftLandmark(
      ref: json['ref'] as String,
      floorId: json['floorId'] as String,
      kind: $enumDecode(_$LandmarkKindEnumMap, json['kind']),
      labelText: json['labelText'] as String,
      displayName: json['displayName'] as String,
      aliases:
          (json['aliases'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const <String>[],
      roomId: json['roomId'] as String?,
    );

Map<String, dynamic> _$DraftLandmarkToJson(_DraftLandmark instance) =>
    <String, dynamic>{
      'ref': instance.ref,
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

_DraftStep _$DraftStepFromJson(Map<String, dynamic> json) => _DraftStep(
  seq: (json['seq'] as num).toInt(),
  fromRef: json['from'] as String,
  toRef: json['to'] as String,
  instruction: json['instruction'] as String,
  distanceM: (json['distanceM'] as num).toDouble(),
  turnDeg: (json['turnDeg'] as num?)?.toInt() ?? 0,
  stepsRecorded: (json['stepsRecorded'] as num?)?.toInt(),
);

Map<String, dynamic> _$DraftStepToJson(_DraftStep instance) =>
    <String, dynamic>{
      'seq': instance.seq,
      'from': instance.fromRef,
      'to': instance.toRef,
      'instruction': instance.instruction,
      'distanceM': instance.distanceM,
      'turnDeg': instance.turnDeg,
      'stepsRecorded': instance.stepsRecorded,
    };

_RouteDraft _$RouteDraftFromJson(Map<String, dynamic> json) => _RouteDraft(
  buildingId: json['buildingId'] as String,
  destinationRoomId: json['destinationRoomId'] as String,
  landmarks: (json['landmarks'] as List<dynamic>)
      .map((e) => DraftLandmark.fromJson(e as Map<String, dynamic>))
      .toList(),
  steps: (json['steps'] as List<dynamic>)
      .map((e) => DraftStep.fromJson(e as Map<String, dynamic>))
      .toList(),
);

Map<String, dynamic> _$RouteDraftToJson(_RouteDraft instance) =>
    <String, dynamic>{
      'buildingId': instance.buildingId,
      'destinationRoomId': instance.destinationRoomId,
      'landmarks': instance.landmarks,
      'steps': instance.steps,
    };
