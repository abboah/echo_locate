import 'dart:async';
import 'dart:typed_data';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../../core/models/building.dart' show BuildingFloor;
import '../../../core/models/room_plan.dart';
import '../../../core/utils/logger.dart';
import '../../../services/mapping/room_cleanup.dart';
import '../../../services/mapping/room_geometry.dart';
import '../../../services/mapping/room_graph.dart';
import '../../../services/vision/arcore_capture_service.dart';
import '../../../services/vision/depth_frame.dart' show ArCoreAvailability;
import '../../buildings/building_repository.dart';
import '../../room_trace/room_plan_repository.dart';

part 'room_capture_state.dart';

/// Capturing room shapes in AR — floorplan spec §2, Dart side.
///
/// A `Cubit` rather than a full Bloc: every input here is a direct command from
/// one screen — tap a corner, undo, close the room — with no event a second
/// source could raise. Following `ScanCapabilityCubit`, which made the same
/// call for the same reason.
///
/// ## Deliberately the same shape as `RoomTraceBloc`
///
/// The two produce the identical artefact — a [RoomPlan] — and share the whole
/// pipeline below it: cleanup, winding, self-intersection rejection, the door
/// count guard, the nav graph, directions, the renderer, the repository. What
/// differs is only where corners come from: a finger on a photograph there, an
/// ARCore hit-test here.
///
/// The one real difference is **units**. A traced plan is unitless because
/// nobody measured the wall board; a captured plan is genuinely in metres, so
/// [metresPerUnit] is set and guidance is allowed to speak distances aloud.
///
/// ## Status
///
/// Untested on hardware — the team's device is not ARCore-certified. Everything
/// above the platform channel is exercised in `room_capture_cubit_test.dart`
/// against a fake service; the parts that need a phone are the hit-test
/// geometry and the preview's orientation. See `RoomCaptureHandler` for the
/// specific constants to reach for when one is available.
class RoomCaptureCubit extends Cubit<RoomCaptureState> {
  RoomCaptureCubit(this._capture, this._plans, this._buildings)
    : super(const RoomCaptureState());

  final ArCoreCaptureService _capture;
  final RoomPlanRepository _plans;
  final BuildingRepository _buildings;

  StreamSubscription<CaptureFrame>? _frames;

  /// Shortest wall kept when cleaning a captured room, in **metres**.
  ///
  /// The library default (30 cm) is right here and wrong for photo tracing,
  /// which works in image fractions — the mirror of the bug that deleted rooms
  /// down to triangles there. Captured coordinates really are metres, so the
  /// metre-shaped constant is the correct one.
  static const double minEdgeMetres = kMinEdgeMetres;

  /// How near a room's wall a door tap must land, in **metres**.
  ///
  /// Generous on purpose. The contributor is standing *in* the doorway, so the
  /// point is essentially on the wall the two rooms share — but the two rooms
  /// were captured in separate passes and their walls will not coincide
  /// exactly, and ARCore's own hit precision adds to that. A metre absorbs
  /// both and is still far tighter than the gap to any third room.
  ///
  /// **Tuning point.** If doors start attaching to the wrong neighbour in a
  /// building with thin partitions, this is the number.
  static const double doorSnapMetres = 1;

  /// How far a single session may span before drift is worth warning about.
  ///
  /// Spec §8: ARCore heading error compounds with distance, and heading error
  /// is the kind that ruins a plan rather than blurring it. A wing — one
  /// corridor and the rooms off it — is the unit that stays honest. Past this,
  /// the right move is to save, start a fresh session for the next wing, and
  /// align them by hand later.
  ///
  /// Not enforced, only reported: cutting somebody off mid-capture would lose
  /// more than the drift costs.
  static const double driftWarningSpanMetres = 35;

  /// Metres left between a newly opened wing and everything already placed.
  ///
  /// Enough that two wings never overlap before anybody has aligned them, and
  /// small enough that the new one is still on screen next to the old. Matches
  /// the gap `FloorGraph` leaves between routes that share no landmark, for the
  /// same reason: parked is not placed, and it has to *look* unplaced.
  static const double parkingGapMetres = 20;

  int _nextId = 1;

  String? _wingId;

  String _id(String prefix) => '$prefix-${_nextId++}';

  /// Starts a new wing on [plan], parked clear of whatever is already there.
  ///
  /// Each AR session begins with ARCore's origin wherever the phone happens to
  /// be, so this session's coordinates say nothing about where it sits relative
  /// to a wing captured yesterday. Dropping it in raw would pile the new rooms
  /// on top of the old ones at coordinates that mean nothing.
  ///
  /// So it is **parked**: shifted east of everything placed, visibly beside the
  /// rest rather than pretending to be part of it. Aligning it is a deliberate
  /// act in the editor, which is spec §8's whole point — a person who can see
  /// the building does in seconds what pose-graph optimisation does in weeks.
  ///
  /// The first wing on an empty floor is not parked; there is nothing to be
  /// clear of, and its own frame is as good an origin as any.
  RoomPlan _openWing(RoomPlan plan) {
    final wingId = 'wing-${plan.wingIds.length + 1}';
    _wingId = wingId;

    if (plan.drawableRooms.isEmpty) return plan;

    return plan.placeWing(
      wingId,
      WingPlacement(dx: plan.bounds.right + parkingGapMetres),
    );
  }

  Future<void> start({
    required String buildingId,
    String floorId = '',
    required int viewWidth,
    required int viewHeight,
    int displayRotation = 0,
  }) async {
    emit(state.copyWith(buildingId: buildingId, floorId: floorId));

    // Real floor ids, or a captured room references a floor the server will
    // reject — the same failure the tracing flow documents.
    var resolvedFloor = floorId;
    var prefix = 'R';
    try {
      final floors = await _buildings.floorsOf(buildingId);
      if (isClosed) return;
      if (floors.isNotEmpty) {
        final floor = floors.firstWhere(
          (f) => f.id == floorId,
          orElse: () => floors.first,
        );
        resolvedFloor = floor.id;
        prefix = _codePrefixFor(floor.label);
        emit(state.copyWith(floors: floors, floorId: floor.id));
      }
    } catch (error) {
      AppLogger.warn('Floors unavailable for $buildingId: $error');
    }

    // What this floor already has. Without this a second scan of the same
    // floor started blank and **saved over the first** — a whole wing of a
    // building lost silently, which is the worst kind of bug for something
    // somebody spent twenty minutes walking.
    RoomPlan plan = RoomPlan(
      buildingId: buildingId,
      floorId: resolvedFloor,
      codePrefix: prefix,
      // The difference that matters: these coordinates are metres, so
      // guidance may speak distances from them.
      metresPerUnit: 1,
    );
    try {
      final existing = await _plans.planFor(buildingId, resolvedFloor);
      if (isClosed) return;
      if (existing != null && existing.storedRooms.isNotEmpty) {
        // Refused rather than merged. A plan traced off a photograph is
        // measured in fractions of that image's width; AR capture produces
        // metres. Appending one to the other puts two coordinate systems about
        // fifty times apart into one space — the captured wing dwarfs the
        // building, and because the combined plan inherits the traced plan's
        // null scale, guidance also stops speaking distances it now genuinely
        // has. Nothing about it looks wrong until somebody opens the map.
        //
        // There is no honest conversion: rescaling needs the metres-per-unit
        // nobody measured, which is the whole reason a traced plan is unitless.
        if (!existing.isMetric) {
          emit(
            state.copyWith(
              stage: RoomCaptureStage.unavailable,
              error:
                  'This floor was traced from a photo, which has no real '
                  'scale. Scanning it in AR would mix two different '
                  'measurements — edit the traced plan instead, or scan a '
                  'floor nobody has traced.',
            ),
          );
          return;
        }
        plan = existing;
        _nextId = existing.highestIdSuffix + 1;
      }
    } catch (error) {
      AppLogger.warn('Existing room plan unavailable: $error');
    }

    emit(state.copyWith(plan: _openWing(plan), wingId: _wingId));

    final availability = await _capture.checkAvailability();
    if (isClosed) return;
    emit(state.copyWith(availability: availability));

    if (availability != ArCoreAvailability.supported) {
      // Not an error state. A large share of budget Android hardware — the
      // hardware this app's users have — is uncertified, and the honest answer
      // is to offer photo tracing rather than to fail.
      emit(state.copyWith(stage: RoomCaptureStage.unavailable));
      return;
    }

    final failure = await _capture.start(
      viewWidth: viewWidth,
      viewHeight: viewHeight,
      displayRotation: displayRotation,
    );
    if (isClosed) return;
    if (failure != null) {
      emit(state.copyWith(stage: RoomCaptureStage.unavailable, error: failure));
      return;
    }

    _frames = _capture.frames.listen((frame) {
      if (isClosed) return;
      emit(
        state.copyWith(
          stage: RoomCaptureStage.capturing,
          tracking: frame.tracking,
          issue: frame.issue,
          planeLocked: frame.planeLocked,
          // Held rather than replaced with null: previews are throttled
          // natively, so most updates carry state and no image, and blanking
          // the view between them would strobe.
          preview: frame.preview ?? state.preview,
          previewQuarterTurns: frame.quarterTurns,
        ),
      );
    });

    emit(state.copyWith(stage: RoomCaptureStage.capturing));
  }

  /// Tries to place a corner where the user tapped.
  ///
  /// [u] and [v] are normalised across the preview. A tap that hits nothing —
  /// no tracking, no plane, a point beyond what ARCore has actually observed,
  /// or a surface that is not this room's floor — is reported as guidance
  /// rather than as an error, because all four are ordinary while walking
  /// around a real building.
  Future<void> tapCorner(double u, double v) async {
    if (state.stage != RoomCaptureStage.capturing) return;
    if (!state.tracking.canCapture) {
      emit(state.copyWith(hint: state.issue.advice));
      return;
    }

    final corner = await _capture.hitTest(u, v);
    if (isClosed) return;

    if (corner == null) {
      emit(
        state.copyWith(
          hint: 'No floor there. Aim at the floor where the wall meets it.',
        ),
      );
      return;
    }

    emit(state.copyWith(draft: [...state.draft, corner], hint: null));
  }

  /// Switches between placing corners and placing doors.
  ///
  /// Leaving room mode abandons a half-captured polygon rather than leaving it
  /// to reappear over a different room later.
  /// Switches to another floor of the same building.
  ///
  /// Only before anything has been captured this session. A plan belongs to one
  /// floor, so changing floor mid-wing would either discard work or file rooms
  /// under a floor they are not on — and the screen disables the picker rather
  /// than letting either happen quietly.
  Future<void> changeFloor(String floorId) async {
    if (state.wingHasRooms || state.isCapturing) return;
    if (floorId == state.floorId) return;

    final floor = state.floors.where((f) => f.id == floorId).firstOrNull;
    if (floor == null) return;

    RoomPlan plan = RoomPlan(
      buildingId: state.buildingId,
      floorId: floorId,
      codePrefix: _codePrefixFor(floor.label),
      metresPerUnit: 1,
    );
    _nextId = 1;

    try {
      final existing = await _plans.planFor(state.buildingId, floorId);
      if (isClosed) return;
      if (existing != null && existing.storedRooms.isNotEmpty) {
        if (!existing.isMetric) {
          emit(
            state.copyWith(
              floorId: floorId,
              plan: plan,
              error:
                  'That floor was traced from a photo, which has no real '
                  'scale. Edit the traced plan instead.',
            ),
          );
          return;
        }
        plan = existing;
        _nextId = existing.highestIdSuffix + 1;
      }
    } catch (error) {
      AppLogger.warn('Existing room plan unavailable: $error');
    }

    emit(
      state.copyWith(floorId: floorId, plan: _openWing(plan), wingId: _wingId),
    );
  }

  /// Tells ARCore the view resized or the device rotated.
  Future<void> setViewport({
    required int viewWidth,
    required int viewHeight,
    int displayRotation = 0,
  }) => _capture.setViewport(
    viewWidth: viewWidth,
    viewHeight: viewHeight,
    displayRotation: displayRotation,
  );

  void setMode(RoomCaptureMode mode) {
    emit(state.copyWith(mode: mode, draft: const [], hint: null));
  }

  /// Records a door where the contributor is standing.
  ///
  /// The interaction the AR path gets for free and the photo path cannot: stand
  /// **in the doorway** and tap the floor. The point lands on the wall the two
  /// rooms share, and which two they are is then geometry rather than another
  /// question to answer — see [RoomNavGraph.inferDoorAt], shared with tracing.
  ///
  /// Without this a captured floor is a picture rather than a map: the rooms
  /// are positioned correctly and joined by nothing, so every one of them is
  /// unreachable from every other and no route can be planned at all.
  Future<void> tapDoor(double u, double v) async {
    if (state.stage != RoomCaptureStage.capturing) return;
    if (!state.tracking.canCapture) {
      emit(state.copyWith(hint: state.issue.advice));
      return;
    }
    if (state.plan.drawableRooms.length < 2) {
      emit(
        state.copyWith(
          hint: 'Capture the rooms either side of the door first.',
        ),
      );
      return;
    }

    final corner = await _capture.hitTest(u, v);
    if (isClosed) return;
    if (corner == null) {
      emit(
        state.copyWith(
          hint: 'No floor there. Aim at the floor in the doorway.',
        ),
      );
      return;
    }

    final inferred = RoomNavGraph.inferDoorAt(
      state.plan,
      corner.position,
      radius: doorSnapMetres,
    );
    final roomA = inferred.roomA;
    final roomB = inferred.roomB;

    if (roomA == null) {
      emit(
        state.copyWith(
          hint: 'That is not near a wall. Stand in the doorway and tap.',
        ),
      );
      return;
    }

    if (roomB != null &&
        state.plan.openings.any(
          (o) => o.touches(roomA.id) && o.touches(roomB.id),
        )) {
      emit(state.copyWith(hint: 'Those rooms already have a door.'));
      return;
    }

    emit(
      state.copyWith(
        plan: state.plan.copyWith(
          storedOpenings: [
            ...state.plan.openings,
            Opening(
              id: _id('door'),
              roomAId: roomA.id,
              roomBId: roomB?.id,
              at: RoomCorner.of(corner.position),
            ),
          ],
        ),
        hint: roomB == null
            ? 'Recorded as a way out — only one room borders that point.'
            : 'Door recorded: ${roomA.spokenName} to ${roomB.spokenName}.',
      ),
    );
  }

  void removeDoor(String openingId) {
    emit(
      state.copyWith(
        plan: state.plan.copyWith(
          storedOpenings: [
            for (final opening in state.plan.openings)
              if (opening.id != openingId) opening,
          ],
        ),
      ),
    );
  }

  /// Records how many doors the contributor counted on a corridor's walls.
  ///
  /// The guard on the only instruction this app can get confidently, silently
  /// wrong. Until the tagged doors match this number, `RoomDirections` refuses
  /// to say "the second door on your left" at all — see
  /// [RoomPlan.corridorIsComplete].
  void declareDoorCount({required String corridorId, required int count}) {
    emit(
      state.copyWith(
        plan: state.plan.copyWith(
          declaredDoorCounts: {
            ...state.plan.declaredDoorCounts,
            corridorId: count,
          },
        ),
      ),
    );
  }

  /// Adds a room behind a door nobody opened — spec §6.3.
  ///
  /// A corridor with eight doors where five lead somewhere captured and three
  /// lead to locked offices still has eight doors. The three have to be
  /// *counted* or every ordinal past them is wrong; a stub carries no polygon,
  /// so it is in the graph and absent from the drawing.
  void addStubRoom() {
    // Code is the id — rooms are not numbered, here or in the tracing flow.
    // Both build the same model and feed the same landmark bridge, so a
    // sequential code allocated here would reach guidance's mouth just the
    // same. See [Room.displayName].
    final roomId = _id('room');
    final room = Room.stub(
      id: roomId,
      floorId: state.floorId,
      code: roomId,
    );
    emit(
      state.copyWith(
        plan: state.plan.copyWith(storedRooms: [...state.plan.rooms, room]),
      ),
    );
  }

  Future<void> undoCorner() async {
    if (state.draft.isEmpty) return;
    final removed = state.draft.last;
    emit(
      state.copyWith(
        draft: state.draft.sublist(0, state.draft.length - 1),
        hint: null,
      ),
    );
    // Its anchor is no longer wanted, and anchors cost tracking work per frame.
    await _capture.releaseCorners([removed]);
  }

  Future<void> discardRoom() async {
    final abandoned = state.draft;
    emit(state.copyWith(draft: const [], hint: null));
    await _capture.releaseCorners(abandoned);
  }

  /// Closes the captured polygon into a room.
  ///
  /// Identical rules to the tracing flow, deliberately: self-intersection is
  /// judged on the **raw** capture before cleanup, because snapping walls to a
  /// grid can pull a crossed polygon straight and silently accept a shape the
  /// user did not mean.
  Future<void> closeRoom({
    required RoomCategory category,
    String? label,
  }) async {
    if (!state.canCloseRoom) {
      emit(state.copyWith(hint: 'A room needs at least three corners.'));
      return;
    }

    // Re-read every corner before judging the shape.
    //
    // ARCore may have relocalised since the first tap — lost tracking, found
    // itself, and shifted where it thinks the world origin is. Corners recorded
    // either side of that are in two different frames, and the room comes out
    // deformed with nothing to say so. Asking ARCore for its anchors' current
    // poses puts them all back in one frame, and it has to happen *before*
    // cleanup and the self-intersection check, or both judge a shape the walls
    // were never in.
    final resolved = await _capture.resolveCorners(state.draft);
    if (isClosed) return;

    final raw = [for (final corner in resolved) corner.position];

    if (selfIntersects(raw)) {
      emit(
        state.copyWith(
          hint: 'Those walls cross each other. Undo the last corner.',
        ),
      );
      return;
    }

    final cleaned = cleanupPolygon(raw, minEdgeMetres: minEdgeMetres);
    if (cleaned.length < 3 || selfIntersects(cleaned)) {
      emit(
        state.copyWith(
          draft: const [],
          hint: 'That shape did not come out as a room. Try again.',
        ),
      );
      return;
    }

    final room = Room(
      id: _id('room'),
      floorId: state.floorId,
      code: state.plan.allocateCode(),
      category: category,
      label: (label?.trim().isEmpty ?? true) ? null : label!.trim(),
      polygon: [for (final corner in cleaned) RoomCorner.of(corner)],
      // Which session captured it. This is what lets the editor move a whole
      // wing without disturbing one captured on a different day.
      wingId: _wingId,
    );

    emit(
      state.copyWith(
        plan: state.plan.copyWith(storedRooms: [...state.plan.rooms, room]),
        draft: const [],
        hint: null,
      ),
    );

    // The corners are polygon now; their anchors have no further job.
    await _capture.releaseCorners(resolved);

    // The next room locks to its own floor. Reset after closing rather than
    // before starting, so walking into the next room and tapping just works.
    await _capture.resetPlaneLock();
  }

  Future<void> save() async {
    if (!state.canSave) {
      emit(state.copyWith(error: 'Capture at least one room first.'));
      return;
    }
    emit(state.copyWith(stage: RoomCaptureStage.saving));
    try {
      await _plans.save(state.plan);
      if (isClosed) return;
      emit(state.copyWith(stage: RoomCaptureStage.saved));
    } catch (error, stack) {
      AppLogger.error('Captured plan save failed', error, stack);
      if (isClosed) return;
      emit(
        state.copyWith(
          stage: RoomCaptureStage.capturing,
          error: 'Could not save. The rooms are still here — try again.',
        ),
      );
    }
  }

  static String _codePrefixFor(String label) {
    final trimmed = label.trim();
    if (trimmed.isEmpty) return 'R';
    return '${trimmed.toUpperCase()}F';
  }

  @override
  Future<void> close() async {
    await _frames?.cancel();
    await _capture.stop();
    return super.close();
  }
}
