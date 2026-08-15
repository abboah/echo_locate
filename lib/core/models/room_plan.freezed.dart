// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'room_plan.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$RoomCorner {

 double get x; double get y;
/// Create a copy of RoomCorner
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RoomCornerCopyWith<RoomCorner> get copyWith => _$RoomCornerCopyWithImpl<RoomCorner>(this as RoomCorner, _$identity);

  /// Serializes this RoomCorner to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RoomCorner&&(identical(other.x, x) || other.x == x)&&(identical(other.y, y) || other.y == y));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,x,y);

@override
String toString() {
  return 'RoomCorner(x: $x, y: $y)';
}


}

/// @nodoc
abstract mixin class $RoomCornerCopyWith<$Res>  {
  factory $RoomCornerCopyWith(RoomCorner value, $Res Function(RoomCorner) _then) = _$RoomCornerCopyWithImpl;
@useResult
$Res call({
 double x, double y
});




}
/// @nodoc
class _$RoomCornerCopyWithImpl<$Res>
    implements $RoomCornerCopyWith<$Res> {
  _$RoomCornerCopyWithImpl(this._self, this._then);

  final RoomCorner _self;
  final $Res Function(RoomCorner) _then;

/// Create a copy of RoomCorner
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? x = null,Object? y = null,}) {
  return _then(_self.copyWith(
x: null == x ? _self.x : x // ignore: cast_nullable_to_non_nullable
as double,y: null == y ? _self.y : y // ignore: cast_nullable_to_non_nullable
as double,
  ));
}

}


/// Adds pattern-matching-related methods to [RoomCorner].
extension RoomCornerPatterns on RoomCorner {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _RoomCorner value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _RoomCorner() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _RoomCorner value)  $default,){
final _that = this;
switch (_that) {
case _RoomCorner():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _RoomCorner value)?  $default,){
final _that = this;
switch (_that) {
case _RoomCorner() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( double x,  double y)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _RoomCorner() when $default != null:
return $default(_that.x,_that.y);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( double x,  double y)  $default,) {final _that = this;
switch (_that) {
case _RoomCorner():
return $default(_that.x,_that.y);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( double x,  double y)?  $default,) {final _that = this;
switch (_that) {
case _RoomCorner() when $default != null:
return $default(_that.x,_that.y);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _RoomCorner extends RoomCorner {
  const _RoomCorner({required this.x, required this.y}): super._();
  factory _RoomCorner.fromJson(Map<String, dynamic> json) => _$RoomCornerFromJson(json);

@override final  double x;
@override final  double y;

/// Create a copy of RoomCorner
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RoomCornerCopyWith<_RoomCorner> get copyWith => __$RoomCornerCopyWithImpl<_RoomCorner>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$RoomCornerToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _RoomCorner&&(identical(other.x, x) || other.x == x)&&(identical(other.y, y) || other.y == y));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,x,y);

@override
String toString() {
  return 'RoomCorner(x: $x, y: $y)';
}


}

/// @nodoc
abstract mixin class _$RoomCornerCopyWith<$Res> implements $RoomCornerCopyWith<$Res> {
  factory _$RoomCornerCopyWith(_RoomCorner value, $Res Function(_RoomCorner) _then) = __$RoomCornerCopyWithImpl;
@override @useResult
$Res call({
 double x, double y
});




}
/// @nodoc
class __$RoomCornerCopyWithImpl<$Res>
    implements _$RoomCornerCopyWith<$Res> {
  __$RoomCornerCopyWithImpl(this._self, this._then);

  final _RoomCorner _self;
  final $Res Function(_RoomCorner) _then;

/// Create a copy of RoomCorner
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? x = null,Object? y = null,}) {
  return _then(_RoomCorner(
x: null == x ? _self.x : x // ignore: cast_nullable_to_non_nullable
as double,y: null == y ? _self.y : y // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}


/// @nodoc
mixin _$WingPlacement {

 double get dx; double get dy;/// Radians, counter-clockwise, applied **before** the shift.
 double get rotation;
/// Create a copy of WingPlacement
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$WingPlacementCopyWith<WingPlacement> get copyWith => _$WingPlacementCopyWithImpl<WingPlacement>(this as WingPlacement, _$identity);

  /// Serializes this WingPlacement to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is WingPlacement&&(identical(other.dx, dx) || other.dx == dx)&&(identical(other.dy, dy) || other.dy == dy)&&(identical(other.rotation, rotation) || other.rotation == rotation));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,dx,dy,rotation);

@override
String toString() {
  return 'WingPlacement(dx: $dx, dy: $dy, rotation: $rotation)';
}


}

/// @nodoc
abstract mixin class $WingPlacementCopyWith<$Res>  {
  factory $WingPlacementCopyWith(WingPlacement value, $Res Function(WingPlacement) _then) = _$WingPlacementCopyWithImpl;
@useResult
$Res call({
 double dx, double dy, double rotation
});




}
/// @nodoc
class _$WingPlacementCopyWithImpl<$Res>
    implements $WingPlacementCopyWith<$Res> {
  _$WingPlacementCopyWithImpl(this._self, this._then);

  final WingPlacement _self;
  final $Res Function(WingPlacement) _then;

/// Create a copy of WingPlacement
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? dx = null,Object? dy = null,Object? rotation = null,}) {
  return _then(_self.copyWith(
dx: null == dx ? _self.dx : dx // ignore: cast_nullable_to_non_nullable
as double,dy: null == dy ? _self.dy : dy // ignore: cast_nullable_to_non_nullable
as double,rotation: null == rotation ? _self.rotation : rotation // ignore: cast_nullable_to_non_nullable
as double,
  ));
}

}


/// Adds pattern-matching-related methods to [WingPlacement].
extension WingPlacementPatterns on WingPlacement {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _WingPlacement value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _WingPlacement() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _WingPlacement value)  $default,){
final _that = this;
switch (_that) {
case _WingPlacement():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _WingPlacement value)?  $default,){
final _that = this;
switch (_that) {
case _WingPlacement() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( double dx,  double dy,  double rotation)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _WingPlacement() when $default != null:
return $default(_that.dx,_that.dy,_that.rotation);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( double dx,  double dy,  double rotation)  $default,) {final _that = this;
switch (_that) {
case _WingPlacement():
return $default(_that.dx,_that.dy,_that.rotation);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( double dx,  double dy,  double rotation)?  $default,) {final _that = this;
switch (_that) {
case _WingPlacement() when $default != null:
return $default(_that.dx,_that.dy,_that.rotation);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _WingPlacement extends WingPlacement {
  const _WingPlacement({this.dx = 0, this.dy = 0, this.rotation = 0}): super._();
  factory _WingPlacement.fromJson(Map<String, dynamic> json) => _$WingPlacementFromJson(json);

@override@JsonKey() final  double dx;
@override@JsonKey() final  double dy;
/// Radians, counter-clockwise, applied **before** the shift.
@override@JsonKey() final  double rotation;

/// Create a copy of WingPlacement
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$WingPlacementCopyWith<_WingPlacement> get copyWith => __$WingPlacementCopyWithImpl<_WingPlacement>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$WingPlacementToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _WingPlacement&&(identical(other.dx, dx) || other.dx == dx)&&(identical(other.dy, dy) || other.dy == dy)&&(identical(other.rotation, rotation) || other.rotation == rotation));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,dx,dy,rotation);

@override
String toString() {
  return 'WingPlacement(dx: $dx, dy: $dy, rotation: $rotation)';
}


}

/// @nodoc
abstract mixin class _$WingPlacementCopyWith<$Res> implements $WingPlacementCopyWith<$Res> {
  factory _$WingPlacementCopyWith(_WingPlacement value, $Res Function(_WingPlacement) _then) = __$WingPlacementCopyWithImpl;
@override @useResult
$Res call({
 double dx, double dy, double rotation
});




}
/// @nodoc
class __$WingPlacementCopyWithImpl<$Res>
    implements _$WingPlacementCopyWith<$Res> {
  __$WingPlacementCopyWithImpl(this._self, this._then);

  final _WingPlacement _self;
  final $Res Function(_WingPlacement) _then;

/// Create a copy of WingPlacement
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? dx = null,Object? dy = null,Object? rotation = null,}) {
  return _then(_WingPlacement(
dx: null == dx ? _self.dx : dx // ignore: cast_nullable_to_non_nullable
as double,dy: null == dy ? _self.dy : dy // ignore: cast_nullable_to_non_nullable
as double,rotation: null == rotation ? _self.rotation : rotation // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}


/// @nodoc
mixin _$Room {

 String get id; String get floorId;/// Auto-allocated, e.g. `'GF 14'`. Never typed by a contributor — see
/// [RoomPlan.allocateCode].
 String get code; RoomCategory get category;/// Corners in metres, counter-clockwise. Always run through
/// `cleanupPolygon` before construction; nothing downstream re-normalises.
 List<RoomCorner> get polygon;/// What the sign on the door says, when anybody has tagged it.
 String? get label;/// The landmark this room's door corresponds to, joining the area map to
/// the landmark map that guidance already runs on.
 String? get landmarkId;/// Which capture session this room came from — see [WingPlacement].
///
/// Null for a plan captured or traced in one go, which is the common case
/// and needs no alignment.
 String? get wingId;/// The line down the middle of a corridor, when it was drawn as a path.
///
/// Empty for every ordinary room, and for a corridor traced as a bare
/// polygon — which is why every plan saved before this existed still loads.
///
/// A corridor is the one room whose *shape* is not what matters about it.
/// What a walker needs is the line they follow, its direction at each point,
/// and the real distance along it. A polygon supplies none of those: the
/// direction has to be guessed from the longest wall, which is wrong the
/// moment the corridor bends, and the distance between two doors is measured
/// straight through the wall between them.
///
/// So a corridor may instead be drawn as a path, and its [polygon] generated
/// around it by [ribbonAround]. Both are stored: the polygon is what gets
/// drawn and what door inference snaps to, the centreline is what routing
/// and door counting run on.
 List<RoomCorner> get centreline;
/// Create a copy of Room
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RoomCopyWith<Room> get copyWith => _$RoomCopyWithImpl<Room>(this as Room, _$identity);

  /// Serializes this Room to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Room&&(identical(other.id, id) || other.id == id)&&(identical(other.floorId, floorId) || other.floorId == floorId)&&(identical(other.code, code) || other.code == code)&&(identical(other.category, category) || other.category == category)&&const DeepCollectionEquality().equals(other.polygon, polygon)&&(identical(other.label, label) || other.label == label)&&(identical(other.landmarkId, landmarkId) || other.landmarkId == landmarkId)&&(identical(other.wingId, wingId) || other.wingId == wingId)&&const DeepCollectionEquality().equals(other.centreline, centreline));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,floorId,code,category,const DeepCollectionEquality().hash(polygon),label,landmarkId,wingId,const DeepCollectionEquality().hash(centreline));

@override
String toString() {
  return 'Room(id: $id, floorId: $floorId, code: $code, category: $category, polygon: $polygon, label: $label, landmarkId: $landmarkId, wingId: $wingId, centreline: $centreline)';
}


}

/// @nodoc
abstract mixin class $RoomCopyWith<$Res>  {
  factory $RoomCopyWith(Room value, $Res Function(Room) _then) = _$RoomCopyWithImpl;
@useResult
$Res call({
 String id, String floorId, String code, RoomCategory category, List<RoomCorner> polygon, String? label, String? landmarkId, String? wingId, List<RoomCorner> centreline
});




}
/// @nodoc
class _$RoomCopyWithImpl<$Res>
    implements $RoomCopyWith<$Res> {
  _$RoomCopyWithImpl(this._self, this._then);

  final Room _self;
  final $Res Function(Room) _then;

/// Create a copy of Room
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? floorId = null,Object? code = null,Object? category = null,Object? polygon = null,Object? label = freezed,Object? landmarkId = freezed,Object? wingId = freezed,Object? centreline = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,floorId: null == floorId ? _self.floorId : floorId // ignore: cast_nullable_to_non_nullable
as String,code: null == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as String,category: null == category ? _self.category : category // ignore: cast_nullable_to_non_nullable
as RoomCategory,polygon: null == polygon ? _self.polygon : polygon // ignore: cast_nullable_to_non_nullable
as List<RoomCorner>,label: freezed == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String?,landmarkId: freezed == landmarkId ? _self.landmarkId : landmarkId // ignore: cast_nullable_to_non_nullable
as String?,wingId: freezed == wingId ? _self.wingId : wingId // ignore: cast_nullable_to_non_nullable
as String?,centreline: null == centreline ? _self.centreline : centreline // ignore: cast_nullable_to_non_nullable
as List<RoomCorner>,
  ));
}

}


/// Adds pattern-matching-related methods to [Room].
extension RoomPatterns on Room {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Room value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Room() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Room value)  $default,){
final _that = this;
switch (_that) {
case _Room():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Room value)?  $default,){
final _that = this;
switch (_that) {
case _Room() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String floorId,  String code,  RoomCategory category,  List<RoomCorner> polygon,  String? label,  String? landmarkId,  String? wingId,  List<RoomCorner> centreline)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Room() when $default != null:
return $default(_that.id,_that.floorId,_that.code,_that.category,_that.polygon,_that.label,_that.landmarkId,_that.wingId,_that.centreline);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String floorId,  String code,  RoomCategory category,  List<RoomCorner> polygon,  String? label,  String? landmarkId,  String? wingId,  List<RoomCorner> centreline)  $default,) {final _that = this;
switch (_that) {
case _Room():
return $default(_that.id,_that.floorId,_that.code,_that.category,_that.polygon,_that.label,_that.landmarkId,_that.wingId,_that.centreline);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String floorId,  String code,  RoomCategory category,  List<RoomCorner> polygon,  String? label,  String? landmarkId,  String? wingId,  List<RoomCorner> centreline)?  $default,) {final _that = this;
switch (_that) {
case _Room() when $default != null:
return $default(_that.id,_that.floorId,_that.code,_that.category,_that.polygon,_that.label,_that.landmarkId,_that.wingId,_that.centreline);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _Room extends Room {
  const _Room({required this.id, required this.floorId, required this.code, required this.category, final  List<RoomCorner> polygon = const <RoomCorner>[], this.label, this.landmarkId, this.wingId, final  List<RoomCorner> centreline = const <RoomCorner>[]}): _polygon = polygon,_centreline = centreline,super._();
  factory _Room.fromJson(Map<String, dynamic> json) => _$RoomFromJson(json);

@override final  String id;
@override final  String floorId;
/// Auto-allocated, e.g. `'GF 14'`. Never typed by a contributor — see
/// [RoomPlan.allocateCode].
@override final  String code;
@override final  RoomCategory category;
/// Corners in metres, counter-clockwise. Always run through
/// `cleanupPolygon` before construction; nothing downstream re-normalises.
 final  List<RoomCorner> _polygon;
/// Corners in metres, counter-clockwise. Always run through
/// `cleanupPolygon` before construction; nothing downstream re-normalises.
@override@JsonKey() List<RoomCorner> get polygon {
  if (_polygon is EqualUnmodifiableListView) return _polygon;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_polygon);
}

/// What the sign on the door says, when anybody has tagged it.
@override final  String? label;
/// The landmark this room's door corresponds to, joining the area map to
/// the landmark map that guidance already runs on.
@override final  String? landmarkId;
/// Which capture session this room came from — see [WingPlacement].
///
/// Null for a plan captured or traced in one go, which is the common case
/// and needs no alignment.
@override final  String? wingId;
/// The line down the middle of a corridor, when it was drawn as a path.
///
/// Empty for every ordinary room, and for a corridor traced as a bare
/// polygon — which is why every plan saved before this existed still loads.
///
/// A corridor is the one room whose *shape* is not what matters about it.
/// What a walker needs is the line they follow, its direction at each point,
/// and the real distance along it. A polygon supplies none of those: the
/// direction has to be guessed from the longest wall, which is wrong the
/// moment the corridor bends, and the distance between two doors is measured
/// straight through the wall between them.
///
/// So a corridor may instead be drawn as a path, and its [polygon] generated
/// around it by [ribbonAround]. Both are stored: the polygon is what gets
/// drawn and what door inference snaps to, the centreline is what routing
/// and door counting run on.
 final  List<RoomCorner> _centreline;
/// The line down the middle of a corridor, when it was drawn as a path.
///
/// Empty for every ordinary room, and for a corridor traced as a bare
/// polygon — which is why every plan saved before this existed still loads.
///
/// A corridor is the one room whose *shape* is not what matters about it.
/// What a walker needs is the line they follow, its direction at each point,
/// and the real distance along it. A polygon supplies none of those: the
/// direction has to be guessed from the longest wall, which is wrong the
/// moment the corridor bends, and the distance between two doors is measured
/// straight through the wall between them.
///
/// So a corridor may instead be drawn as a path, and its [polygon] generated
/// around it by [ribbonAround]. Both are stored: the polygon is what gets
/// drawn and what door inference snaps to, the centreline is what routing
/// and door counting run on.
@override@JsonKey() List<RoomCorner> get centreline {
  if (_centreline is EqualUnmodifiableListView) return _centreline;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_centreline);
}


/// Create a copy of Room
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RoomCopyWith<_Room> get copyWith => __$RoomCopyWithImpl<_Room>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$RoomToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Room&&(identical(other.id, id) || other.id == id)&&(identical(other.floorId, floorId) || other.floorId == floorId)&&(identical(other.code, code) || other.code == code)&&(identical(other.category, category) || other.category == category)&&const DeepCollectionEquality().equals(other._polygon, _polygon)&&(identical(other.label, label) || other.label == label)&&(identical(other.landmarkId, landmarkId) || other.landmarkId == landmarkId)&&(identical(other.wingId, wingId) || other.wingId == wingId)&&const DeepCollectionEquality().equals(other._centreline, _centreline));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,floorId,code,category,const DeepCollectionEquality().hash(_polygon),label,landmarkId,wingId,const DeepCollectionEquality().hash(_centreline));

@override
String toString() {
  return 'Room(id: $id, floorId: $floorId, code: $code, category: $category, polygon: $polygon, label: $label, landmarkId: $landmarkId, wingId: $wingId, centreline: $centreline)';
}


}

/// @nodoc
abstract mixin class _$RoomCopyWith<$Res> implements $RoomCopyWith<$Res> {
  factory _$RoomCopyWith(_Room value, $Res Function(_Room) _then) = __$RoomCopyWithImpl;
@override @useResult
$Res call({
 String id, String floorId, String code, RoomCategory category, List<RoomCorner> polygon, String? label, String? landmarkId, String? wingId, List<RoomCorner> centreline
});




}
/// @nodoc
class __$RoomCopyWithImpl<$Res>
    implements _$RoomCopyWith<$Res> {
  __$RoomCopyWithImpl(this._self, this._then);

  final _Room _self;
  final $Res Function(_Room) _then;

/// Create a copy of Room
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? floorId = null,Object? code = null,Object? category = null,Object? polygon = null,Object? label = freezed,Object? landmarkId = freezed,Object? wingId = freezed,Object? centreline = null,}) {
  return _then(_Room(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,floorId: null == floorId ? _self.floorId : floorId // ignore: cast_nullable_to_non_nullable
as String,code: null == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as String,category: null == category ? _self.category : category // ignore: cast_nullable_to_non_nullable
as RoomCategory,polygon: null == polygon ? _self._polygon : polygon // ignore: cast_nullable_to_non_nullable
as List<RoomCorner>,label: freezed == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String?,landmarkId: freezed == landmarkId ? _self.landmarkId : landmarkId // ignore: cast_nullable_to_non_nullable
as String?,wingId: freezed == wingId ? _self.wingId : wingId // ignore: cast_nullable_to_non_nullable
as String?,centreline: null == centreline ? _self._centreline : centreline // ignore: cast_nullable_to_non_nullable
as List<RoomCorner>,
  ));
}


}


/// @nodoc
mixin _$Opening {

 String get id; String get roomAId;/// Null for an exterior door. Routing skips these; the renderer draws them,
/// because "this is the way out" is worth seeing.
 String? get roomBId;/// Midpoint of the opening in the wall, in metres.
 RoomCorner get at; double get widthM;/// False for an open archway. Changes the phrasing — "through the archway"
/// rather than "through the door" — and nothing else.
 bool get isDoor;
/// Create a copy of Opening
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$OpeningCopyWith<Opening> get copyWith => _$OpeningCopyWithImpl<Opening>(this as Opening, _$identity);

  /// Serializes this Opening to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Opening&&(identical(other.id, id) || other.id == id)&&(identical(other.roomAId, roomAId) || other.roomAId == roomAId)&&(identical(other.roomBId, roomBId) || other.roomBId == roomBId)&&(identical(other.at, at) || other.at == at)&&(identical(other.widthM, widthM) || other.widthM == widthM)&&(identical(other.isDoor, isDoor) || other.isDoor == isDoor));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,roomAId,roomBId,at,widthM,isDoor);

@override
String toString() {
  return 'Opening(id: $id, roomAId: $roomAId, roomBId: $roomBId, at: $at, widthM: $widthM, isDoor: $isDoor)';
}


}

/// @nodoc
abstract mixin class $OpeningCopyWith<$Res>  {
  factory $OpeningCopyWith(Opening value, $Res Function(Opening) _then) = _$OpeningCopyWithImpl;
@useResult
$Res call({
 String id, String roomAId, String? roomBId, RoomCorner at, double widthM, bool isDoor
});


$RoomCornerCopyWith<$Res> get at;

}
/// @nodoc
class _$OpeningCopyWithImpl<$Res>
    implements $OpeningCopyWith<$Res> {
  _$OpeningCopyWithImpl(this._self, this._then);

  final Opening _self;
  final $Res Function(Opening) _then;

/// Create a copy of Opening
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? roomAId = null,Object? roomBId = freezed,Object? at = null,Object? widthM = null,Object? isDoor = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,roomAId: null == roomAId ? _self.roomAId : roomAId // ignore: cast_nullable_to_non_nullable
as String,roomBId: freezed == roomBId ? _self.roomBId : roomBId // ignore: cast_nullable_to_non_nullable
as String?,at: null == at ? _self.at : at // ignore: cast_nullable_to_non_nullable
as RoomCorner,widthM: null == widthM ? _self.widthM : widthM // ignore: cast_nullable_to_non_nullable
as double,isDoor: null == isDoor ? _self.isDoor : isDoor // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}
/// Create a copy of Opening
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$RoomCornerCopyWith<$Res> get at {
  
  return $RoomCornerCopyWith<$Res>(_self.at, (value) {
    return _then(_self.copyWith(at: value));
  });
}
}


/// Adds pattern-matching-related methods to [Opening].
extension OpeningPatterns on Opening {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Opening value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Opening() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Opening value)  $default,){
final _that = this;
switch (_that) {
case _Opening():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Opening value)?  $default,){
final _that = this;
switch (_that) {
case _Opening() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String roomAId,  String? roomBId,  RoomCorner at,  double widthM,  bool isDoor)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Opening() when $default != null:
return $default(_that.id,_that.roomAId,_that.roomBId,_that.at,_that.widthM,_that.isDoor);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String roomAId,  String? roomBId,  RoomCorner at,  double widthM,  bool isDoor)  $default,) {final _that = this;
switch (_that) {
case _Opening():
return $default(_that.id,_that.roomAId,_that.roomBId,_that.at,_that.widthM,_that.isDoor);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String roomAId,  String? roomBId,  RoomCorner at,  double widthM,  bool isDoor)?  $default,) {final _that = this;
switch (_that) {
case _Opening() when $default != null:
return $default(_that.id,_that.roomAId,_that.roomBId,_that.at,_that.widthM,_that.isDoor);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _Opening extends Opening {
  const _Opening({required this.id, required this.roomAId, this.roomBId, required this.at, this.widthM = 0.9, this.isDoor = true}): super._();
  factory _Opening.fromJson(Map<String, dynamic> json) => _$OpeningFromJson(json);

@override final  String id;
@override final  String roomAId;
/// Null for an exterior door. Routing skips these; the renderer draws them,
/// because "this is the way out" is worth seeing.
@override final  String? roomBId;
/// Midpoint of the opening in the wall, in metres.
@override final  RoomCorner at;
@override@JsonKey() final  double widthM;
/// False for an open archway. Changes the phrasing — "through the archway"
/// rather than "through the door" — and nothing else.
@override@JsonKey() final  bool isDoor;

/// Create a copy of Opening
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$OpeningCopyWith<_Opening> get copyWith => __$OpeningCopyWithImpl<_Opening>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$OpeningToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Opening&&(identical(other.id, id) || other.id == id)&&(identical(other.roomAId, roomAId) || other.roomAId == roomAId)&&(identical(other.roomBId, roomBId) || other.roomBId == roomBId)&&(identical(other.at, at) || other.at == at)&&(identical(other.widthM, widthM) || other.widthM == widthM)&&(identical(other.isDoor, isDoor) || other.isDoor == isDoor));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,roomAId,roomBId,at,widthM,isDoor);

@override
String toString() {
  return 'Opening(id: $id, roomAId: $roomAId, roomBId: $roomBId, at: $at, widthM: $widthM, isDoor: $isDoor)';
}


}

/// @nodoc
abstract mixin class _$OpeningCopyWith<$Res> implements $OpeningCopyWith<$Res> {
  factory _$OpeningCopyWith(_Opening value, $Res Function(_Opening) _then) = __$OpeningCopyWithImpl;
@override @useResult
$Res call({
 String id, String roomAId, String? roomBId, RoomCorner at, double widthM, bool isDoor
});


@override $RoomCornerCopyWith<$Res> get at;

}
/// @nodoc
class __$OpeningCopyWithImpl<$Res>
    implements _$OpeningCopyWith<$Res> {
  __$OpeningCopyWithImpl(this._self, this._then);

  final _Opening _self;
  final $Res Function(_Opening) _then;

/// Create a copy of Opening
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? roomAId = null,Object? roomBId = freezed,Object? at = null,Object? widthM = null,Object? isDoor = null,}) {
  return _then(_Opening(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,roomAId: null == roomAId ? _self.roomAId : roomAId // ignore: cast_nullable_to_non_nullable
as String,roomBId: freezed == roomBId ? _self.roomBId : roomBId // ignore: cast_nullable_to_non_nullable
as String?,at: null == at ? _self.at : at // ignore: cast_nullable_to_non_nullable
as RoomCorner,widthM: null == widthM ? _self.widthM : widthM // ignore: cast_nullable_to_non_nullable
as double,isDoor: null == isDoor ? _self.isDoor : isDoor // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

/// Create a copy of Opening
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$RoomCornerCopyWith<$Res> get at {
  
  return $RoomCornerCopyWith<$Res>(_self.at, (value) {
    return _then(_self.copyWith(at: value));
  });
}
}


/// @nodoc
mixin _$RoomPlan {

 String get buildingId; String get floorId;/// Prefix for auto-allocated room codes, e.g. `'GF'`.
 String get codePrefix;/// Rooms **as captured**, before their wing's placement is applied.
///
/// Read [rooms] instead unless you are editing a wing's alignment. The
/// JSON key is still `rooms`, so plans saved before wings existed load
/// unchanged.
@JsonKey(name: 'rooms') List<Room> get storedRooms;@JsonKey(name: 'openings') List<Opening> get storedOpenings;/// Wing id → where that wing sits on the floor.
///
/// A wing is one capture session: one corridor and the rooms off it. Each
/// AR session starts with ARCore's origin wherever the phone happened to
/// be, so a second session's coordinates mean nothing relative to the
/// first — the placement here is what reconciles them.
///
/// Empty for a plan captured or traced in one go, which is why every
/// existing plan and every test carries on working: no wings means no
/// transform, and [rooms] returns exactly what was stored.
 Map<String, WingPlacement> get wings;/// Corridor id → how many doors the contributor counted on its walls.
///
/// The one number a mapper is asked to type, and the guard on the most
/// dangerous failure in the system — see [corridorIsComplete].
 Map<String, int> get declaredDoorCounts;/// How many metres one plan unit is, when anything knows.
///
/// Null for a plan traced off a photographed wall board, which is the
/// common case and costs nothing: A* compares edge lengths against each
/// other, so scaling every room by the same unknown constant picks exactly
/// the same route. Set for a plan captured in AR, where the coordinates
/// really are metres.
///
/// What it *does* change is speech. `RoomDirections` refuses to say "walk
/// twelve metres" from a plan whose units nobody has measured — a
/// confidently wrong number is worse in a blind user's ear than no number.
/// Same reasoning, and the same field, as [TracedPlan.metresPerUnit].
 double? get metresPerUnit;
/// Create a copy of RoomPlan
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RoomPlanCopyWith<RoomPlan> get copyWith => _$RoomPlanCopyWithImpl<RoomPlan>(this as RoomPlan, _$identity);

  /// Serializes this RoomPlan to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RoomPlan&&(identical(other.buildingId, buildingId) || other.buildingId == buildingId)&&(identical(other.floorId, floorId) || other.floorId == floorId)&&(identical(other.codePrefix, codePrefix) || other.codePrefix == codePrefix)&&const DeepCollectionEquality().equals(other.storedRooms, storedRooms)&&const DeepCollectionEquality().equals(other.storedOpenings, storedOpenings)&&const DeepCollectionEquality().equals(other.wings, wings)&&const DeepCollectionEquality().equals(other.declaredDoorCounts, declaredDoorCounts)&&(identical(other.metresPerUnit, metresPerUnit) || other.metresPerUnit == metresPerUnit));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,buildingId,floorId,codePrefix,const DeepCollectionEquality().hash(storedRooms),const DeepCollectionEquality().hash(storedOpenings),const DeepCollectionEquality().hash(wings),const DeepCollectionEquality().hash(declaredDoorCounts),metresPerUnit);

@override
String toString() {
  return 'RoomPlan(buildingId: $buildingId, floorId: $floorId, codePrefix: $codePrefix, storedRooms: $storedRooms, storedOpenings: $storedOpenings, wings: $wings, declaredDoorCounts: $declaredDoorCounts, metresPerUnit: $metresPerUnit)';
}


}

/// @nodoc
abstract mixin class $RoomPlanCopyWith<$Res>  {
  factory $RoomPlanCopyWith(RoomPlan value, $Res Function(RoomPlan) _then) = _$RoomPlanCopyWithImpl;
@useResult
$Res call({
 String buildingId, String floorId, String codePrefix,@JsonKey(name: 'rooms') List<Room> storedRooms,@JsonKey(name: 'openings') List<Opening> storedOpenings, Map<String, WingPlacement> wings, Map<String, int> declaredDoorCounts, double? metresPerUnit
});




}
/// @nodoc
class _$RoomPlanCopyWithImpl<$Res>
    implements $RoomPlanCopyWith<$Res> {
  _$RoomPlanCopyWithImpl(this._self, this._then);

  final RoomPlan _self;
  final $Res Function(RoomPlan) _then;

/// Create a copy of RoomPlan
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? buildingId = null,Object? floorId = null,Object? codePrefix = null,Object? storedRooms = null,Object? storedOpenings = null,Object? wings = null,Object? declaredDoorCounts = null,Object? metresPerUnit = freezed,}) {
  return _then(_self.copyWith(
buildingId: null == buildingId ? _self.buildingId : buildingId // ignore: cast_nullable_to_non_nullable
as String,floorId: null == floorId ? _self.floorId : floorId // ignore: cast_nullable_to_non_nullable
as String,codePrefix: null == codePrefix ? _self.codePrefix : codePrefix // ignore: cast_nullable_to_non_nullable
as String,storedRooms: null == storedRooms ? _self.storedRooms : storedRooms // ignore: cast_nullable_to_non_nullable
as List<Room>,storedOpenings: null == storedOpenings ? _self.storedOpenings : storedOpenings // ignore: cast_nullable_to_non_nullable
as List<Opening>,wings: null == wings ? _self.wings : wings // ignore: cast_nullable_to_non_nullable
as Map<String, WingPlacement>,declaredDoorCounts: null == declaredDoorCounts ? _self.declaredDoorCounts : declaredDoorCounts // ignore: cast_nullable_to_non_nullable
as Map<String, int>,metresPerUnit: freezed == metresPerUnit ? _self.metresPerUnit : metresPerUnit // ignore: cast_nullable_to_non_nullable
as double?,
  ));
}

}


/// Adds pattern-matching-related methods to [RoomPlan].
extension RoomPlanPatterns on RoomPlan {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _RoomPlan value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _RoomPlan() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _RoomPlan value)  $default,){
final _that = this;
switch (_that) {
case _RoomPlan():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _RoomPlan value)?  $default,){
final _that = this;
switch (_that) {
case _RoomPlan() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String buildingId,  String floorId,  String codePrefix, @JsonKey(name: 'rooms')  List<Room> storedRooms, @JsonKey(name: 'openings')  List<Opening> storedOpenings,  Map<String, WingPlacement> wings,  Map<String, int> declaredDoorCounts,  double? metresPerUnit)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _RoomPlan() when $default != null:
return $default(_that.buildingId,_that.floorId,_that.codePrefix,_that.storedRooms,_that.storedOpenings,_that.wings,_that.declaredDoorCounts,_that.metresPerUnit);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String buildingId,  String floorId,  String codePrefix, @JsonKey(name: 'rooms')  List<Room> storedRooms, @JsonKey(name: 'openings')  List<Opening> storedOpenings,  Map<String, WingPlacement> wings,  Map<String, int> declaredDoorCounts,  double? metresPerUnit)  $default,) {final _that = this;
switch (_that) {
case _RoomPlan():
return $default(_that.buildingId,_that.floorId,_that.codePrefix,_that.storedRooms,_that.storedOpenings,_that.wings,_that.declaredDoorCounts,_that.metresPerUnit);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String buildingId,  String floorId,  String codePrefix, @JsonKey(name: 'rooms')  List<Room> storedRooms, @JsonKey(name: 'openings')  List<Opening> storedOpenings,  Map<String, WingPlacement> wings,  Map<String, int> declaredDoorCounts,  double? metresPerUnit)?  $default,) {final _that = this;
switch (_that) {
case _RoomPlan() when $default != null:
return $default(_that.buildingId,_that.floorId,_that.codePrefix,_that.storedRooms,_that.storedOpenings,_that.wings,_that.declaredDoorCounts,_that.metresPerUnit);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _RoomPlan extends RoomPlan {
  const _RoomPlan({required this.buildingId, required this.floorId, required this.codePrefix, @JsonKey(name: 'rooms') final  List<Room> storedRooms = const <Room>[], @JsonKey(name: 'openings') final  List<Opening> storedOpenings = const <Opening>[], final  Map<String, WingPlacement> wings = const <String, WingPlacement>{}, final  Map<String, int> declaredDoorCounts = const <String, int>{}, this.metresPerUnit}): _storedRooms = storedRooms,_storedOpenings = storedOpenings,_wings = wings,_declaredDoorCounts = declaredDoorCounts,super._();
  factory _RoomPlan.fromJson(Map<String, dynamic> json) => _$RoomPlanFromJson(json);

@override final  String buildingId;
@override final  String floorId;
/// Prefix for auto-allocated room codes, e.g. `'GF'`.
@override final  String codePrefix;
/// Rooms **as captured**, before their wing's placement is applied.
///
/// Read [rooms] instead unless you are editing a wing's alignment. The
/// JSON key is still `rooms`, so plans saved before wings existed load
/// unchanged.
 final  List<Room> _storedRooms;
/// Rooms **as captured**, before their wing's placement is applied.
///
/// Read [rooms] instead unless you are editing a wing's alignment. The
/// JSON key is still `rooms`, so plans saved before wings existed load
/// unchanged.
@override@JsonKey(name: 'rooms') List<Room> get storedRooms {
  if (_storedRooms is EqualUnmodifiableListView) return _storedRooms;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_storedRooms);
}

 final  List<Opening> _storedOpenings;
@override@JsonKey(name: 'openings') List<Opening> get storedOpenings {
  if (_storedOpenings is EqualUnmodifiableListView) return _storedOpenings;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_storedOpenings);
}

/// Wing id → where that wing sits on the floor.
///
/// A wing is one capture session: one corridor and the rooms off it. Each
/// AR session starts with ARCore's origin wherever the phone happened to
/// be, so a second session's coordinates mean nothing relative to the
/// first — the placement here is what reconciles them.
///
/// Empty for a plan captured or traced in one go, which is why every
/// existing plan and every test carries on working: no wings means no
/// transform, and [rooms] returns exactly what was stored.
 final  Map<String, WingPlacement> _wings;
/// Wing id → where that wing sits on the floor.
///
/// A wing is one capture session: one corridor and the rooms off it. Each
/// AR session starts with ARCore's origin wherever the phone happened to
/// be, so a second session's coordinates mean nothing relative to the
/// first — the placement here is what reconciles them.
///
/// Empty for a plan captured or traced in one go, which is why every
/// existing plan and every test carries on working: no wings means no
/// transform, and [rooms] returns exactly what was stored.
@override@JsonKey() Map<String, WingPlacement> get wings {
  if (_wings is EqualUnmodifiableMapView) return _wings;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_wings);
}

/// Corridor id → how many doors the contributor counted on its walls.
///
/// The one number a mapper is asked to type, and the guard on the most
/// dangerous failure in the system — see [corridorIsComplete].
 final  Map<String, int> _declaredDoorCounts;
/// Corridor id → how many doors the contributor counted on its walls.
///
/// The one number a mapper is asked to type, and the guard on the most
/// dangerous failure in the system — see [corridorIsComplete].
@override@JsonKey() Map<String, int> get declaredDoorCounts {
  if (_declaredDoorCounts is EqualUnmodifiableMapView) return _declaredDoorCounts;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_declaredDoorCounts);
}

/// How many metres one plan unit is, when anything knows.
///
/// Null for a plan traced off a photographed wall board, which is the
/// common case and costs nothing: A* compares edge lengths against each
/// other, so scaling every room by the same unknown constant picks exactly
/// the same route. Set for a plan captured in AR, where the coordinates
/// really are metres.
///
/// What it *does* change is speech. `RoomDirections` refuses to say "walk
/// twelve metres" from a plan whose units nobody has measured — a
/// confidently wrong number is worse in a blind user's ear than no number.
/// Same reasoning, and the same field, as [TracedPlan.metresPerUnit].
@override final  double? metresPerUnit;

/// Create a copy of RoomPlan
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RoomPlanCopyWith<_RoomPlan> get copyWith => __$RoomPlanCopyWithImpl<_RoomPlan>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$RoomPlanToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _RoomPlan&&(identical(other.buildingId, buildingId) || other.buildingId == buildingId)&&(identical(other.floorId, floorId) || other.floorId == floorId)&&(identical(other.codePrefix, codePrefix) || other.codePrefix == codePrefix)&&const DeepCollectionEquality().equals(other._storedRooms, _storedRooms)&&const DeepCollectionEquality().equals(other._storedOpenings, _storedOpenings)&&const DeepCollectionEquality().equals(other._wings, _wings)&&const DeepCollectionEquality().equals(other._declaredDoorCounts, _declaredDoorCounts)&&(identical(other.metresPerUnit, metresPerUnit) || other.metresPerUnit == metresPerUnit));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,buildingId,floorId,codePrefix,const DeepCollectionEquality().hash(_storedRooms),const DeepCollectionEquality().hash(_storedOpenings),const DeepCollectionEquality().hash(_wings),const DeepCollectionEquality().hash(_declaredDoorCounts),metresPerUnit);

@override
String toString() {
  return 'RoomPlan(buildingId: $buildingId, floorId: $floorId, codePrefix: $codePrefix, storedRooms: $storedRooms, storedOpenings: $storedOpenings, wings: $wings, declaredDoorCounts: $declaredDoorCounts, metresPerUnit: $metresPerUnit)';
}


}

/// @nodoc
abstract mixin class _$RoomPlanCopyWith<$Res> implements $RoomPlanCopyWith<$Res> {
  factory _$RoomPlanCopyWith(_RoomPlan value, $Res Function(_RoomPlan) _then) = __$RoomPlanCopyWithImpl;
@override @useResult
$Res call({
 String buildingId, String floorId, String codePrefix,@JsonKey(name: 'rooms') List<Room> storedRooms,@JsonKey(name: 'openings') List<Opening> storedOpenings, Map<String, WingPlacement> wings, Map<String, int> declaredDoorCounts, double? metresPerUnit
});




}
/// @nodoc
class __$RoomPlanCopyWithImpl<$Res>
    implements _$RoomPlanCopyWith<$Res> {
  __$RoomPlanCopyWithImpl(this._self, this._then);

  final _RoomPlan _self;
  final $Res Function(_RoomPlan) _then;

/// Create a copy of RoomPlan
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? buildingId = null,Object? floorId = null,Object? codePrefix = null,Object? storedRooms = null,Object? storedOpenings = null,Object? wings = null,Object? declaredDoorCounts = null,Object? metresPerUnit = freezed,}) {
  return _then(_RoomPlan(
buildingId: null == buildingId ? _self.buildingId : buildingId // ignore: cast_nullable_to_non_nullable
as String,floorId: null == floorId ? _self.floorId : floorId // ignore: cast_nullable_to_non_nullable
as String,codePrefix: null == codePrefix ? _self.codePrefix : codePrefix // ignore: cast_nullable_to_non_nullable
as String,storedRooms: null == storedRooms ? _self._storedRooms : storedRooms // ignore: cast_nullable_to_non_nullable
as List<Room>,storedOpenings: null == storedOpenings ? _self._storedOpenings : storedOpenings // ignore: cast_nullable_to_non_nullable
as List<Opening>,wings: null == wings ? _self._wings : wings // ignore: cast_nullable_to_non_nullable
as Map<String, WingPlacement>,declaredDoorCounts: null == declaredDoorCounts ? _self._declaredDoorCounts : declaredDoorCounts // ignore: cast_nullable_to_non_nullable
as Map<String, int>,metresPerUnit: freezed == metresPerUnit ? _self.metresPerUnit : metresPerUnit // ignore: cast_nullable_to_non_nullable
as double?,
  ));
}


}

// dart format on
