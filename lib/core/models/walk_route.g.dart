// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'walk_route.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_RouteStep _$RouteStepFromJson(Map<String, dynamic> json) => _RouteStep(
  seq: (json['seq'] as num).toInt(),
  fromLandmarkId: json['fromLandmarkId'] as String,
  toLandmarkId: json['toLandmarkId'] as String,
  instruction: json['instruction'] as String,
  distanceM: (json['distanceM'] as num).toDouble(),
  turnDeg: (json['turnDeg'] as num?)?.toInt() ?? 0,
  stepsRecorded: (json['stepsRecorded'] as num?)?.toInt(),
);

Map<String, dynamic> _$RouteStepToJson(_RouteStep instance) =>
    <String, dynamic>{
      'seq': instance.seq,
      'fromLandmarkId': instance.fromLandmarkId,
      'toLandmarkId': instance.toLandmarkId,
      'instruction': instance.instruction,
      'distanceM': instance.distanceM,
      'turnDeg': instance.turnDeg,
      'stepsRecorded': instance.stepsRecorded,
    };

_WalkRoute _$WalkRouteFromJson(Map<String, dynamic> json) => _WalkRoute(
  id: json['id'] as String,
  buildingId: json['buildingId'] as String,
  startLandmarkId: json['startLandmarkId'] as String,
  destinationRoomId: json['destinationRoomId'] as String,
  steps: (json['steps'] as List<dynamic>)
      .map((e) => RouteStep.fromJson(e as Map<String, dynamic>))
      .toList(),
  totalDistanceM: (json['totalDistanceM'] as num?)?.toDouble() ?? 0,
  verifiedCount: (json['verifiedCount'] as num?)?.toInt() ?? 0,
);

Map<String, dynamic> _$WalkRouteToJson(_WalkRoute instance) =>
    <String, dynamic>{
      'id': instance.id,
      'buildingId': instance.buildingId,
      'startLandmarkId': instance.startLandmarkId,
      'destinationRoomId': instance.destinationRoomId,
      'steps': instance.steps.map((e) => e.toJson()).toList(),
      'totalDistanceM': instance.totalDistanceM,
      'verifiedCount': instance.verifiedCount,
    };
