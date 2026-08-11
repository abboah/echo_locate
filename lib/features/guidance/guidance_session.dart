import 'package:equatable/equatable.dart';

import '../../core/models/landmark.dart';
import '../../services/mapping/floor_graph.dart';
import '../../services/mapping/route_planner.dart';
import '../../services/motion/stride_profile.dart';

/// Everything a walk needs to be guided: the route, the building's landmarks,
/// and how far this particular user travels per step.
///
/// Assembled by the screen that starts guidance, so [GuidanceBloc] never talks
/// to a repository and can be tested with no I/O at all.
class GuidanceSession extends Equatable {
  const GuidanceSession({
    required this.plan,
    required this.landmarks,
    required this.destinationName,
    this.stride = StrideProfile.fallback,
    this.graph,
    this.metric = true,
  });

  final PlannedRoute plan;

  /// Every landmark in the building, not just this route's.
  ///
  /// The recovery sweep matches an OCR read against all of them: a user who
  /// has walked into the wrong corridor is, by definition, looking at a sign
  /// that is not on their route.
  final List<Landmark> landmarks;

  /// Spoken on arrival, and in the ask-a-person fallback.
  final String destinationName;

  final StrideProfile stride;

  /// The whole building's map, when it is available. Recovery uses it to plan
  /// a fresh route from wherever the user turns out to be; without it a lost
  /// user off their route can only be told to ask someone.
  final FloorGraph? graph;

  /// Whether this route's leg lengths are really metres.
  ///
  /// False for a route over a traced plan nobody measured. Guidance then drops
  /// step counts and leans on landmark confirmation, which is the fallback it
  /// already uses on stairs and on phones with no counter.
  final bool metric;

  Landmark? landmarkOf(String id) {
    for (final landmark in landmarks) {
      if (landmark.id == id) return landmark;
    }
    return null;
  }

  /// Speakable name for a landmark, falling back to its id so a missing
  /// record degrades to something odd-sounding rather than to silence.
  String nameOf(String id) => landmarkOf(id)?.displayName ?? id;

  /// Where the route ends. Recovery replans to here.
  String? get destinationLandmarkId =>
      plan.landmarkIds.isEmpty ? null : plan.landmarkIds.last;

  GuidanceSession copyWith({PlannedRoute? plan, StrideProfile? stride}) =>
      GuidanceSession(
        plan: plan ?? this.plan,
        landmarks: landmarks,
        destinationName: destinationName,
        stride: stride ?? this.stride,
        graph: graph,
        metric: metric,
      );

  @override
  List<Object?> get props =>
      [plan, landmarks, destinationName, stride, graph, metric];
}
