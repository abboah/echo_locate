// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'landmark.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$Landmark {

 String get id; String get buildingId; String get floorId; LandmarkKind get kind;/// Normalised text OCR must match, e.g. `'204'`. Compared case- and
/// whitespace-insensitively, with a Levenshtein tolerance of 1.
 String get labelText;/// Human-facing name, e.g. `'Reading Hall door'`. Spoken on arrival.
 String get displayName;/// Systematic misreads seen in the field (`'2O4'`, `'2 04'`). The fuzzy
/// matcher covers single-character slips; this is for the rest.
 List<String> get aliases;/// Set when this landmark is a room's door — how a route ends.
 String? get roomId;
/// Create a copy of Landmark
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LandmarkCopyWith<Landmark> get copyWith => _$LandmarkCopyWithImpl<Landmark>(this as Landmark, _$identity);

  /// Serializes this Landmark to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Landmark&&(identical(other.id, id) || other.id == id)&&(identical(other.buildingId, buildingId) || other.buildingId == buildingId)&&(identical(other.floorId, floorId) || other.floorId == floorId)&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.labelText, labelText) || other.labelText == labelText)&&(identical(other.displayName, displayName) || other.displayName == displayName)&&const DeepCollectionEquality().equals(other.aliases, aliases)&&(identical(other.roomId, roomId) || other.roomId == roomId));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,buildingId,floorId,kind,labelText,displayName,const DeepCollectionEquality().hash(aliases),roomId);

@override
String toString() {
  return 'Landmark(id: $id, buildingId: $buildingId, floorId: $floorId, kind: $kind, labelText: $labelText, displayName: $displayName, aliases: $aliases, roomId: $roomId)';
}


}

/// @nodoc
abstract mixin class $LandmarkCopyWith<$Res>  {
  factory $LandmarkCopyWith(Landmark value, $Res Function(Landmark) _then) = _$LandmarkCopyWithImpl;
@useResult
$Res call({
 String id, String buildingId, String floorId, LandmarkKind kind, String labelText, String displayName, List<String> aliases, String? roomId
});




}
/// @nodoc
class _$LandmarkCopyWithImpl<$Res>
    implements $LandmarkCopyWith<$Res> {
  _$LandmarkCopyWithImpl(this._self, this._then);

  final Landmark _self;
  final $Res Function(Landmark) _then;

/// Create a copy of Landmark
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? buildingId = null,Object? floorId = null,Object? kind = null,Object? labelText = null,Object? displayName = null,Object? aliases = null,Object? roomId = freezed,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,buildingId: null == buildingId ? _self.buildingId : buildingId // ignore: cast_nullable_to_non_nullable
as String,floorId: null == floorId ? _self.floorId : floorId // ignore: cast_nullable_to_non_nullable
as String,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as LandmarkKind,labelText: null == labelText ? _self.labelText : labelText // ignore: cast_nullable_to_non_nullable
as String,displayName: null == displayName ? _self.displayName : displayName // ignore: cast_nullable_to_non_nullable
as String,aliases: null == aliases ? _self.aliases : aliases // ignore: cast_nullable_to_non_nullable
as List<String>,roomId: freezed == roomId ? _self.roomId : roomId // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [Landmark].
extension LandmarkPatterns on Landmark {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Landmark value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Landmark() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Landmark value)  $default,){
final _that = this;
switch (_that) {
case _Landmark():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Landmark value)?  $default,){
final _that = this;
switch (_that) {
case _Landmark() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String buildingId,  String floorId,  LandmarkKind kind,  String labelText,  String displayName,  List<String> aliases,  String? roomId)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Landmark() when $default != null:
return $default(_that.id,_that.buildingId,_that.floorId,_that.kind,_that.labelText,_that.displayName,_that.aliases,_that.roomId);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String buildingId,  String floorId,  LandmarkKind kind,  String labelText,  String displayName,  List<String> aliases,  String? roomId)  $default,) {final _that = this;
switch (_that) {
case _Landmark():
return $default(_that.id,_that.buildingId,_that.floorId,_that.kind,_that.labelText,_that.displayName,_that.aliases,_that.roomId);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String buildingId,  String floorId,  LandmarkKind kind,  String labelText,  String displayName,  List<String> aliases,  String? roomId)?  $default,) {final _that = this;
switch (_that) {
case _Landmark() when $default != null:
return $default(_that.id,_that.buildingId,_that.floorId,_that.kind,_that.labelText,_that.displayName,_that.aliases,_that.roomId);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _Landmark extends Landmark {
  const _Landmark({required this.id, required this.buildingId, required this.floorId, required this.kind, required this.labelText, required this.displayName, final  List<String> aliases = const <String>[], this.roomId}): _aliases = aliases,super._();
  factory _Landmark.fromJson(Map<String, dynamic> json) => _$LandmarkFromJson(json);

@override final  String id;
@override final  String buildingId;
@override final  String floorId;
@override final  LandmarkKind kind;
/// Normalised text OCR must match, e.g. `'204'`. Compared case- and
/// whitespace-insensitively, with a Levenshtein tolerance of 1.
@override final  String labelText;
/// Human-facing name, e.g. `'Reading Hall door'`. Spoken on arrival.
@override final  String displayName;
/// Systematic misreads seen in the field (`'2O4'`, `'2 04'`). The fuzzy
/// matcher covers single-character slips; this is for the rest.
 final  List<String> _aliases;
/// Systematic misreads seen in the field (`'2O4'`, `'2 04'`). The fuzzy
/// matcher covers single-character slips; this is for the rest.
@override@JsonKey() List<String> get aliases {
  if (_aliases is EqualUnmodifiableListView) return _aliases;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_aliases);
}

/// Set when this landmark is a room's door — how a route ends.
@override final  String? roomId;

/// Create a copy of Landmark
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$LandmarkCopyWith<_Landmark> get copyWith => __$LandmarkCopyWithImpl<_Landmark>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$LandmarkToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Landmark&&(identical(other.id, id) || other.id == id)&&(identical(other.buildingId, buildingId) || other.buildingId == buildingId)&&(identical(other.floorId, floorId) || other.floorId == floorId)&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.labelText, labelText) || other.labelText == labelText)&&(identical(other.displayName, displayName) || other.displayName == displayName)&&const DeepCollectionEquality().equals(other._aliases, _aliases)&&(identical(other.roomId, roomId) || other.roomId == roomId));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,buildingId,floorId,kind,labelText,displayName,const DeepCollectionEquality().hash(_aliases),roomId);

@override
String toString() {
  return 'Landmark(id: $id, buildingId: $buildingId, floorId: $floorId, kind: $kind, labelText: $labelText, displayName: $displayName, aliases: $aliases, roomId: $roomId)';
}


}

/// @nodoc
abstract mixin class _$LandmarkCopyWith<$Res> implements $LandmarkCopyWith<$Res> {
  factory _$LandmarkCopyWith(_Landmark value, $Res Function(_Landmark) _then) = __$LandmarkCopyWithImpl;
@override @useResult
$Res call({
 String id, String buildingId, String floorId, LandmarkKind kind, String labelText, String displayName, List<String> aliases, String? roomId
});




}
/// @nodoc
class __$LandmarkCopyWithImpl<$Res>
    implements _$LandmarkCopyWith<$Res> {
  __$LandmarkCopyWithImpl(this._self, this._then);

  final _Landmark _self;
  final $Res Function(_Landmark) _then;

/// Create a copy of Landmark
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? buildingId = null,Object? floorId = null,Object? kind = null,Object? labelText = null,Object? displayName = null,Object? aliases = null,Object? roomId = freezed,}) {
  return _then(_Landmark(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,buildingId: null == buildingId ? _self.buildingId : buildingId // ignore: cast_nullable_to_non_nullable
as String,floorId: null == floorId ? _self.floorId : floorId // ignore: cast_nullable_to_non_nullable
as String,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as LandmarkKind,labelText: null == labelText ? _self.labelText : labelText // ignore: cast_nullable_to_non_nullable
as String,displayName: null == displayName ? _self.displayName : displayName // ignore: cast_nullable_to_non_nullable
as String,aliases: null == aliases ? _self._aliases : aliases // ignore: cast_nullable_to_non_nullable
as List<String>,roomId: freezed == roomId ? _self.roomId : roomId // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
