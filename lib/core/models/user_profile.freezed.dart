// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'user_profile.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
  'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models',
);

UserProfile _$UserProfileFromJson(Map<String, dynamic> json) {
  return _UserProfile.fromJson(json);
}

/// @nodoc
mixin _$UserProfile {
  String get id => throw _privateConstructorUsedError;
  String get fullName => throw _privateConstructorUsedError;
  String get email => throw _privateConstructorUsedError;
  int get buildingsMapped => throw _privateConstructorUsedError;
  int get floorsMapped => throw _privateConstructorUsedError;
  int get roomsMapped => throw _privateConstructorUsedError;
  String get rankLabel => throw _privateConstructorUsedError;

  /// Serializes this UserProfile to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of UserProfile
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $UserProfileCopyWith<UserProfile> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $UserProfileCopyWith<$Res> {
  factory $UserProfileCopyWith(
    UserProfile value,
    $Res Function(UserProfile) then,
  ) = _$UserProfileCopyWithImpl<$Res, UserProfile>;
  @useResult
  $Res call({
    String id,
    String fullName,
    String email,
    int buildingsMapped,
    int floorsMapped,
    int roomsMapped,
    String rankLabel,
  });
}

/// @nodoc
class _$UserProfileCopyWithImpl<$Res, $Val extends UserProfile>
    implements $UserProfileCopyWith<$Res> {
  _$UserProfileCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of UserProfile
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? fullName = null,
    Object? email = null,
    Object? buildingsMapped = null,
    Object? floorsMapped = null,
    Object? roomsMapped = null,
    Object? rankLabel = null,
  }) {
    return _then(
      _value.copyWith(
            id: null == id
                ? _value.id
                : id // ignore: cast_nullable_to_non_nullable
                      as String,
            fullName: null == fullName
                ? _value.fullName
                : fullName // ignore: cast_nullable_to_non_nullable
                      as String,
            email: null == email
                ? _value.email
                : email // ignore: cast_nullable_to_non_nullable
                      as String,
            buildingsMapped: null == buildingsMapped
                ? _value.buildingsMapped
                : buildingsMapped // ignore: cast_nullable_to_non_nullable
                      as int,
            floorsMapped: null == floorsMapped
                ? _value.floorsMapped
                : floorsMapped // ignore: cast_nullable_to_non_nullable
                      as int,
            roomsMapped: null == roomsMapped
                ? _value.roomsMapped
                : roomsMapped // ignore: cast_nullable_to_non_nullable
                      as int,
            rankLabel: null == rankLabel
                ? _value.rankLabel
                : rankLabel // ignore: cast_nullable_to_non_nullable
                      as String,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$UserProfileImplCopyWith<$Res>
    implements $UserProfileCopyWith<$Res> {
  factory _$$UserProfileImplCopyWith(
    _$UserProfileImpl value,
    $Res Function(_$UserProfileImpl) then,
  ) = __$$UserProfileImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    String id,
    String fullName,
    String email,
    int buildingsMapped,
    int floorsMapped,
    int roomsMapped,
    String rankLabel,
  });
}

/// @nodoc
class __$$UserProfileImplCopyWithImpl<$Res>
    extends _$UserProfileCopyWithImpl<$Res, _$UserProfileImpl>
    implements _$$UserProfileImplCopyWith<$Res> {
  __$$UserProfileImplCopyWithImpl(
    _$UserProfileImpl _value,
    $Res Function(_$UserProfileImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of UserProfile
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? fullName = null,
    Object? email = null,
    Object? buildingsMapped = null,
    Object? floorsMapped = null,
    Object? roomsMapped = null,
    Object? rankLabel = null,
  }) {
    return _then(
      _$UserProfileImpl(
        id: null == id
            ? _value.id
            : id // ignore: cast_nullable_to_non_nullable
                  as String,
        fullName: null == fullName
            ? _value.fullName
            : fullName // ignore: cast_nullable_to_non_nullable
                  as String,
        email: null == email
            ? _value.email
            : email // ignore: cast_nullable_to_non_nullable
                  as String,
        buildingsMapped: null == buildingsMapped
            ? _value.buildingsMapped
            : buildingsMapped // ignore: cast_nullable_to_non_nullable
                  as int,
        floorsMapped: null == floorsMapped
            ? _value.floorsMapped
            : floorsMapped // ignore: cast_nullable_to_non_nullable
                  as int,
        roomsMapped: null == roomsMapped
            ? _value.roomsMapped
            : roomsMapped // ignore: cast_nullable_to_non_nullable
                  as int,
        rankLabel: null == rankLabel
            ? _value.rankLabel
            : rankLabel // ignore: cast_nullable_to_non_nullable
                  as String,
      ),
    );
  }
}

/// @nodoc
@JsonSerializable()
class _$UserProfileImpl implements _UserProfile {
  const _$UserProfileImpl({
    required this.id,
    required this.fullName,
    required this.email,
    this.buildingsMapped = 0,
    this.floorsMapped = 0,
    this.roomsMapped = 0,
    this.rankLabel = 'New mapper',
  });

  factory _$UserProfileImpl.fromJson(Map<String, dynamic> json) =>
      _$$UserProfileImplFromJson(json);

  @override
  final String id;
  @override
  final String fullName;
  @override
  final String email;
  @override
  @JsonKey()
  final int buildingsMapped;
  @override
  @JsonKey()
  final int floorsMapped;
  @override
  @JsonKey()
  final int roomsMapped;
  @override
  @JsonKey()
  final String rankLabel;

  @override
  String toString() {
    return 'UserProfile(id: $id, fullName: $fullName, email: $email, buildingsMapped: $buildingsMapped, floorsMapped: $floorsMapped, roomsMapped: $roomsMapped, rankLabel: $rankLabel)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$UserProfileImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.fullName, fullName) ||
                other.fullName == fullName) &&
            (identical(other.email, email) || other.email == email) &&
            (identical(other.buildingsMapped, buildingsMapped) ||
                other.buildingsMapped == buildingsMapped) &&
            (identical(other.floorsMapped, floorsMapped) ||
                other.floorsMapped == floorsMapped) &&
            (identical(other.roomsMapped, roomsMapped) ||
                other.roomsMapped == roomsMapped) &&
            (identical(other.rankLabel, rankLabel) ||
                other.rankLabel == rankLabel));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
    runtimeType,
    id,
    fullName,
    email,
    buildingsMapped,
    floorsMapped,
    roomsMapped,
    rankLabel,
  );

  /// Create a copy of UserProfile
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$UserProfileImplCopyWith<_$UserProfileImpl> get copyWith =>
      __$$UserProfileImplCopyWithImpl<_$UserProfileImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$UserProfileImplToJson(this);
  }
}

abstract class _UserProfile implements UserProfile {
  const factory _UserProfile({
    required final String id,
    required final String fullName,
    required final String email,
    final int buildingsMapped,
    final int floorsMapped,
    final int roomsMapped,
    final String rankLabel,
  }) = _$UserProfileImpl;

  factory _UserProfile.fromJson(Map<String, dynamic> json) =
      _$UserProfileImpl.fromJson;

  @override
  String get id;
  @override
  String get fullName;
  @override
  String get email;
  @override
  int get buildingsMapped;
  @override
  int get floorsMapped;
  @override
  int get roomsMapped;
  @override
  String get rankLabel;

  /// Create a copy of UserProfile
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$UserProfileImplCopyWith<_$UserProfileImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
