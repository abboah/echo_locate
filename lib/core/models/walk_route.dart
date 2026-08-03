import 'package:freezed_annotation/freezed_annotation.dart';

part 'walk_route.freezed.dart';
part 'walk_route.g.dart';

/// One leg of a recorded walk: landmark to landmark.
///
/// Named [RouteStep] rather than `Step` to avoid Flutter's `Step` widget, and
/// the parent is [WalkRoute] rather than `Route` for the same reason.
@freezed
class RouteStep with _$RouteStep {
  const factory RouteStep({
    required int seq,
    required String fromLandmarkId,
    required String toLandmarkId,

    /// Spoken verbatim: 'straight past the help desk'.
    required String instruction,

    /// Canonical length in metres.
    ///
    /// Steps are never the stored unit: a 78cm stride and a 65cm stride do not
    /// share a count, so the contributor's steps are converted to metres on
    /// capture and back into the *current user's* steps on playback.
    required double distanceM,

    /// Turn taken at the START of this leg: 0 straight, -90 left, +90 right,
    /// ±135 sharp. Tapped by the contributor, not sensed — an indoor compass
    /// reading costs magnetic error and buys nothing.
    @Default(0) int turnDeg,

    /// The contributor's raw count. Evidence for the evaluation chapter only;
    /// never used for guidance.
    int? stepsRecorded,
  }) = _RouteStep;

  const RouteStep._();

  factory RouteStep.fromJson(Map<String, dynamic> json) =>
      _$RouteStepFromJson(json);

  /// How many steps *this* user should expect, given their stride.
  int expectedSteps(double strideM) =>
      strideM <= 0 ? 0 : (distanceM / strideM).round();
}

/// A recorded walk from a starting landmark to a destination room.
///
/// Two things are derived from this rather than stored: the 2D schematic
/// (walk the legs as a turtle — rotate by [RouteStep.turnDeg], advance
/// [RouteStep.distanceM]) and the graph A* runs over, whose nodes are
/// landmarks and whose edge weights are leg distances.
@freezed
class WalkRoute with _$WalkRoute {
  const factory WalkRoute({
    required String id,
    required String buildingId,
    required String startLandmarkId,
    required String destinationRoomId,
    required List<RouteStep> steps,
    @Default(0) double totalDistanceM,

    /// Times another user completed this route successfully — a crude quality
    /// signal when several recordings compete for the same destination.
    @Default(0) int verifiedCount,
  }) = _WalkRoute;

  const WalkRoute._();

  factory WalkRoute.fromJson(Map<String, dynamic> json) =>
      _$WalkRouteFromJson(json);

  /// Landmark ids in walking order, start included.
  List<String> get landmarkIds => [
        if (steps.isNotEmpty) steps.first.fromLandmarkId,
        for (final step in steps) step.toLandmarkId,
      ];
}
