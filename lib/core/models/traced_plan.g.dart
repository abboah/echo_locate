// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'traced_plan.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_TracedNode _$TracedNodeFromJson(Map<String, dynamic> json) => _TracedNode(
  ref: json['ref'] as String,
  x: (json['x'] as num).toDouble(),
  y: (json['y'] as num).toDouble(),
  floorId: json['floorId'] as String,
  kind: $enumDecode(_$LandmarkKindEnumMap, json['kind']),
  labelText: json['labelText'] as String,
  displayName: json['displayName'] as String,
  aliases:
      (json['aliases'] as List<dynamic>?)?.map((e) => e as String).toList() ??
      const <String>[],
  roomId: json['roomId'] as String?,
);

Map<String, dynamic> _$TracedNodeToJson(_TracedNode instance) =>
    <String, dynamic>{
      'ref': instance.ref,
      'x': instance.x,
      'y': instance.y,
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

_TracedEdge _$TracedEdgeFromJson(Map<String, dynamic> json) => _TracedEdge(
  fromRef: json['fromRef'] as String,
  toRef: json['toRef'] as String,
);

Map<String, dynamic> _$TracedEdgeToJson(_TracedEdge instance) =>
    <String, dynamic>{'fromRef': instance.fromRef, 'toRef': instance.toRef};

_TracedPlan _$TracedPlanFromJson(Map<String, dynamic> json) => _TracedPlan(
  buildingId: json['buildingId'] as String,
  nodes: (json['nodes'] as List<dynamic>)
      .map((e) => TracedNode.fromJson(e as Map<String, dynamic>))
      .toList(),
  edges: (json['edges'] as List<dynamic>)
      .map((e) => TracedEdge.fromJson(e as Map<String, dynamic>))
      .toList(),
  metresPerUnit: (json['metresPerUnit'] as num?)?.toDouble(),
);

Map<String, dynamic> _$TracedPlanToJson(_TracedPlan instance) =>
    <String, dynamic>{
      'buildingId': instance.buildingId,
      'nodes': instance.nodes.map((e) => e.toJson()).toList(),
      'edges': instance.edges.map((e) => e.toJson()).toList(),
      'metresPerUnit': instance.metresPerUnit,
    };
