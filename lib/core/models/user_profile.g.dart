// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'user_profile.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$UserProfileImpl _$$UserProfileImplFromJson(Map<String, dynamic> json) =>
    _$UserProfileImpl(
      id: json['id'] as String,
      fullName: json['fullName'] as String,
      email: json['email'] as String,
      buildingsMapped: (json['buildingsMapped'] as num?)?.toInt() ?? 0,
      floorsMapped: (json['floorsMapped'] as num?)?.toInt() ?? 0,
      roomsMapped: (json['roomsMapped'] as num?)?.toInt() ?? 0,
      rankLabel: json['rankLabel'] as String? ?? 'New mapper',
    );

Map<String, dynamic> _$$UserProfileImplToJson(_$UserProfileImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'fullName': instance.fullName,
      'email': instance.email,
      'buildingsMapped': instance.buildingsMapped,
      'floorsMapped': instance.floorsMapped,
      'roomsMapped': instance.roomsMapped,
      'rankLabel': instance.rankLabel,
    };
