// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'building.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$Building {

 String get id; String get name; String get area; int get floorsCount; int get mappers; int get mappedPercent; double get distanceKm; String get category; String get glyph; String get updatedLabel;
/// Create a copy of Building
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BuildingCopyWith<Building> get copyWith => _$BuildingCopyWithImpl<Building>(this as Building, _$identity);

  /// Serializes this Building to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Building&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.area, area) || other.area == area)&&(identical(other.floorsCount, floorsCount) || other.floorsCount == floorsCount)&&(identical(other.mappers, mappers) || other.mappers == mappers)&&(identical(other.mappedPercent, mappedPercent) || other.mappedPercent == mappedPercent)&&(identical(other.distanceKm, distanceKm) || other.distanceKm == distanceKm)&&(identical(other.category, category) || other.category == category)&&(identical(other.glyph, glyph) || other.glyph == glyph)&&(identical(other.updatedLabel, updatedLabel) || other.updatedLabel == updatedLabel));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,name,area,floorsCount,mappers,mappedPercent,distanceKm,category,glyph,updatedLabel);

@override
String toString() {
  return 'Building(id: $id, name: $name, area: $area, floorsCount: $floorsCount, mappers: $mappers, mappedPercent: $mappedPercent, distanceKm: $distanceKm, category: $category, glyph: $glyph, updatedLabel: $updatedLabel)';
}


}

/// @nodoc
abstract mixin class $BuildingCopyWith<$Res>  {
  factory $BuildingCopyWith(Building value, $Res Function(Building) _then) = _$BuildingCopyWithImpl;
@useResult
$Res call({
 String id, String name, String area, int floorsCount, int mappers, int mappedPercent, double distanceKm, String category, String glyph, String updatedLabel
});




}
/// @nodoc
class _$BuildingCopyWithImpl<$Res>
    implements $BuildingCopyWith<$Res> {
  _$BuildingCopyWithImpl(this._self, this._then);

  final Building _self;
  final $Res Function(Building) _then;

/// Create a copy of Building
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,Object? area = null,Object? floorsCount = null,Object? mappers = null,Object? mappedPercent = null,Object? distanceKm = null,Object? category = null,Object? glyph = null,Object? updatedLabel = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,area: null == area ? _self.area : area // ignore: cast_nullable_to_non_nullable
as String,floorsCount: null == floorsCount ? _self.floorsCount : floorsCount // ignore: cast_nullable_to_non_nullable
as int,mappers: null == mappers ? _self.mappers : mappers // ignore: cast_nullable_to_non_nullable
as int,mappedPercent: null == mappedPercent ? _self.mappedPercent : mappedPercent // ignore: cast_nullable_to_non_nullable
as int,distanceKm: null == distanceKm ? _self.distanceKm : distanceKm // ignore: cast_nullable_to_non_nullable
as double,category: null == category ? _self.category : category // ignore: cast_nullable_to_non_nullable
as String,glyph: null == glyph ? _self.glyph : glyph // ignore: cast_nullable_to_non_nullable
as String,updatedLabel: null == updatedLabel ? _self.updatedLabel : updatedLabel // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [Building].
extension BuildingPatterns on Building {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Building value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Building() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Building value)  $default,){
final _that = this;
switch (_that) {
case _Building():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Building value)?  $default,){
final _that = this;
switch (_that) {
case _Building() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String name,  String area,  int floorsCount,  int mappers,  int mappedPercent,  double distanceKm,  String category,  String glyph,  String updatedLabel)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Building() when $default != null:
return $default(_that.id,_that.name,_that.area,_that.floorsCount,_that.mappers,_that.mappedPercent,_that.distanceKm,_that.category,_that.glyph,_that.updatedLabel);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String name,  String area,  int floorsCount,  int mappers,  int mappedPercent,  double distanceKm,  String category,  String glyph,  String updatedLabel)  $default,) {final _that = this;
switch (_that) {
case _Building():
return $default(_that.id,_that.name,_that.area,_that.floorsCount,_that.mappers,_that.mappedPercent,_that.distanceKm,_that.category,_that.glyph,_that.updatedLabel);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String name,  String area,  int floorsCount,  int mappers,  int mappedPercent,  double distanceKm,  String category,  String glyph,  String updatedLabel)?  $default,) {final _that = this;
switch (_that) {
case _Building() when $default != null:
return $default(_that.id,_that.name,_that.area,_that.floorsCount,_that.mappers,_that.mappedPercent,_that.distanceKm,_that.category,_that.glyph,_that.updatedLabel);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _Building implements Building {
  const _Building({required this.id, required this.name, required this.area, required this.floorsCount, required this.mappers, required this.mappedPercent, required this.distanceKm, required this.category, this.glyph = 'building', this.updatedLabel = 'updated recently'});
  factory _Building.fromJson(Map<String, dynamic> json) => _$BuildingFromJson(json);

@override final  String id;
@override final  String name;
@override final  String area;
@override final  int floorsCount;
@override final  int mappers;
@override final  int mappedPercent;
@override final  double distanceKm;
@override final  String category;
@override@JsonKey() final  String glyph;
@override@JsonKey() final  String updatedLabel;

/// Create a copy of Building
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$BuildingCopyWith<_Building> get copyWith => __$BuildingCopyWithImpl<_Building>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$BuildingToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Building&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.area, area) || other.area == area)&&(identical(other.floorsCount, floorsCount) || other.floorsCount == floorsCount)&&(identical(other.mappers, mappers) || other.mappers == mappers)&&(identical(other.mappedPercent, mappedPercent) || other.mappedPercent == mappedPercent)&&(identical(other.distanceKm, distanceKm) || other.distanceKm == distanceKm)&&(identical(other.category, category) || other.category == category)&&(identical(other.glyph, glyph) || other.glyph == glyph)&&(identical(other.updatedLabel, updatedLabel) || other.updatedLabel == updatedLabel));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,name,area,floorsCount,mappers,mappedPercent,distanceKm,category,glyph,updatedLabel);

@override
String toString() {
  return 'Building(id: $id, name: $name, area: $area, floorsCount: $floorsCount, mappers: $mappers, mappedPercent: $mappedPercent, distanceKm: $distanceKm, category: $category, glyph: $glyph, updatedLabel: $updatedLabel)';
}


}

/// @nodoc
abstract mixin class _$BuildingCopyWith<$Res> implements $BuildingCopyWith<$Res> {
  factory _$BuildingCopyWith(_Building value, $Res Function(_Building) _then) = __$BuildingCopyWithImpl;
@override @useResult
$Res call({
 String id, String name, String area, int floorsCount, int mappers, int mappedPercent, double distanceKm, String category, String glyph, String updatedLabel
});




}
/// @nodoc
class __$BuildingCopyWithImpl<$Res>
    implements _$BuildingCopyWith<$Res> {
  __$BuildingCopyWithImpl(this._self, this._then);

  final _Building _self;
  final $Res Function(_Building) _then;

/// Create a copy of Building
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? area = null,Object? floorsCount = null,Object? mappers = null,Object? mappedPercent = null,Object? distanceKm = null,Object? category = null,Object? glyph = null,Object? updatedLabel = null,}) {
  return _then(_Building(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,area: null == area ? _self.area : area // ignore: cast_nullable_to_non_nullable
as String,floorsCount: null == floorsCount ? _self.floorsCount : floorsCount // ignore: cast_nullable_to_non_nullable
as int,mappers: null == mappers ? _self.mappers : mappers // ignore: cast_nullable_to_non_nullable
as int,mappedPercent: null == mappedPercent ? _self.mappedPercent : mappedPercent // ignore: cast_nullable_to_non_nullable
as int,distanceKm: null == distanceKm ? _self.distanceKm : distanceKm // ignore: cast_nullable_to_non_nullable
as double,category: null == category ? _self.category : category // ignore: cast_nullable_to_non_nullable
as String,glyph: null == glyph ? _self.glyph : glyph // ignore: cast_nullable_to_non_nullable
as String,updatedLabel: null == updatedLabel ? _self.updatedLabel : updatedLabel // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}


/// @nodoc
mixin _$BuildingFloor {

 String get label; List<Room> get rooms;/// The `floors` row this came from, matching `Landmark.floorId`.
///
/// Every landmark belongs to a floor, so recording a route cannot start
/// without one. It is also what lets the floor plan name its planes:
/// without it the switcher on the navigation screen reads "b3f1c2…"
/// instead of "Floor 2".
///
/// Defaulted rather than required so a floor list cached by an older build
/// still decodes — an empty id means "cached before floors were
/// identified", and capture asks the contributor to reload rather than
/// uploading landmarks attached to nothing.
 String get id;
/// Create a copy of BuildingFloor
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BuildingFloorCopyWith<BuildingFloor> get copyWith => _$BuildingFloorCopyWithImpl<BuildingFloor>(this as BuildingFloor, _$identity);

  /// Serializes this BuildingFloor to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BuildingFloor&&(identical(other.label, label) || other.label == label)&&const DeepCollectionEquality().equals(other.rooms, rooms)&&(identical(other.id, id) || other.id == id));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,label,const DeepCollectionEquality().hash(rooms),id);

@override
String toString() {
  return 'BuildingFloor(label: $label, rooms: $rooms, id: $id)';
}


}

/// @nodoc
abstract mixin class $BuildingFloorCopyWith<$Res>  {
  factory $BuildingFloorCopyWith(BuildingFloor value, $Res Function(BuildingFloor) _then) = _$BuildingFloorCopyWithImpl;
@useResult
$Res call({
 String label, List<Room> rooms, String id
});




}
/// @nodoc
class _$BuildingFloorCopyWithImpl<$Res>
    implements $BuildingFloorCopyWith<$Res> {
  _$BuildingFloorCopyWithImpl(this._self, this._then);

  final BuildingFloor _self;
  final $Res Function(BuildingFloor) _then;

/// Create a copy of BuildingFloor
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? label = null,Object? rooms = null,Object? id = null,}) {
  return _then(_self.copyWith(
label: null == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String,rooms: null == rooms ? _self.rooms : rooms // ignore: cast_nullable_to_non_nullable
as List<Room>,id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [BuildingFloor].
extension BuildingFloorPatterns on BuildingFloor {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _BuildingFloor value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _BuildingFloor() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _BuildingFloor value)  $default,){
final _that = this;
switch (_that) {
case _BuildingFloor():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _BuildingFloor value)?  $default,){
final _that = this;
switch (_that) {
case _BuildingFloor() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String label,  List<Room> rooms,  String id)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _BuildingFloor() when $default != null:
return $default(_that.label,_that.rooms,_that.id);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String label,  List<Room> rooms,  String id)  $default,) {final _that = this;
switch (_that) {
case _BuildingFloor():
return $default(_that.label,_that.rooms,_that.id);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String label,  List<Room> rooms,  String id)?  $default,) {final _that = this;
switch (_that) {
case _BuildingFloor() when $default != null:
return $default(_that.label,_that.rooms,_that.id);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _BuildingFloor implements BuildingFloor {
  const _BuildingFloor({required this.label, required final  List<Room> rooms, this.id = ''}): _rooms = rooms;
  factory _BuildingFloor.fromJson(Map<String, dynamic> json) => _$BuildingFloorFromJson(json);

@override final  String label;
 final  List<Room> _rooms;
@override List<Room> get rooms {
  if (_rooms is EqualUnmodifiableListView) return _rooms;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_rooms);
}

/// The `floors` row this came from, matching `Landmark.floorId`.
///
/// Every landmark belongs to a floor, so recording a route cannot start
/// without one. It is also what lets the floor plan name its planes:
/// without it the switcher on the navigation screen reads "b3f1c2…"
/// instead of "Floor 2".
///
/// Defaulted rather than required so a floor list cached by an older build
/// still decodes — an empty id means "cached before floors were
/// identified", and capture asks the contributor to reload rather than
/// uploading landmarks attached to nothing.
@override@JsonKey() final  String id;

/// Create a copy of BuildingFloor
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$BuildingFloorCopyWith<_BuildingFloor> get copyWith => __$BuildingFloorCopyWithImpl<_BuildingFloor>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$BuildingFloorToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _BuildingFloor&&(identical(other.label, label) || other.label == label)&&const DeepCollectionEquality().equals(other._rooms, _rooms)&&(identical(other.id, id) || other.id == id));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,label,const DeepCollectionEquality().hash(_rooms),id);

@override
String toString() {
  return 'BuildingFloor(label: $label, rooms: $rooms, id: $id)';
}


}

/// @nodoc
abstract mixin class _$BuildingFloorCopyWith<$Res> implements $BuildingFloorCopyWith<$Res> {
  factory _$BuildingFloorCopyWith(_BuildingFloor value, $Res Function(_BuildingFloor) _then) = __$BuildingFloorCopyWithImpl;
@override @useResult
$Res call({
 String label, List<Room> rooms, String id
});




}
/// @nodoc
class __$BuildingFloorCopyWithImpl<$Res>
    implements _$BuildingFloorCopyWith<$Res> {
  __$BuildingFloorCopyWithImpl(this._self, this._then);

  final _BuildingFloor _self;
  final $Res Function(_BuildingFloor) _then;

/// Create a copy of BuildingFloor
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? label = null,Object? rooms = null,Object? id = null,}) {
  return _then(_BuildingFloor(
label: null == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String,rooms: null == rooms ? _self._rooms : rooms // ignore: cast_nullable_to_non_nullable
as List<Room>,id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}


/// @nodoc
mixin _$Room {

 String get id; String get name; int get distanceM; String get kind;
/// Create a copy of Room
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RoomCopyWith<Room> get copyWith => _$RoomCopyWithImpl<Room>(this as Room, _$identity);

  /// Serializes this Room to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Room&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.distanceM, distanceM) || other.distanceM == distanceM)&&(identical(other.kind, kind) || other.kind == kind));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,name,distanceM,kind);

@override
String toString() {
  return 'Room(id: $id, name: $name, distanceM: $distanceM, kind: $kind)';
}


}

/// @nodoc
abstract mixin class $RoomCopyWith<$Res>  {
  factory $RoomCopyWith(Room value, $Res Function(Room) _then) = _$RoomCopyWithImpl;
@useResult
$Res call({
 String id, String name, int distanceM, String kind
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
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,Object? distanceM = null,Object? kind = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,distanceM: null == distanceM ? _self.distanceM : distanceM // ignore: cast_nullable_to_non_nullable
as int,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as String,
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String name,  int distanceM,  String kind)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Room() when $default != null:
return $default(_that.id,_that.name,_that.distanceM,_that.kind);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String name,  int distanceM,  String kind)  $default,) {final _that = this;
switch (_that) {
case _Room():
return $default(_that.id,_that.name,_that.distanceM,_that.kind);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String name,  int distanceM,  String kind)?  $default,) {final _that = this;
switch (_that) {
case _Room() when $default != null:
return $default(_that.id,_that.name,_that.distanceM,_that.kind);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _Room implements Room {
  const _Room({required this.id, required this.name, required this.distanceM, this.kind = 'room'});
  factory _Room.fromJson(Map<String, dynamic> json) => _$RoomFromJson(json);

@override final  String id;
@override final  String name;
@override final  int distanceM;
@override@JsonKey() final  String kind;

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
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Room&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.distanceM, distanceM) || other.distanceM == distanceM)&&(identical(other.kind, kind) || other.kind == kind));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,name,distanceM,kind);

@override
String toString() {
  return 'Room(id: $id, name: $name, distanceM: $distanceM, kind: $kind)';
}


}

/// @nodoc
abstract mixin class _$RoomCopyWith<$Res> implements $RoomCopyWith<$Res> {
  factory _$RoomCopyWith(_Room value, $Res Function(_Room) _then) = __$RoomCopyWithImpl;
@override @useResult
$Res call({
 String id, String name, int distanceM, String kind
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
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? distanceM = null,Object? kind = null,}) {
  return _then(_Room(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,distanceM: null == distanceM ? _self.distanceM : distanceM // ignore: cast_nullable_to_non_nullable
as int,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
