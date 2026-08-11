// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'traced_plan.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$TracedNode {

/// Identifies this node within the plan. Client-side while tracing ('n1'),
/// rewritten to the real landmark id once the plan is saved, so
/// [FloorGraph.fromPlan] builds the same graph before and after a round
/// trip through the repository.
 String get ref;/// East of the plan's origin, in plan units.
///
/// Plan units, not metres: see [TracedPlan.metresPerUnit] for why a traced
/// plan is unitless and why that costs nothing.
 double get x;/// North of the plan's origin, in plan units.
 double get y;/// Which floor this node sits on. Held per node rather than per plan so a
/// building traced floor by floor is still one graph: the stairwell node on
/// the ground floor and the landing node above it are joined by an ordinary
/// edge, and A* climbs it like any other corridor.
 String get floorId; LandmarkKind get kind;/// What OCR must read to confirm arrival here — printed on the plan and,
/// crucially, on the door itself.
 String get labelText; String get displayName; List<String> get aliases; String? get roomId;
/// Create a copy of TracedNode
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TracedNodeCopyWith<TracedNode> get copyWith => _$TracedNodeCopyWithImpl<TracedNode>(this as TracedNode, _$identity);

  /// Serializes this TracedNode to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TracedNode&&(identical(other.ref, ref) || other.ref == ref)&&(identical(other.x, x) || other.x == x)&&(identical(other.y, y) || other.y == y)&&(identical(other.floorId, floorId) || other.floorId == floorId)&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.labelText, labelText) || other.labelText == labelText)&&(identical(other.displayName, displayName) || other.displayName == displayName)&&const DeepCollectionEquality().equals(other.aliases, aliases)&&(identical(other.roomId, roomId) || other.roomId == roomId));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,ref,x,y,floorId,kind,labelText,displayName,const DeepCollectionEquality().hash(aliases),roomId);

@override
String toString() {
  return 'TracedNode(ref: $ref, x: $x, y: $y, floorId: $floorId, kind: $kind, labelText: $labelText, displayName: $displayName, aliases: $aliases, roomId: $roomId)';
}


}

/// @nodoc
abstract mixin class $TracedNodeCopyWith<$Res>  {
  factory $TracedNodeCopyWith(TracedNode value, $Res Function(TracedNode) _then) = _$TracedNodeCopyWithImpl;
@useResult
$Res call({
 String ref, double x, double y, String floorId, LandmarkKind kind, String labelText, String displayName, List<String> aliases, String? roomId
});




}
/// @nodoc
class _$TracedNodeCopyWithImpl<$Res>
    implements $TracedNodeCopyWith<$Res> {
  _$TracedNodeCopyWithImpl(this._self, this._then);

  final TracedNode _self;
  final $Res Function(TracedNode) _then;

/// Create a copy of TracedNode
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? ref = null,Object? x = null,Object? y = null,Object? floorId = null,Object? kind = null,Object? labelText = null,Object? displayName = null,Object? aliases = null,Object? roomId = freezed,}) {
  return _then(_self.copyWith(
ref: null == ref ? _self.ref : ref // ignore: cast_nullable_to_non_nullable
as String,x: null == x ? _self.x : x // ignore: cast_nullable_to_non_nullable
as double,y: null == y ? _self.y : y // ignore: cast_nullable_to_non_nullable
as double,floorId: null == floorId ? _self.floorId : floorId // ignore: cast_nullable_to_non_nullable
as String,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as LandmarkKind,labelText: null == labelText ? _self.labelText : labelText // ignore: cast_nullable_to_non_nullable
as String,displayName: null == displayName ? _self.displayName : displayName // ignore: cast_nullable_to_non_nullable
as String,aliases: null == aliases ? _self.aliases : aliases // ignore: cast_nullable_to_non_nullable
as List<String>,roomId: freezed == roomId ? _self.roomId : roomId // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [TracedNode].
extension TracedNodePatterns on TracedNode {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _TracedNode value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _TracedNode() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _TracedNode value)  $default,){
final _that = this;
switch (_that) {
case _TracedNode():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _TracedNode value)?  $default,){
final _that = this;
switch (_that) {
case _TracedNode() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String ref,  double x,  double y,  String floorId,  LandmarkKind kind,  String labelText,  String displayName,  List<String> aliases,  String? roomId)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _TracedNode() when $default != null:
return $default(_that.ref,_that.x,_that.y,_that.floorId,_that.kind,_that.labelText,_that.displayName,_that.aliases,_that.roomId);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String ref,  double x,  double y,  String floorId,  LandmarkKind kind,  String labelText,  String displayName,  List<String> aliases,  String? roomId)  $default,) {final _that = this;
switch (_that) {
case _TracedNode():
return $default(_that.ref,_that.x,_that.y,_that.floorId,_that.kind,_that.labelText,_that.displayName,_that.aliases,_that.roomId);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String ref,  double x,  double y,  String floorId,  LandmarkKind kind,  String labelText,  String displayName,  List<String> aliases,  String? roomId)?  $default,) {final _that = this;
switch (_that) {
case _TracedNode() when $default != null:
return $default(_that.ref,_that.x,_that.y,_that.floorId,_that.kind,_that.labelText,_that.displayName,_that.aliases,_that.roomId);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _TracedNode extends TracedNode {
  const _TracedNode({required this.ref, required this.x, required this.y, required this.floorId, required this.kind, required this.labelText, required this.displayName, final  List<String> aliases = const <String>[], this.roomId}): _aliases = aliases,super._();
  factory _TracedNode.fromJson(Map<String, dynamic> json) => _$TracedNodeFromJson(json);

/// Identifies this node within the plan. Client-side while tracing ('n1'),
/// rewritten to the real landmark id once the plan is saved, so
/// [FloorGraph.fromPlan] builds the same graph before and after a round
/// trip through the repository.
@override final  String ref;
/// East of the plan's origin, in plan units.
///
/// Plan units, not metres: see [TracedPlan.metresPerUnit] for why a traced
/// plan is unitless and why that costs nothing.
@override final  double x;
/// North of the plan's origin, in plan units.
@override final  double y;
/// Which floor this node sits on. Held per node rather than per plan so a
/// building traced floor by floor is still one graph: the stairwell node on
/// the ground floor and the landing node above it are joined by an ordinary
/// edge, and A* climbs it like any other corridor.
@override final  String floorId;
@override final  LandmarkKind kind;
/// What OCR must read to confirm arrival here — printed on the plan and,
/// crucially, on the door itself.
@override final  String labelText;
@override final  String displayName;
 final  List<String> _aliases;
@override@JsonKey() List<String> get aliases {
  if (_aliases is EqualUnmodifiableListView) return _aliases;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_aliases);
}

@override final  String? roomId;

/// Create a copy of TracedNode
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$TracedNodeCopyWith<_TracedNode> get copyWith => __$TracedNodeCopyWithImpl<_TracedNode>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$TracedNodeToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _TracedNode&&(identical(other.ref, ref) || other.ref == ref)&&(identical(other.x, x) || other.x == x)&&(identical(other.y, y) || other.y == y)&&(identical(other.floorId, floorId) || other.floorId == floorId)&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.labelText, labelText) || other.labelText == labelText)&&(identical(other.displayName, displayName) || other.displayName == displayName)&&const DeepCollectionEquality().equals(other._aliases, _aliases)&&(identical(other.roomId, roomId) || other.roomId == roomId));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,ref,x,y,floorId,kind,labelText,displayName,const DeepCollectionEquality().hash(_aliases),roomId);

@override
String toString() {
  return 'TracedNode(ref: $ref, x: $x, y: $y, floorId: $floorId, kind: $kind, labelText: $labelText, displayName: $displayName, aliases: $aliases, roomId: $roomId)';
}


}

/// @nodoc
abstract mixin class _$TracedNodeCopyWith<$Res> implements $TracedNodeCopyWith<$Res> {
  factory _$TracedNodeCopyWith(_TracedNode value, $Res Function(_TracedNode) _then) = __$TracedNodeCopyWithImpl;
@override @useResult
$Res call({
 String ref, double x, double y, String floorId, LandmarkKind kind, String labelText, String displayName, List<String> aliases, String? roomId
});




}
/// @nodoc
class __$TracedNodeCopyWithImpl<$Res>
    implements _$TracedNodeCopyWith<$Res> {
  __$TracedNodeCopyWithImpl(this._self, this._then);

  final _TracedNode _self;
  final $Res Function(_TracedNode) _then;

/// Create a copy of TracedNode
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? ref = null,Object? x = null,Object? y = null,Object? floorId = null,Object? kind = null,Object? labelText = null,Object? displayName = null,Object? aliases = null,Object? roomId = freezed,}) {
  return _then(_TracedNode(
ref: null == ref ? _self.ref : ref // ignore: cast_nullable_to_non_nullable
as String,x: null == x ? _self.x : x // ignore: cast_nullable_to_non_nullable
as double,y: null == y ? _self.y : y // ignore: cast_nullable_to_non_nullable
as double,floorId: null == floorId ? _self.floorId : floorId // ignore: cast_nullable_to_non_nullable
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
mixin _$TracedEdge {

 String get fromRef; String get toRef;
/// Create a copy of TracedEdge
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TracedEdgeCopyWith<TracedEdge> get copyWith => _$TracedEdgeCopyWithImpl<TracedEdge>(this as TracedEdge, _$identity);

  /// Serializes this TracedEdge to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TracedEdge&&(identical(other.fromRef, fromRef) || other.fromRef == fromRef)&&(identical(other.toRef, toRef) || other.toRef == toRef));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,fromRef,toRef);

@override
String toString() {
  return 'TracedEdge(fromRef: $fromRef, toRef: $toRef)';
}


}

/// @nodoc
abstract mixin class $TracedEdgeCopyWith<$Res>  {
  factory $TracedEdgeCopyWith(TracedEdge value, $Res Function(TracedEdge) _then) = _$TracedEdgeCopyWithImpl;
@useResult
$Res call({
 String fromRef, String toRef
});




}
/// @nodoc
class _$TracedEdgeCopyWithImpl<$Res>
    implements $TracedEdgeCopyWith<$Res> {
  _$TracedEdgeCopyWithImpl(this._self, this._then);

  final TracedEdge _self;
  final $Res Function(TracedEdge) _then;

/// Create a copy of TracedEdge
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? fromRef = null,Object? toRef = null,}) {
  return _then(_self.copyWith(
fromRef: null == fromRef ? _self.fromRef : fromRef // ignore: cast_nullable_to_non_nullable
as String,toRef: null == toRef ? _self.toRef : toRef // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [TracedEdge].
extension TracedEdgePatterns on TracedEdge {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _TracedEdge value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _TracedEdge() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _TracedEdge value)  $default,){
final _that = this;
switch (_that) {
case _TracedEdge():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _TracedEdge value)?  $default,){
final _that = this;
switch (_that) {
case _TracedEdge() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String fromRef,  String toRef)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _TracedEdge() when $default != null:
return $default(_that.fromRef,_that.toRef);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String fromRef,  String toRef)  $default,) {final _that = this;
switch (_that) {
case _TracedEdge():
return $default(_that.fromRef,_that.toRef);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String fromRef,  String toRef)?  $default,) {final _that = this;
switch (_that) {
case _TracedEdge() when $default != null:
return $default(_that.fromRef,_that.toRef);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _TracedEdge extends TracedEdge {
  const _TracedEdge({required this.fromRef, required this.toRef}): super._();
  factory _TracedEdge.fromJson(Map<String, dynamic> json) => _$TracedEdgeFromJson(json);

@override final  String fromRef;
@override final  String toRef;

/// Create a copy of TracedEdge
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$TracedEdgeCopyWith<_TracedEdge> get copyWith => __$TracedEdgeCopyWithImpl<_TracedEdge>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$TracedEdgeToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _TracedEdge&&(identical(other.fromRef, fromRef) || other.fromRef == fromRef)&&(identical(other.toRef, toRef) || other.toRef == toRef));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,fromRef,toRef);

@override
String toString() {
  return 'TracedEdge(fromRef: $fromRef, toRef: $toRef)';
}


}

/// @nodoc
abstract mixin class _$TracedEdgeCopyWith<$Res> implements $TracedEdgeCopyWith<$Res> {
  factory _$TracedEdgeCopyWith(_TracedEdge value, $Res Function(_TracedEdge) _then) = __$TracedEdgeCopyWithImpl;
@override @useResult
$Res call({
 String fromRef, String toRef
});




}
/// @nodoc
class __$TracedEdgeCopyWithImpl<$Res>
    implements _$TracedEdgeCopyWith<$Res> {
  __$TracedEdgeCopyWithImpl(this._self, this._then);

  final _TracedEdge _self;
  final $Res Function(_TracedEdge) _then;

/// Create a copy of TracedEdge
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? fromRef = null,Object? toRef = null,}) {
  return _then(_TracedEdge(
fromRef: null == fromRef ? _self.fromRef : fromRef // ignore: cast_nullable_to_non_nullable
as String,toRef: null == toRef ? _self.toRef : toRef // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}


/// @nodoc
mixin _$TracedPlan {

 String get buildingId; List<TracedNode> get nodes; List<TracedEdge> get edges;/// How many metres one plan unit is, when anything knows.
///
/// Almost always null, and that is the point. A contributor tracing a plan
/// cannot be asked how far apart two points on it really are — they do not
/// know, and asking is the same unanswerable question as "tap when you have
/// walked ten metres". Nothing needs the answer: A* compares edge lengths
/// against each other, so scaling every edge by the same unknown constant
/// picks exactly the same route, and guidance names landmarks rather than
/// distances.
///
/// Left here because it *can* be filled in later without asking anybody:
/// one walk over one traced leg with a working step counter gives metres
/// for that leg, which sizes the whole plan. Until then the map is
/// unitless and works.
 double? get metresPerUnit;
/// Create a copy of TracedPlan
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TracedPlanCopyWith<TracedPlan> get copyWith => _$TracedPlanCopyWithImpl<TracedPlan>(this as TracedPlan, _$identity);

  /// Serializes this TracedPlan to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TracedPlan&&(identical(other.buildingId, buildingId) || other.buildingId == buildingId)&&const DeepCollectionEquality().equals(other.nodes, nodes)&&const DeepCollectionEquality().equals(other.edges, edges)&&(identical(other.metresPerUnit, metresPerUnit) || other.metresPerUnit == metresPerUnit));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,buildingId,const DeepCollectionEquality().hash(nodes),const DeepCollectionEquality().hash(edges),metresPerUnit);

@override
String toString() {
  return 'TracedPlan(buildingId: $buildingId, nodes: $nodes, edges: $edges, metresPerUnit: $metresPerUnit)';
}


}

/// @nodoc
abstract mixin class $TracedPlanCopyWith<$Res>  {
  factory $TracedPlanCopyWith(TracedPlan value, $Res Function(TracedPlan) _then) = _$TracedPlanCopyWithImpl;
@useResult
$Res call({
 String buildingId, List<TracedNode> nodes, List<TracedEdge> edges, double? metresPerUnit
});




}
/// @nodoc
class _$TracedPlanCopyWithImpl<$Res>
    implements $TracedPlanCopyWith<$Res> {
  _$TracedPlanCopyWithImpl(this._self, this._then);

  final TracedPlan _self;
  final $Res Function(TracedPlan) _then;

/// Create a copy of TracedPlan
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? buildingId = null,Object? nodes = null,Object? edges = null,Object? metresPerUnit = freezed,}) {
  return _then(_self.copyWith(
buildingId: null == buildingId ? _self.buildingId : buildingId // ignore: cast_nullable_to_non_nullable
as String,nodes: null == nodes ? _self.nodes : nodes // ignore: cast_nullable_to_non_nullable
as List<TracedNode>,edges: null == edges ? _self.edges : edges // ignore: cast_nullable_to_non_nullable
as List<TracedEdge>,metresPerUnit: freezed == metresPerUnit ? _self.metresPerUnit : metresPerUnit // ignore: cast_nullable_to_non_nullable
as double?,
  ));
}

}


/// Adds pattern-matching-related methods to [TracedPlan].
extension TracedPlanPatterns on TracedPlan {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _TracedPlan value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _TracedPlan() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _TracedPlan value)  $default,){
final _that = this;
switch (_that) {
case _TracedPlan():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _TracedPlan value)?  $default,){
final _that = this;
switch (_that) {
case _TracedPlan() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String buildingId,  List<TracedNode> nodes,  List<TracedEdge> edges,  double? metresPerUnit)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _TracedPlan() when $default != null:
return $default(_that.buildingId,_that.nodes,_that.edges,_that.metresPerUnit);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String buildingId,  List<TracedNode> nodes,  List<TracedEdge> edges,  double? metresPerUnit)  $default,) {final _that = this;
switch (_that) {
case _TracedPlan():
return $default(_that.buildingId,_that.nodes,_that.edges,_that.metresPerUnit);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String buildingId,  List<TracedNode> nodes,  List<TracedEdge> edges,  double? metresPerUnit)?  $default,) {final _that = this;
switch (_that) {
case _TracedPlan() when $default != null:
return $default(_that.buildingId,_that.nodes,_that.edges,_that.metresPerUnit);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _TracedPlan extends TracedPlan {
  const _TracedPlan({required this.buildingId, required final  List<TracedNode> nodes, required final  List<TracedEdge> edges, this.metresPerUnit}): _nodes = nodes,_edges = edges,super._();
  factory _TracedPlan.fromJson(Map<String, dynamic> json) => _$TracedPlanFromJson(json);

@override final  String buildingId;
 final  List<TracedNode> _nodes;
@override List<TracedNode> get nodes {
  if (_nodes is EqualUnmodifiableListView) return _nodes;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_nodes);
}

 final  List<TracedEdge> _edges;
@override List<TracedEdge> get edges {
  if (_edges is EqualUnmodifiableListView) return _edges;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_edges);
}

/// How many metres one plan unit is, when anything knows.
///
/// Almost always null, and that is the point. A contributor tracing a plan
/// cannot be asked how far apart two points on it really are — they do not
/// know, and asking is the same unanswerable question as "tap when you have
/// walked ten metres". Nothing needs the answer: A* compares edge lengths
/// against each other, so scaling every edge by the same unknown constant
/// picks exactly the same route, and guidance names landmarks rather than
/// distances.
///
/// Left here because it *can* be filled in later without asking anybody:
/// one walk over one traced leg with a working step counter gives metres
/// for that leg, which sizes the whole plan. Until then the map is
/// unitless and works.
@override final  double? metresPerUnit;

/// Create a copy of TracedPlan
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$TracedPlanCopyWith<_TracedPlan> get copyWith => __$TracedPlanCopyWithImpl<_TracedPlan>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$TracedPlanToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _TracedPlan&&(identical(other.buildingId, buildingId) || other.buildingId == buildingId)&&const DeepCollectionEquality().equals(other._nodes, _nodes)&&const DeepCollectionEquality().equals(other._edges, _edges)&&(identical(other.metresPerUnit, metresPerUnit) || other.metresPerUnit == metresPerUnit));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,buildingId,const DeepCollectionEquality().hash(_nodes),const DeepCollectionEquality().hash(_edges),metresPerUnit);

@override
String toString() {
  return 'TracedPlan(buildingId: $buildingId, nodes: $nodes, edges: $edges, metresPerUnit: $metresPerUnit)';
}


}

/// @nodoc
abstract mixin class _$TracedPlanCopyWith<$Res> implements $TracedPlanCopyWith<$Res> {
  factory _$TracedPlanCopyWith(_TracedPlan value, $Res Function(_TracedPlan) _then) = __$TracedPlanCopyWithImpl;
@override @useResult
$Res call({
 String buildingId, List<TracedNode> nodes, List<TracedEdge> edges, double? metresPerUnit
});




}
/// @nodoc
class __$TracedPlanCopyWithImpl<$Res>
    implements _$TracedPlanCopyWith<$Res> {
  __$TracedPlanCopyWithImpl(this._self, this._then);

  final _TracedPlan _self;
  final $Res Function(_TracedPlan) _then;

/// Create a copy of TracedPlan
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? buildingId = null,Object? nodes = null,Object? edges = null,Object? metresPerUnit = freezed,}) {
  return _then(_TracedPlan(
buildingId: null == buildingId ? _self.buildingId : buildingId // ignore: cast_nullable_to_non_nullable
as String,nodes: null == nodes ? _self._nodes : nodes // ignore: cast_nullable_to_non_nullable
as List<TracedNode>,edges: null == edges ? _self._edges : edges // ignore: cast_nullable_to_non_nullable
as List<TracedEdge>,metresPerUnit: freezed == metresPerUnit ? _self.metresPerUnit : metresPerUnit // ignore: cast_nullable_to_non_nullable
as double?,
  ));
}


}

// dart format on
