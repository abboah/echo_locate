// Laying a recorded-walk route into the room — the other half of spec §6.4.
//
// `RoomPlanBridge.routePathFrom` gives the AR layer geometry for a *traced*
// plan. Nothing gave it geometry for the map this app builds by itself: the
// schematic merged out of contributors' recorded walks. So the building flow —
// `navigation_page` — started every guidance session with `routePath: null`,
// which sets `_cannotRegister` in `ArGuidanceCubit` and drops the arrow back to
// dead-reckoned legs. On that screen the registration could never fire at all,
// however good ARCore's pose was.
//
// The coordinates were there the whole time. `route_layout` runs each recorded
// walk as a turtle program and `FloorGraph.merge` stitches the results into one
// frame in metres — that is what the floor map on screen is drawn from. This
// reads the same positions back out along a planned route.
//
// ## This geometry is worse than a traced plan's, and still worth registering
//
// The schematic drifts. Turns come from six tapped buttons, so a corridor that
// bends 80° is recorded as 90°, and `FloorGraph` is explicit that the error is
// measured and reported rather than fitted away. A route registered against it
// is therefore right at the landmarks and progressively wrong between them.
//
// That is exactly the error a landmark re-centring takes out — see
// `ArGuidanceCubit._recentreOnConfirmation`. Each confirmed sign re-anchors the
// transform, so the drift that reaches the walker is one corridor's worth, not
// the building's. Which is the same bound the dead-reckoned leg already lived
// with, except that between landmarks this one knows where the corners are and
// can point at them.
//
// What it will not do is register geometry it can tell is fiction. See
// [_agreesWithRecorded].

import 'dart:math' as math;
import 'dart:ui' show Offset;

import '../../core/utils/logger.dart';
import 'floor_graph.dart';
import 'map_node.dart';
import 'room_plan_bridge.dart' show RoutePath;
import 'route_planner.dart';

/// How far a laid-out leg may differ from the distance the walk recorded.
///
/// Whichever of the two is larger. The absolute figure covers short legs, where
/// a fraction of a couple of metres is less than the merge's own averaging; the
/// fraction covers long ones, where accumulated turn error scales with length.
const double _agreesWithinM = 2;
const double _agreesWithinFraction = 0.35;

/// Shorter than this and there is nothing to register: the whole route fits
/// inside the couple of metres of walking the solve needs before it can run.
const double _shortestUsefulM = 3;

/// The planned walk as a line on the floor, in metres, or null when the merged
/// map cannot honestly place it.
///
/// Null is a normal answer and the caller must treat it as one — guidance
/// carries on with dead-reckoned legs, which is what this screen did before any
/// of this existed. It is returned for a route the merge never placed, one that
/// changes floor, one whose geometry contradicts its own recorded distances,
/// and one whose graph is not in metres at all.
RoutePath? routePathThroughGraph(FloorGraph graph, PlannedRoute route) {
  // A plan traced off an unmeasured image routes correctly — A* only compares
  // edges against each other — but its lengths are in no unit, and laying them
  // into a room in metres would size the building by whatever the tracing
  // happened to be drawn at.
  if (!graph.metric) return null;
  if (route.legs.isEmpty) return null;

  final ids = route.landmarkIds;
  final nodes = <MapNode>[];
  for (final id in ids) {
    final node = graph.nodeOf(id);
    // A landmark on the route that the merge never placed. Skipping it and
    // joining its neighbours would draw a line through whatever is between
    // them, so the whole route goes without geometry instead.
    if (node == null) return null;
    nodes.add(node);
  }

  // The legs have to be the chain [ids] says they are. A synthesised route is
  // spliced out of several contributors' walks, and a splice that does not join
  // end to end would pair each leg's recorded length with somebody else's
  // segment in the check below.
  for (var i = 0; i < route.legs.length; i++) {
    if (route.legs[i].fromLandmarkId != ids[i] ||
        route.legs[i].toLandmarkId != ids[i + 1]) {
      return null;
    }
  }

  // One floor only. A floor-change leg's distance is real — the contributor
  // climbed it and guidance quotes it — but it is vertical, and `route_layout`
  // deliberately places the landing directly above the stairwell, so both ends
  // of that leg are the same point on the floor plane. ARCore's world does not
  // know the walker went upstairs either; registering across the change would
  // fold the upper corridor onto the lower one.
  final floorId = nodes.first.floorId;
  if (nodes.any((node) => node.floorId != floorId)) return null;

  final points = [for (final node in nodes) Offset(node.x, node.y)];

  final legEnds = <double>[];
  var along = 0.0;
  for (var i = 0; i < route.legs.length; i++) {
    final laid = (points[i + 1] - points[i]).distance;
    if (!_agreesWithRecorded(laid: laid, recorded: route.legs[i].distanceM)) {
      AppLogger.info(
        'Graph geometry disagrees with the walk at leg $i: laid out '
        '${laid.toStringAsFixed(1)}m against a recorded '
        '${route.legs[i].distanceM.toStringAsFixed(1)}m — not registering',
      );
      return null;
    }
    along += laid;
    legEnds.add(along);
  }

  if (along < _shortestUsefulM) return null;

  return RoutePath(pointsM: points, legEndsM: legEnds);
}

/// Whether a laid-out segment and the distance somebody recorded walking it
/// describe the same corridor.
///
/// Two things this separates, and they need separating because only one of them
/// is survivable. A route that shared no landmark with anything already placed
/// is parked clear of the rest of the map in a frame of its own
/// (`MergeResult.unanchoredRouteIds`) — its nodes are tens of metres from where
/// the walk says they are, and a transform solved against them would send the
/// walker across the building. Averaging duplicate sightings of a landmark, by
/// contrast, pulls a node off any single walk's idea of it by a metre or two,
/// and that is the drift this is meant to carry rather than refuse.
///
/// The two differ by an order of magnitude, which is the only reason a single
/// threshold can tell them apart.
bool _agreesWithRecorded({required double laid, required double recorded}) {
  final tolerance = math.max(_agreesWithinM, recorded * _agreesWithinFraction);
  return (laid - recorded).abs() <= tolerance;
}
