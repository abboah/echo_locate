import 'package:freezed_annotation/freezed_annotation.dart';

import 'landmark.dart';

part 'route_draft.freezed.dart';
part 'route_draft.g.dart';

/// A route being recorded, before the server has assigned any ids.
///
/// Separate from [WalkRoute] because during capture the landmarks do not exist
/// yet. The contributor labels them with a client-side [ref] ('L1', 'L2'), the
/// steps reference those refs, and `save_route` maps refs to real uuids in one
/// transaction — so a dropped connection can never leave landmarks without
/// their legs.
///
/// Serialises directly to the `save_route(p_route jsonb)` payload.
@freezed
abstract class DraftLandmark with _$DraftLandmark {
  const factory DraftLandmark({
    /// Client-side label, unique within this draft.
    required String ref,
    required String floorId,
    required LandmarkKind kind,
    required String labelText,
    required String displayName,
    @Default(<String>[]) List<String> aliases,
    String? roomId,
  }) = _DraftLandmark;

  factory DraftLandmark.fromJson(Map<String, dynamic> json) =>
      _$DraftLandmarkFromJson(json);
}

@freezed
abstract class DraftStep with _$DraftStep {
  const factory DraftStep({
    required int seq,
    @JsonKey(name: 'from') required String fromRef,
    @JsonKey(name: 'to') required String toRef,
    required String instruction,
    required double distanceM,
    @Default(0) int turnDeg,
    int? stepsRecorded,
  }) = _DraftStep;

  factory DraftStep.fromJson(Map<String, dynamic> json) =>
      _$DraftStepFromJson(json);
}

@freezed
abstract class RouteDraft with _$RouteDraft {
  const factory RouteDraft({
    required String buildingId,
    required String destinationRoomId,
    required List<DraftLandmark> landmarks,
    required List<DraftStep> steps,
  }) = _RouteDraft;

  const RouteDraft._();

  factory RouteDraft.fromJson(Map<String, dynamic> json) =>
      _$RouteDraftFromJson(json);

  /// Payload for the `save_route` RPC. Keys are snake_case to match the SQL
  /// function; the repository is the only place that knows this shape.
  Map<String, dynamic> toRpcPayload() => {
    'building_id': buildingId,
    'destination_room_id': destinationRoomId,
    'landmarks': [
      for (final l in landmarks)
        {
          'ref': l.ref,
          'floor_id': l.floorId,
          'kind': l.kind.name,
          'label_text': l.labelText,
          'display_name': l.displayName,
          'aliases': l.aliases,
          'room_id': l.roomId,
        },
    ],
    'steps': [
      for (final s in steps)
        {
          'seq': s.seq,
          'from': s.fromRef,
          'to': s.toRef,
          'instruction': s.instruction,
          'distance_m': s.distanceM,
          'steps_recorded': s.stepsRecorded,
          'turn_deg': s.turnDeg,
        },
    ],
  };
}
