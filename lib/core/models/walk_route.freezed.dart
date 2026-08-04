// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'walk_route.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$RouteStep {

 int get seq; String get fromLandmarkId; String get toLandmarkId;/// Spoken verbatim: 'straight past the help desk'.
 String get instruction;/// Canonical length in metres.
///
/// Steps are never the stored unit: a 78cm stride and a 65cm stride do not
/// share a count, so the contributor's steps are converted to metres on
/// capture and back into the *current user's* steps on playback.
 double get distanceM;/// Turn taken at the START of this leg: 0 straight, -90 left, +90 right,
/// ±135 sharp. Tapped by the contributor, not sensed — an indoor compass
/// reading costs magnetic error and buys nothing.
 int get turnDeg;/// The contributor's raw count. Evidence for the evaluation chapter only;
/// never used for guidance.
 int? get stepsRecorded;
/// Create a copy of RouteStep
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RouteStepCopyWith<RouteStep> get copyWith => _$RouteStepCopyWithImpl<RouteStep>(this as RouteStep, _$identity);

  /// Serializes this RouteStep to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RouteStep&&(identical(other.seq, seq) || other.seq == seq)&&(identical(other.fromLandmarkId, fromLandmarkId) || other.fromLandmarkId == fromLandmarkId)&&(identical(other.toLandmarkId, toLandmarkId) || other.toLandmarkId == toLandmarkId)&&(identical(other.instruction, instruction) || other.instruction == instruction)&&(identical(other.distanceM, distanceM) || other.distanceM == distanceM)&&(identical(other.turnDeg, turnDeg) || other.turnDeg == turnDeg)&&(identical(other.stepsRecorded, stepsRecorded) || other.stepsRecorded == stepsRecorded));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,seq,fromLandmarkId,toLandmarkId,instruction,distanceM,turnDeg,stepsRecorded);

@override
String toString() {
  return 'RouteStep(seq: $seq, fromLandmarkId: $fromLandmarkId, toLandmarkId: $toLandmarkId, instruction: $instruction, distanceM: $distanceM, turnDeg: $turnDeg, stepsRecorded: $stepsRecorded)';
}


}

/// @nodoc
abstract mixin class $RouteStepCopyWith<$Res>  {
  factory $RouteStepCopyWith(RouteStep value, $Res Function(RouteStep) _then) = _$RouteStepCopyWithImpl;
@useResult
$Res call({
 int seq, String fromLandmarkId, String toLandmarkId, String instruction, double distanceM, int turnDeg, int? stepsRecorded
});




}
/// @nodoc
class _$RouteStepCopyWithImpl<$Res>
    implements $RouteStepCopyWith<$Res> {
  _$RouteStepCopyWithImpl(this._self, this._then);

  final RouteStep _self;
  final $Res Function(RouteStep) _then;

/// Create a copy of RouteStep
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? seq = null,Object? fromLandmarkId = null,Object? toLandmarkId = null,Object? instruction = null,Object? distanceM = null,Object? turnDeg = null,Object? stepsRecorded = freezed,}) {
  return _then(_self.copyWith(
seq: null == seq ? _self.seq : seq // ignore: cast_nullable_to_non_nullable
as int,fromLandmarkId: null == fromLandmarkId ? _self.fromLandmarkId : fromLandmarkId // ignore: cast_nullable_to_non_nullable
as String,toLandmarkId: null == toLandmarkId ? _self.toLandmarkId : toLandmarkId // ignore: cast_nullable_to_non_nullable
as String,instruction: null == instruction ? _self.instruction : instruction // ignore: cast_nullable_to_non_nullable
as String,distanceM: null == distanceM ? _self.distanceM : distanceM // ignore: cast_nullable_to_non_nullable
as double,turnDeg: null == turnDeg ? _self.turnDeg : turnDeg // ignore: cast_nullable_to_non_nullable
as int,stepsRecorded: freezed == stepsRecorded ? _self.stepsRecorded : stepsRecorded // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

}


/// Adds pattern-matching-related methods to [RouteStep].
extension RouteStepPatterns on RouteStep {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _RouteStep value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _RouteStep() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _RouteStep value)  $default,){
final _that = this;
switch (_that) {
case _RouteStep():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _RouteStep value)?  $default,){
final _that = this;
switch (_that) {
case _RouteStep() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int seq,  String fromLandmarkId,  String toLandmarkId,  String instruction,  double distanceM,  int turnDeg,  int? stepsRecorded)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _RouteStep() when $default != null:
return $default(_that.seq,_that.fromLandmarkId,_that.toLandmarkId,_that.instruction,_that.distanceM,_that.turnDeg,_that.stepsRecorded);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int seq,  String fromLandmarkId,  String toLandmarkId,  String instruction,  double distanceM,  int turnDeg,  int? stepsRecorded)  $default,) {final _that = this;
switch (_that) {
case _RouteStep():
return $default(_that.seq,_that.fromLandmarkId,_that.toLandmarkId,_that.instruction,_that.distanceM,_that.turnDeg,_that.stepsRecorded);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int seq,  String fromLandmarkId,  String toLandmarkId,  String instruction,  double distanceM,  int turnDeg,  int? stepsRecorded)?  $default,) {final _that = this;
switch (_that) {
case _RouteStep() when $default != null:
return $default(_that.seq,_that.fromLandmarkId,_that.toLandmarkId,_that.instruction,_that.distanceM,_that.turnDeg,_that.stepsRecorded);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _RouteStep extends RouteStep {
  const _RouteStep({required this.seq, required this.fromLandmarkId, required this.toLandmarkId, required this.instruction, required this.distanceM, this.turnDeg = 0, this.stepsRecorded}): super._();
  factory _RouteStep.fromJson(Map<String, dynamic> json) => _$RouteStepFromJson(json);

@override final  int seq;
@override final  String fromLandmarkId;
@override final  String toLandmarkId;
/// Spoken verbatim: 'straight past the help desk'.
@override final  String instruction;
/// Canonical length in metres.
///
/// Steps are never the stored unit: a 78cm stride and a 65cm stride do not
/// share a count, so the contributor's steps are converted to metres on
/// capture and back into the *current user's* steps on playback.
@override final  double distanceM;
/// Turn taken at the START of this leg: 0 straight, -90 left, +90 right,
/// ±135 sharp. Tapped by the contributor, not sensed — an indoor compass
/// reading costs magnetic error and buys nothing.
@override@JsonKey() final  int turnDeg;
/// The contributor's raw count. Evidence for the evaluation chapter only;
/// never used for guidance.
@override final  int? stepsRecorded;

/// Create a copy of RouteStep
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RouteStepCopyWith<_RouteStep> get copyWith => __$RouteStepCopyWithImpl<_RouteStep>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$RouteStepToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _RouteStep&&(identical(other.seq, seq) || other.seq == seq)&&(identical(other.fromLandmarkId, fromLandmarkId) || other.fromLandmarkId == fromLandmarkId)&&(identical(other.toLandmarkId, toLandmarkId) || other.toLandmarkId == toLandmarkId)&&(identical(other.instruction, instruction) || other.instruction == instruction)&&(identical(other.distanceM, distanceM) || other.distanceM == distanceM)&&(identical(other.turnDeg, turnDeg) || other.turnDeg == turnDeg)&&(identical(other.stepsRecorded, stepsRecorded) || other.stepsRecorded == stepsRecorded));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,seq,fromLandmarkId,toLandmarkId,instruction,distanceM,turnDeg,stepsRecorded);

@override
String toString() {
  return 'RouteStep(seq: $seq, fromLandmarkId: $fromLandmarkId, toLandmarkId: $toLandmarkId, instruction: $instruction, distanceM: $distanceM, turnDeg: $turnDeg, stepsRecorded: $stepsRecorded)';
}


}

/// @nodoc
abstract mixin class _$RouteStepCopyWith<$Res> implements $RouteStepCopyWith<$Res> {
  factory _$RouteStepCopyWith(_RouteStep value, $Res Function(_RouteStep) _then) = __$RouteStepCopyWithImpl;
@override @useResult
$Res call({
 int seq, String fromLandmarkId, String toLandmarkId, String instruction, double distanceM, int turnDeg, int? stepsRecorded
});




}
/// @nodoc
class __$RouteStepCopyWithImpl<$Res>
    implements _$RouteStepCopyWith<$Res> {
  __$RouteStepCopyWithImpl(this._self, this._then);

  final _RouteStep _self;
  final $Res Function(_RouteStep) _then;

/// Create a copy of RouteStep
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? seq = null,Object? fromLandmarkId = null,Object? toLandmarkId = null,Object? instruction = null,Object? distanceM = null,Object? turnDeg = null,Object? stepsRecorded = freezed,}) {
  return _then(_RouteStep(
seq: null == seq ? _self.seq : seq // ignore: cast_nullable_to_non_nullable
as int,fromLandmarkId: null == fromLandmarkId ? _self.fromLandmarkId : fromLandmarkId // ignore: cast_nullable_to_non_nullable
as String,toLandmarkId: null == toLandmarkId ? _self.toLandmarkId : toLandmarkId // ignore: cast_nullable_to_non_nullable
as String,instruction: null == instruction ? _self.instruction : instruction // ignore: cast_nullable_to_non_nullable
as String,distanceM: null == distanceM ? _self.distanceM : distanceM // ignore: cast_nullable_to_non_nullable
as double,turnDeg: null == turnDeg ? _self.turnDeg : turnDeg // ignore: cast_nullable_to_non_nullable
as int,stepsRecorded: freezed == stepsRecorded ? _self.stepsRecorded : stepsRecorded // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}


/// @nodoc
mixin _$WalkRoute {

 String get id; String get buildingId; String get startLandmarkId; String get destinationRoomId; List<RouteStep> get steps; double get totalDistanceM;/// Times another user completed this route successfully — a crude quality
/// signal when several recordings compete for the same destination.
 int get verifiedCount;
/// Create a copy of WalkRoute
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$WalkRouteCopyWith<WalkRoute> get copyWith => _$WalkRouteCopyWithImpl<WalkRoute>(this as WalkRoute, _$identity);

  /// Serializes this WalkRoute to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is WalkRoute&&(identical(other.id, id) || other.id == id)&&(identical(other.buildingId, buildingId) || other.buildingId == buildingId)&&(identical(other.startLandmarkId, startLandmarkId) || other.startLandmarkId == startLandmarkId)&&(identical(other.destinationRoomId, destinationRoomId) || other.destinationRoomId == destinationRoomId)&&const DeepCollectionEquality().equals(other.steps, steps)&&(identical(other.totalDistanceM, totalDistanceM) || other.totalDistanceM == totalDistanceM)&&(identical(other.verifiedCount, verifiedCount) || other.verifiedCount == verifiedCount));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,buildingId,startLandmarkId,destinationRoomId,const DeepCollectionEquality().hash(steps),totalDistanceM,verifiedCount);

@override
String toString() {
  return 'WalkRoute(id: $id, buildingId: $buildingId, startLandmarkId: $startLandmarkId, destinationRoomId: $destinationRoomId, steps: $steps, totalDistanceM: $totalDistanceM, verifiedCount: $verifiedCount)';
}


}

/// @nodoc
abstract mixin class $WalkRouteCopyWith<$Res>  {
  factory $WalkRouteCopyWith(WalkRoute value, $Res Function(WalkRoute) _then) = _$WalkRouteCopyWithImpl;
@useResult
$Res call({
 String id, String buildingId, String startLandmarkId, String destinationRoomId, List<RouteStep> steps, double totalDistanceM, int verifiedCount
});




}
/// @nodoc
class _$WalkRouteCopyWithImpl<$Res>
    implements $WalkRouteCopyWith<$Res> {
  _$WalkRouteCopyWithImpl(this._self, this._then);

  final WalkRoute _self;
  final $Res Function(WalkRoute) _then;

/// Create a copy of WalkRoute
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? buildingId = null,Object? startLandmarkId = null,Object? destinationRoomId = null,Object? steps = null,Object? totalDistanceM = null,Object? verifiedCount = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,buildingId: null == buildingId ? _self.buildingId : buildingId // ignore: cast_nullable_to_non_nullable
as String,startLandmarkId: null == startLandmarkId ? _self.startLandmarkId : startLandmarkId // ignore: cast_nullable_to_non_nullable
as String,destinationRoomId: null == destinationRoomId ? _self.destinationRoomId : destinationRoomId // ignore: cast_nullable_to_non_nullable
as String,steps: null == steps ? _self.steps : steps // ignore: cast_nullable_to_non_nullable
as List<RouteStep>,totalDistanceM: null == totalDistanceM ? _self.totalDistanceM : totalDistanceM // ignore: cast_nullable_to_non_nullable
as double,verifiedCount: null == verifiedCount ? _self.verifiedCount : verifiedCount // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [WalkRoute].
extension WalkRoutePatterns on WalkRoute {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _WalkRoute value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _WalkRoute() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _WalkRoute value)  $default,){
final _that = this;
switch (_that) {
case _WalkRoute():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _WalkRoute value)?  $default,){
final _that = this;
switch (_that) {
case _WalkRoute() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String buildingId,  String startLandmarkId,  String destinationRoomId,  List<RouteStep> steps,  double totalDistanceM,  int verifiedCount)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _WalkRoute() when $default != null:
return $default(_that.id,_that.buildingId,_that.startLandmarkId,_that.destinationRoomId,_that.steps,_that.totalDistanceM,_that.verifiedCount);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String buildingId,  String startLandmarkId,  String destinationRoomId,  List<RouteStep> steps,  double totalDistanceM,  int verifiedCount)  $default,) {final _that = this;
switch (_that) {
case _WalkRoute():
return $default(_that.id,_that.buildingId,_that.startLandmarkId,_that.destinationRoomId,_that.steps,_that.totalDistanceM,_that.verifiedCount);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String buildingId,  String startLandmarkId,  String destinationRoomId,  List<RouteStep> steps,  double totalDistanceM,  int verifiedCount)?  $default,) {final _that = this;
switch (_that) {
case _WalkRoute() when $default != null:
return $default(_that.id,_that.buildingId,_that.startLandmarkId,_that.destinationRoomId,_that.steps,_that.totalDistanceM,_that.verifiedCount);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _WalkRoute extends WalkRoute {
  const _WalkRoute({required this.id, required this.buildingId, required this.startLandmarkId, required this.destinationRoomId, required final  List<RouteStep> steps, this.totalDistanceM = 0, this.verifiedCount = 0}): _steps = steps,super._();
  factory _WalkRoute.fromJson(Map<String, dynamic> json) => _$WalkRouteFromJson(json);

@override final  String id;
@override final  String buildingId;
@override final  String startLandmarkId;
@override final  String destinationRoomId;
 final  List<RouteStep> _steps;
@override List<RouteStep> get steps {
  if (_steps is EqualUnmodifiableListView) return _steps;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_steps);
}

@override@JsonKey() final  double totalDistanceM;
/// Times another user completed this route successfully — a crude quality
/// signal when several recordings compete for the same destination.
@override@JsonKey() final  int verifiedCount;

/// Create a copy of WalkRoute
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$WalkRouteCopyWith<_WalkRoute> get copyWith => __$WalkRouteCopyWithImpl<_WalkRoute>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$WalkRouteToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _WalkRoute&&(identical(other.id, id) || other.id == id)&&(identical(other.buildingId, buildingId) || other.buildingId == buildingId)&&(identical(other.startLandmarkId, startLandmarkId) || other.startLandmarkId == startLandmarkId)&&(identical(other.destinationRoomId, destinationRoomId) || other.destinationRoomId == destinationRoomId)&&const DeepCollectionEquality().equals(other._steps, _steps)&&(identical(other.totalDistanceM, totalDistanceM) || other.totalDistanceM == totalDistanceM)&&(identical(other.verifiedCount, verifiedCount) || other.verifiedCount == verifiedCount));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,buildingId,startLandmarkId,destinationRoomId,const DeepCollectionEquality().hash(_steps),totalDistanceM,verifiedCount);

@override
String toString() {
  return 'WalkRoute(id: $id, buildingId: $buildingId, startLandmarkId: $startLandmarkId, destinationRoomId: $destinationRoomId, steps: $steps, totalDistanceM: $totalDistanceM, verifiedCount: $verifiedCount)';
}


}

/// @nodoc
abstract mixin class _$WalkRouteCopyWith<$Res> implements $WalkRouteCopyWith<$Res> {
  factory _$WalkRouteCopyWith(_WalkRoute value, $Res Function(_WalkRoute) _then) = __$WalkRouteCopyWithImpl;
@override @useResult
$Res call({
 String id, String buildingId, String startLandmarkId, String destinationRoomId, List<RouteStep> steps, double totalDistanceM, int verifiedCount
});




}
/// @nodoc
class __$WalkRouteCopyWithImpl<$Res>
    implements _$WalkRouteCopyWith<$Res> {
  __$WalkRouteCopyWithImpl(this._self, this._then);

  final _WalkRoute _self;
  final $Res Function(_WalkRoute) _then;

/// Create a copy of WalkRoute
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? buildingId = null,Object? startLandmarkId = null,Object? destinationRoomId = null,Object? steps = null,Object? totalDistanceM = null,Object? verifiedCount = null,}) {
  return _then(_WalkRoute(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,buildingId: null == buildingId ? _self.buildingId : buildingId // ignore: cast_nullable_to_non_nullable
as String,startLandmarkId: null == startLandmarkId ? _self.startLandmarkId : startLandmarkId // ignore: cast_nullable_to_non_nullable
as String,destinationRoomId: null == destinationRoomId ? _self.destinationRoomId : destinationRoomId // ignore: cast_nullable_to_non_nullable
as String,steps: null == steps ? _self._steps : steps // ignore: cast_nullable_to_non_nullable
as List<RouteStep>,totalDistanceM: null == totalDistanceM ? _self.totalDistanceM : totalDistanceM // ignore: cast_nullable_to_non_nullable
as double,verifiedCount: null == verifiedCount ? _self.verifiedCount : verifiedCount // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

// dart format on
