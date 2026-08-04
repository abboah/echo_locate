// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'route_draft.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$DraftLandmark {

/// Client-side label, unique within this draft.
 String get ref; String get floorId; LandmarkKind get kind; String get labelText; String get displayName; List<String> get aliases; String? get roomId;
/// Create a copy of DraftLandmark
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DraftLandmarkCopyWith<DraftLandmark> get copyWith => _$DraftLandmarkCopyWithImpl<DraftLandmark>(this as DraftLandmark, _$identity);

  /// Serializes this DraftLandmark to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DraftLandmark&&(identical(other.ref, ref) || other.ref == ref)&&(identical(other.floorId, floorId) || other.floorId == floorId)&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.labelText, labelText) || other.labelText == labelText)&&(identical(other.displayName, displayName) || other.displayName == displayName)&&const DeepCollectionEquality().equals(other.aliases, aliases)&&(identical(other.roomId, roomId) || other.roomId == roomId));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,ref,floorId,kind,labelText,displayName,const DeepCollectionEquality().hash(aliases),roomId);

@override
String toString() {
  return 'DraftLandmark(ref: $ref, floorId: $floorId, kind: $kind, labelText: $labelText, displayName: $displayName, aliases: $aliases, roomId: $roomId)';
}


}

/// @nodoc
abstract mixin class $DraftLandmarkCopyWith<$Res>  {
  factory $DraftLandmarkCopyWith(DraftLandmark value, $Res Function(DraftLandmark) _then) = _$DraftLandmarkCopyWithImpl;
@useResult
$Res call({
 String ref, String floorId, LandmarkKind kind, String labelText, String displayName, List<String> aliases, String? roomId
});




}
/// @nodoc
class _$DraftLandmarkCopyWithImpl<$Res>
    implements $DraftLandmarkCopyWith<$Res> {
  _$DraftLandmarkCopyWithImpl(this._self, this._then);

  final DraftLandmark _self;
  final $Res Function(DraftLandmark) _then;

/// Create a copy of DraftLandmark
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? ref = null,Object? floorId = null,Object? kind = null,Object? labelText = null,Object? displayName = null,Object? aliases = null,Object? roomId = freezed,}) {
  return _then(_self.copyWith(
ref: null == ref ? _self.ref : ref // ignore: cast_nullable_to_non_nullable
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


/// Adds pattern-matching-related methods to [DraftLandmark].
extension DraftLandmarkPatterns on DraftLandmark {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _DraftLandmark value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _DraftLandmark() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _DraftLandmark value)  $default,){
final _that = this;
switch (_that) {
case _DraftLandmark():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _DraftLandmark value)?  $default,){
final _that = this;
switch (_that) {
case _DraftLandmark() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String ref,  String floorId,  LandmarkKind kind,  String labelText,  String displayName,  List<String> aliases,  String? roomId)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _DraftLandmark() when $default != null:
return $default(_that.ref,_that.floorId,_that.kind,_that.labelText,_that.displayName,_that.aliases,_that.roomId);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String ref,  String floorId,  LandmarkKind kind,  String labelText,  String displayName,  List<String> aliases,  String? roomId)  $default,) {final _that = this;
switch (_that) {
case _DraftLandmark():
return $default(_that.ref,_that.floorId,_that.kind,_that.labelText,_that.displayName,_that.aliases,_that.roomId);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String ref,  String floorId,  LandmarkKind kind,  String labelText,  String displayName,  List<String> aliases,  String? roomId)?  $default,) {final _that = this;
switch (_that) {
case _DraftLandmark() when $default != null:
return $default(_that.ref,_that.floorId,_that.kind,_that.labelText,_that.displayName,_that.aliases,_that.roomId);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _DraftLandmark implements DraftLandmark {
  const _DraftLandmark({required this.ref, required this.floorId, required this.kind, required this.labelText, required this.displayName, final  List<String> aliases = const <String>[], this.roomId}): _aliases = aliases;
  factory _DraftLandmark.fromJson(Map<String, dynamic> json) => _$DraftLandmarkFromJson(json);

/// Client-side label, unique within this draft.
@override final  String ref;
@override final  String floorId;
@override final  LandmarkKind kind;
@override final  String labelText;
@override final  String displayName;
 final  List<String> _aliases;
@override@JsonKey() List<String> get aliases {
  if (_aliases is EqualUnmodifiableListView) return _aliases;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_aliases);
}

@override final  String? roomId;

/// Create a copy of DraftLandmark
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$DraftLandmarkCopyWith<_DraftLandmark> get copyWith => __$DraftLandmarkCopyWithImpl<_DraftLandmark>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$DraftLandmarkToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _DraftLandmark&&(identical(other.ref, ref) || other.ref == ref)&&(identical(other.floorId, floorId) || other.floorId == floorId)&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.labelText, labelText) || other.labelText == labelText)&&(identical(other.displayName, displayName) || other.displayName == displayName)&&const DeepCollectionEquality().equals(other._aliases, _aliases)&&(identical(other.roomId, roomId) || other.roomId == roomId));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,ref,floorId,kind,labelText,displayName,const DeepCollectionEquality().hash(_aliases),roomId);

@override
String toString() {
  return 'DraftLandmark(ref: $ref, floorId: $floorId, kind: $kind, labelText: $labelText, displayName: $displayName, aliases: $aliases, roomId: $roomId)';
}


}

/// @nodoc
abstract mixin class _$DraftLandmarkCopyWith<$Res> implements $DraftLandmarkCopyWith<$Res> {
  factory _$DraftLandmarkCopyWith(_DraftLandmark value, $Res Function(_DraftLandmark) _then) = __$DraftLandmarkCopyWithImpl;
@override @useResult
$Res call({
 String ref, String floorId, LandmarkKind kind, String labelText, String displayName, List<String> aliases, String? roomId
});




}
/// @nodoc
class __$DraftLandmarkCopyWithImpl<$Res>
    implements _$DraftLandmarkCopyWith<$Res> {
  __$DraftLandmarkCopyWithImpl(this._self, this._then);

  final _DraftLandmark _self;
  final $Res Function(_DraftLandmark) _then;

/// Create a copy of DraftLandmark
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? ref = null,Object? floorId = null,Object? kind = null,Object? labelText = null,Object? displayName = null,Object? aliases = null,Object? roomId = freezed,}) {
  return _then(_DraftLandmark(
ref: null == ref ? _self.ref : ref // ignore: cast_nullable_to_non_nullable
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


/// @nodoc
mixin _$DraftStep {

 int get seq;@JsonKey(name: 'from') String get fromRef;@JsonKey(name: 'to') String get toRef; String get instruction; double get distanceM; int get turnDeg; int? get stepsRecorded;
/// Create a copy of DraftStep
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DraftStepCopyWith<DraftStep> get copyWith => _$DraftStepCopyWithImpl<DraftStep>(this as DraftStep, _$identity);

  /// Serializes this DraftStep to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DraftStep&&(identical(other.seq, seq) || other.seq == seq)&&(identical(other.fromRef, fromRef) || other.fromRef == fromRef)&&(identical(other.toRef, toRef) || other.toRef == toRef)&&(identical(other.instruction, instruction) || other.instruction == instruction)&&(identical(other.distanceM, distanceM) || other.distanceM == distanceM)&&(identical(other.turnDeg, turnDeg) || other.turnDeg == turnDeg)&&(identical(other.stepsRecorded, stepsRecorded) || other.stepsRecorded == stepsRecorded));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,seq,fromRef,toRef,instruction,distanceM,turnDeg,stepsRecorded);

@override
String toString() {
  return 'DraftStep(seq: $seq, fromRef: $fromRef, toRef: $toRef, instruction: $instruction, distanceM: $distanceM, turnDeg: $turnDeg, stepsRecorded: $stepsRecorded)';
}


}

/// @nodoc
abstract mixin class $DraftStepCopyWith<$Res>  {
  factory $DraftStepCopyWith(DraftStep value, $Res Function(DraftStep) _then) = _$DraftStepCopyWithImpl;
@useResult
$Res call({
 int seq,@JsonKey(name: 'from') String fromRef,@JsonKey(name: 'to') String toRef, String instruction, double distanceM, int turnDeg, int? stepsRecorded
});




}
/// @nodoc
class _$DraftStepCopyWithImpl<$Res>
    implements $DraftStepCopyWith<$Res> {
  _$DraftStepCopyWithImpl(this._self, this._then);

  final DraftStep _self;
  final $Res Function(DraftStep) _then;

/// Create a copy of DraftStep
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? seq = null,Object? fromRef = null,Object? toRef = null,Object? instruction = null,Object? distanceM = null,Object? turnDeg = null,Object? stepsRecorded = freezed,}) {
  return _then(_self.copyWith(
seq: null == seq ? _self.seq : seq // ignore: cast_nullable_to_non_nullable
as int,fromRef: null == fromRef ? _self.fromRef : fromRef // ignore: cast_nullable_to_non_nullable
as String,toRef: null == toRef ? _self.toRef : toRef // ignore: cast_nullable_to_non_nullable
as String,instruction: null == instruction ? _self.instruction : instruction // ignore: cast_nullable_to_non_nullable
as String,distanceM: null == distanceM ? _self.distanceM : distanceM // ignore: cast_nullable_to_non_nullable
as double,turnDeg: null == turnDeg ? _self.turnDeg : turnDeg // ignore: cast_nullable_to_non_nullable
as int,stepsRecorded: freezed == stepsRecorded ? _self.stepsRecorded : stepsRecorded // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

}


/// Adds pattern-matching-related methods to [DraftStep].
extension DraftStepPatterns on DraftStep {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _DraftStep value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _DraftStep() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _DraftStep value)  $default,){
final _that = this;
switch (_that) {
case _DraftStep():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _DraftStep value)?  $default,){
final _that = this;
switch (_that) {
case _DraftStep() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int seq, @JsonKey(name: 'from')  String fromRef, @JsonKey(name: 'to')  String toRef,  String instruction,  double distanceM,  int turnDeg,  int? stepsRecorded)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _DraftStep() when $default != null:
return $default(_that.seq,_that.fromRef,_that.toRef,_that.instruction,_that.distanceM,_that.turnDeg,_that.stepsRecorded);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int seq, @JsonKey(name: 'from')  String fromRef, @JsonKey(name: 'to')  String toRef,  String instruction,  double distanceM,  int turnDeg,  int? stepsRecorded)  $default,) {final _that = this;
switch (_that) {
case _DraftStep():
return $default(_that.seq,_that.fromRef,_that.toRef,_that.instruction,_that.distanceM,_that.turnDeg,_that.stepsRecorded);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int seq, @JsonKey(name: 'from')  String fromRef, @JsonKey(name: 'to')  String toRef,  String instruction,  double distanceM,  int turnDeg,  int? stepsRecorded)?  $default,) {final _that = this;
switch (_that) {
case _DraftStep() when $default != null:
return $default(_that.seq,_that.fromRef,_that.toRef,_that.instruction,_that.distanceM,_that.turnDeg,_that.stepsRecorded);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _DraftStep implements DraftStep {
  const _DraftStep({required this.seq, @JsonKey(name: 'from') required this.fromRef, @JsonKey(name: 'to') required this.toRef, required this.instruction, required this.distanceM, this.turnDeg = 0, this.stepsRecorded});
  factory _DraftStep.fromJson(Map<String, dynamic> json) => _$DraftStepFromJson(json);

@override final  int seq;
@override@JsonKey(name: 'from') final  String fromRef;
@override@JsonKey(name: 'to') final  String toRef;
@override final  String instruction;
@override final  double distanceM;
@override@JsonKey() final  int turnDeg;
@override final  int? stepsRecorded;

/// Create a copy of DraftStep
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$DraftStepCopyWith<_DraftStep> get copyWith => __$DraftStepCopyWithImpl<_DraftStep>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$DraftStepToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _DraftStep&&(identical(other.seq, seq) || other.seq == seq)&&(identical(other.fromRef, fromRef) || other.fromRef == fromRef)&&(identical(other.toRef, toRef) || other.toRef == toRef)&&(identical(other.instruction, instruction) || other.instruction == instruction)&&(identical(other.distanceM, distanceM) || other.distanceM == distanceM)&&(identical(other.turnDeg, turnDeg) || other.turnDeg == turnDeg)&&(identical(other.stepsRecorded, stepsRecorded) || other.stepsRecorded == stepsRecorded));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,seq,fromRef,toRef,instruction,distanceM,turnDeg,stepsRecorded);

@override
String toString() {
  return 'DraftStep(seq: $seq, fromRef: $fromRef, toRef: $toRef, instruction: $instruction, distanceM: $distanceM, turnDeg: $turnDeg, stepsRecorded: $stepsRecorded)';
}


}

/// @nodoc
abstract mixin class _$DraftStepCopyWith<$Res> implements $DraftStepCopyWith<$Res> {
  factory _$DraftStepCopyWith(_DraftStep value, $Res Function(_DraftStep) _then) = __$DraftStepCopyWithImpl;
@override @useResult
$Res call({
 int seq,@JsonKey(name: 'from') String fromRef,@JsonKey(name: 'to') String toRef, String instruction, double distanceM, int turnDeg, int? stepsRecorded
});




}
/// @nodoc
class __$DraftStepCopyWithImpl<$Res>
    implements _$DraftStepCopyWith<$Res> {
  __$DraftStepCopyWithImpl(this._self, this._then);

  final _DraftStep _self;
  final $Res Function(_DraftStep) _then;

/// Create a copy of DraftStep
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? seq = null,Object? fromRef = null,Object? toRef = null,Object? instruction = null,Object? distanceM = null,Object? turnDeg = null,Object? stepsRecorded = freezed,}) {
  return _then(_DraftStep(
seq: null == seq ? _self.seq : seq // ignore: cast_nullable_to_non_nullable
as int,fromRef: null == fromRef ? _self.fromRef : fromRef // ignore: cast_nullable_to_non_nullable
as String,toRef: null == toRef ? _self.toRef : toRef // ignore: cast_nullable_to_non_nullable
as String,instruction: null == instruction ? _self.instruction : instruction // ignore: cast_nullable_to_non_nullable
as String,distanceM: null == distanceM ? _self.distanceM : distanceM // ignore: cast_nullable_to_non_nullable
as double,turnDeg: null == turnDeg ? _self.turnDeg : turnDeg // ignore: cast_nullable_to_non_nullable
as int,stepsRecorded: freezed == stepsRecorded ? _self.stepsRecorded : stepsRecorded // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}


/// @nodoc
mixin _$RouteDraft {

 String get buildingId; String get destinationRoomId; List<DraftLandmark> get landmarks; List<DraftStep> get steps;
/// Create a copy of RouteDraft
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RouteDraftCopyWith<RouteDraft> get copyWith => _$RouteDraftCopyWithImpl<RouteDraft>(this as RouteDraft, _$identity);

  /// Serializes this RouteDraft to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RouteDraft&&(identical(other.buildingId, buildingId) || other.buildingId == buildingId)&&(identical(other.destinationRoomId, destinationRoomId) || other.destinationRoomId == destinationRoomId)&&const DeepCollectionEquality().equals(other.landmarks, landmarks)&&const DeepCollectionEquality().equals(other.steps, steps));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,buildingId,destinationRoomId,const DeepCollectionEquality().hash(landmarks),const DeepCollectionEquality().hash(steps));

@override
String toString() {
  return 'RouteDraft(buildingId: $buildingId, destinationRoomId: $destinationRoomId, landmarks: $landmarks, steps: $steps)';
}


}

/// @nodoc
abstract mixin class $RouteDraftCopyWith<$Res>  {
  factory $RouteDraftCopyWith(RouteDraft value, $Res Function(RouteDraft) _then) = _$RouteDraftCopyWithImpl;
@useResult
$Res call({
 String buildingId, String destinationRoomId, List<DraftLandmark> landmarks, List<DraftStep> steps
});




}
/// @nodoc
class _$RouteDraftCopyWithImpl<$Res>
    implements $RouteDraftCopyWith<$Res> {
  _$RouteDraftCopyWithImpl(this._self, this._then);

  final RouteDraft _self;
  final $Res Function(RouteDraft) _then;

/// Create a copy of RouteDraft
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? buildingId = null,Object? destinationRoomId = null,Object? landmarks = null,Object? steps = null,}) {
  return _then(_self.copyWith(
buildingId: null == buildingId ? _self.buildingId : buildingId // ignore: cast_nullable_to_non_nullable
as String,destinationRoomId: null == destinationRoomId ? _self.destinationRoomId : destinationRoomId // ignore: cast_nullable_to_non_nullable
as String,landmarks: null == landmarks ? _self.landmarks : landmarks // ignore: cast_nullable_to_non_nullable
as List<DraftLandmark>,steps: null == steps ? _self.steps : steps // ignore: cast_nullable_to_non_nullable
as List<DraftStep>,
  ));
}

}


/// Adds pattern-matching-related methods to [RouteDraft].
extension RouteDraftPatterns on RouteDraft {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _RouteDraft value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _RouteDraft() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _RouteDraft value)  $default,){
final _that = this;
switch (_that) {
case _RouteDraft():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _RouteDraft value)?  $default,){
final _that = this;
switch (_that) {
case _RouteDraft() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String buildingId,  String destinationRoomId,  List<DraftLandmark> landmarks,  List<DraftStep> steps)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _RouteDraft() when $default != null:
return $default(_that.buildingId,_that.destinationRoomId,_that.landmarks,_that.steps);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String buildingId,  String destinationRoomId,  List<DraftLandmark> landmarks,  List<DraftStep> steps)  $default,) {final _that = this;
switch (_that) {
case _RouteDraft():
return $default(_that.buildingId,_that.destinationRoomId,_that.landmarks,_that.steps);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String buildingId,  String destinationRoomId,  List<DraftLandmark> landmarks,  List<DraftStep> steps)?  $default,) {final _that = this;
switch (_that) {
case _RouteDraft() when $default != null:
return $default(_that.buildingId,_that.destinationRoomId,_that.landmarks,_that.steps);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _RouteDraft extends RouteDraft {
  const _RouteDraft({required this.buildingId, required this.destinationRoomId, required final  List<DraftLandmark> landmarks, required final  List<DraftStep> steps}): _landmarks = landmarks,_steps = steps,super._();
  factory _RouteDraft.fromJson(Map<String, dynamic> json) => _$RouteDraftFromJson(json);

@override final  String buildingId;
@override final  String destinationRoomId;
 final  List<DraftLandmark> _landmarks;
@override List<DraftLandmark> get landmarks {
  if (_landmarks is EqualUnmodifiableListView) return _landmarks;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_landmarks);
}

 final  List<DraftStep> _steps;
@override List<DraftStep> get steps {
  if (_steps is EqualUnmodifiableListView) return _steps;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_steps);
}


/// Create a copy of RouteDraft
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RouteDraftCopyWith<_RouteDraft> get copyWith => __$RouteDraftCopyWithImpl<_RouteDraft>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$RouteDraftToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _RouteDraft&&(identical(other.buildingId, buildingId) || other.buildingId == buildingId)&&(identical(other.destinationRoomId, destinationRoomId) || other.destinationRoomId == destinationRoomId)&&const DeepCollectionEquality().equals(other._landmarks, _landmarks)&&const DeepCollectionEquality().equals(other._steps, _steps));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,buildingId,destinationRoomId,const DeepCollectionEquality().hash(_landmarks),const DeepCollectionEquality().hash(_steps));

@override
String toString() {
  return 'RouteDraft(buildingId: $buildingId, destinationRoomId: $destinationRoomId, landmarks: $landmarks, steps: $steps)';
}


}

/// @nodoc
abstract mixin class _$RouteDraftCopyWith<$Res> implements $RouteDraftCopyWith<$Res> {
  factory _$RouteDraftCopyWith(_RouteDraft value, $Res Function(_RouteDraft) _then) = __$RouteDraftCopyWithImpl;
@override @useResult
$Res call({
 String buildingId, String destinationRoomId, List<DraftLandmark> landmarks, List<DraftStep> steps
});




}
/// @nodoc
class __$RouteDraftCopyWithImpl<$Res>
    implements _$RouteDraftCopyWith<$Res> {
  __$RouteDraftCopyWithImpl(this._self, this._then);

  final _RouteDraft _self;
  final $Res Function(_RouteDraft) _then;

/// Create a copy of RouteDraft
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? buildingId = null,Object? destinationRoomId = null,Object? landmarks = null,Object? steps = null,}) {
  return _then(_RouteDraft(
buildingId: null == buildingId ? _self.buildingId : buildingId // ignore: cast_nullable_to_non_nullable
as String,destinationRoomId: null == destinationRoomId ? _self.destinationRoomId : destinationRoomId // ignore: cast_nullable_to_non_nullable
as String,landmarks: null == landmarks ? _self._landmarks : landmarks // ignore: cast_nullable_to_non_nullable
as List<DraftLandmark>,steps: null == steps ? _self._steps : steps // ignore: cast_nullable_to_non_nullable
as List<DraftStep>,
  ));
}


}

// dart format on
