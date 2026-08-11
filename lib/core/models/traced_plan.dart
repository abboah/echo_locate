import 'package:freezed_annotation/freezed_annotation.dart';

import 'landmark.dart';

part 'traced_plan.freezed.dart';
part 'traced_plan.g.dart';

/// A landmark placed by tapping a photographed floor plan.
///
/// [x] and [y] are metres, not pixels: the tracing screen divides the tapped
/// image coordinates by the scale the contributor set, so the stored plan does
/// not depend on the photo's resolution or on the device that traced it.
@freezed
abstract class TracedNode with _$TracedNode {
  const factory TracedNode({
    /// Identifies this node within the plan. Client-side while tracing ('n1'),
    /// rewritten to the real landmark id once the plan is saved, so
    /// [FloorGraph.fromPlan] builds the same graph before and after a round
    /// trip through the repository.
    required String ref,

    /// East of the plan's origin, in plan units.
    ///
    /// Plan units, not metres: see [TracedPlan.metresPerUnit] for why a traced
    /// plan is unitless and why that costs nothing.
    required double x,

    /// North of the plan's origin, in plan units.
    required double y,

    /// Which floor this node sits on. Held per node rather than per plan so a
    /// building traced floor by floor is still one graph: the stairwell node on
    /// the ground floor and the landing node above it are joined by an ordinary
    /// edge, and A* climbs it like any other corridor.
    required String floorId,
    required LandmarkKind kind,

    /// What OCR must read to confirm arrival here — printed on the plan and,
    /// crucially, on the door itself.
    required String labelText,
    required String displayName,
    @Default(<String>[]) List<String> aliases,
    String? roomId,
  }) = _TracedNode;

  const TracedNode._();

  factory TracedNode.fromJson(Map<String, dynamic> json) =>
      _$TracedNodeFromJson(json);
}

/// A corridor between two traced nodes.
///
/// Carries no distance: the length is the distance between the two nodes'
/// coordinates, so a plan cannot contain an edge whose stated length disagrees
/// with where its ends were drawn.
@freezed
abstract class TracedEdge with _$TracedEdge {
  const factory TracedEdge({
    required String fromRef,
    required String toRef,
  }) = _TracedEdge;

  const TracedEdge._();

  factory TracedEdge.fromJson(Map<String, dynamic> json) =>
      _$TracedEdgeFromJson(json);

  bool connects(String a, String b) =>
      (fromRef == a && toRef == b) || (fromRef == b && toRef == a);
}

/// One floor of a building, traced off its posted floor plan.
///
/// The alternative to walking a building with a pedometer. A recorded walk
/// derives geometry by chaining step counts and tapped turns, so error
/// accumulates along the route and a loop never closes. Traced coordinates are
/// absolute from the first tap: nothing accumulates, and the map is as accurate
/// as the plan on the wall.
///
/// Signage-based localisation is unaffected — a traced node still carries the
/// [TracedNode.labelText] OCR looks for. What changes is where the *map* comes
/// from, not how the user is found on it.
@freezed
abstract class TracedPlan with _$TracedPlan {
  const factory TracedPlan({
    required String buildingId,
    required List<TracedNode> nodes,
    required List<TracedEdge> edges,

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
    double? metresPerUnit,
  }) = _TracedPlan;

  const TracedPlan._();

  factory TracedPlan.fromJson(Map<String, dynamic> json) =>
      _$TracedPlanFromJson(json);

  static const TracedPlan empty = TracedPlan(
    buildingId: '',
    nodes: <TracedNode>[],
    edges: <TracedEdge>[],
  );

  bool get isEmpty => nodes.isEmpty;

  TracedNode? nodeOf(String ref) {
    for (final node in nodes) {
      if (node.ref == ref) return node;
    }
    return null;
  }
}
