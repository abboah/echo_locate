import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../../core/models/building.dart' show BuildingFloor;
import '../../../core/models/room_plan.dart';
import '../../../core/utils/logger.dart';
import '../../../services/mapping/floor_squaring.dart';
import '../../../services/mapping/plan_editing.dart';
import '../../../services/mapping/room_geometry.dart';
import '../../../services/mapping/room_graph.dart';
import '../../buildings/building_repository.dart';
import '../../room_trace/room_plan_repository.dart';

part 'plan_editor_state.dart';

/// Correcting a saved floor — floorplan spec §8.
///
/// Two jobs, both of which only make sense once a floor exists:
///
///  * **Aligning wings.** A building too large for one AR session is captured a
///    wing at a time, and each session starts with ARCore's origin wherever the
///    phone was. A newly captured wing is therefore *parked* beside the floor
///    rather than placed on it, and somebody has to say where it really goes.
///    The spec is explicit that this is human-in-the-loop on purpose: automated
///    pose-graph optimisation is weeks of work, and a contributor who can see
///    the building does it in seconds.
///  * **Fixing what was captured.** Delete a room traced twice, change a
///    category picked wrongly, rename a door plate misread. A floor plan nobody
///    can correct is one that gets retraced from scratch instead.
///
/// Rotation and translation only — no scaling, ever. Both capture paths produce
/// geometry that is internally correct; what is unknown is where a wing *sits*,
/// which is three numbers. Offering scale would invite somebody to stretch a
/// wing until it looked right, and a plan that looks right and measures wrong
/// is worse than one that looks wrong.
class PlanEditorCubit extends Cubit<PlanEditorState> {
  PlanEditorCubit(this._plans, this._buildings)
    : super(const PlanEditorState());

  final RoomPlanRepository _plans;
  final BuildingRepository _buildings;

  /// How close two corridors' axes must be before the editor offers to square
  /// them up, in degrees.
  ///
  /// Spec §8's figure. Corridors in one building are overwhelmingly parallel or
  /// perpendicular, so a wing dragged roughly into place is nearly always meant
  /// to be exactly aligned — and "nearly aligned" is the state that makes a
  /// plan look hand-drawn and a door land in the wrong wall.
  static const double snapToleranceDeg = 5;

  /// One nudge of the rotate control, in degrees.
  static const double rotateStepDeg = 1;

  /// The floor as it stood before the last [squareUpFloor], for [undoSquaring].
  RoomPlan? _beforeSquaring;

  Future<void> load({
    required String buildingId,
    required String floorId,
  }) async {
    // Belongs to the floor that is on screen, not to the screen.
    _beforeSquaring = null;
    emit(state.copyWith(status: PlanEditorStatus.loading));

    // The building's floors, so a floor above the ground can be edited at all.
    // Every screen in this feature took the first floor and stopped there.
    var resolvedFloor = floorId;
    try {
      final floors = await _buildings.floorsOf(buildingId);
      if (isClosed) return;
      if (floors.isNotEmpty) {
        final floor = floors.firstWhere(
          (f) => f.id == floorId,
          orElse: () => floors.first,
        );
        resolvedFloor = floor.id;
        emit(state.copyWith(floors: floors, floorId: floor.id));
      }
    } catch (error) {
      AppLogger.warn('Floors unavailable for $buildingId: $error');
    }

    try {
      final plan = await _plans.planFor(buildingId, resolvedFloor);
      if (isClosed) return;
      if (plan == null || plan.storedRooms.isEmpty) {
        emit(
          state.copyWith(
            status: PlanEditorStatus.empty,
            buildingId: buildingId,
            floorId: resolvedFloor,
          ),
        );
        return;
      }
      emit(
        state.copyWith(
          status: PlanEditorStatus.ready,
          buildingId: buildingId,
          floorId: resolvedFloor,
          plan: plan,
          original: plan,
          selectedWingId: plan.wingIds.length > 1 ? plan.wingIds.last : null,
        ),
      );
    } catch (error, stack) {
      AppLogger.error('Plan load failed', error, stack);
      if (isClosed) return;
      emit(
        state.copyWith(
          status: PlanEditorStatus.empty,
          error: 'Could not open this floor.',
        ),
      );
    }
  }

  /// Opens another floor of the same building.
  ///
  /// Refuses while there are unsaved edits rather than discarding them — the
  /// screen offers to save first. Losing a wing alignment somebody spent five
  /// minutes on because they tapped a dropdown is not a trade worth making.
  Future<void> changeFloor(String floorId) async {
    if (floorId == state.floorId) return;
    if (state.isDirty) {
      emit(state.copyWith(hint: 'Save your changes before switching floor.'));
      return;
    }
    await load(buildingId: state.buildingId, floorId: floorId);
  }

  void selectWing(String? wingId) => emit(
    state.copyWith(selectedWingId: wingId, clearSelection: wingId == null),
  );

  void selectRoom(String? roomId) => emit(
    state.copyWith(selectedRoomId: roomId, clearRoomSelection: roomId == null),
  );

  /// Drags the selected wing by [delta], in plan units.
  void nudgeWing(Offset delta) {
    final wingId = state.selectedWingId;
    if (wingId == null) return;
    emit(
      state.copyWith(
        plan: state.plan.placeWing(
          wingId,
          state.placementOf(wingId).movedBy(delta),
        ),
      ),
    );
  }

  /// Rotates the selected wing about the plan origin.
  ///
  /// About the origin rather than the wing's own centre, deliberately: rotating
  /// about a moving centre makes the drag and the rotate interact, so nudging
  /// after rotating moves the wing somewhere the contributor did not point.
  /// Rotate-then-translate composes predictably, which is what a hand
  /// adjustment needs.
  void rotateWing(double radians) {
    final wingId = state.selectedWingId;
    if (wingId == null) return;
    emit(
      state.copyWith(
        plan: state.plan.placeWing(
          wingId,
          state.placementOf(wingId).rotatedBy(radians),
        ),
      ),
    );
  }

  /// Squares the selected wing's corridor against the nearest corridor
  /// elsewhere on the floor, when the two are already close.
  ///
  /// The assist that makes hand alignment tolerable: a wing dragged to within a
  /// few degrees is meant to be parallel, and eyeballing the last three degrees
  /// is exactly what a person is bad at.
  void snapWing() {
    final wingId = state.selectedWingId;
    if (wingId == null) return;

    final correction = state.snapCorrectionFor(wingId);
    if (correction == null) {
      emit(state.copyWith(hint: 'No nearby corridor to square up against.'));
      return;
    }

    emit(
      state.copyWith(
        plan: state.plan.placeWing(
          wingId,
          state.placementOf(wingId).rotatedBy(correction),
        ),
        hint: 'Squared up.',
      ),
    );
  }

  /// Squares every room on the floor onto one shared grid — see [squareFloor].
  ///
  /// Distinct from [snapWing], which rotates one *wing* against a neighbouring
  /// corridor. This touches every room's corners, because the fault it fixes is
  /// that each room was cleaned against its own axis at trace time and so no
  /// two of them quite agree.
  ///
  /// Offered rather than run on save: it rewrites traced geometry, and a
  /// contributor who can see the building is the only one who can say whether
  /// the result is still their floor. [undoSquaring] puts it back.
  void squareUpFloor() {
    final squared = squareFloor(state.plan);
    if (squared == state.plan) {
      emit(state.copyWith(hint: 'Nothing to square up on this floor.'));
      return;
    }
    _beforeSquaring = state.plan;
    emit(
      state.copyWith(
        plan: squared,
        hint: 'Floor squared up. Undo if it is not right.',
      ),
    );
  }

  /// Opens [roomId]'s points for dragging, or closes editing when null.
  void editShape(String? roomId) => emit(
    state.copyWith(
      editingRoomId: roomId,
      clearEditing: roomId == null,
      hint: roomId == null
          ? null
          : 'Drag a point to move it. Tap one to trim or remove it.',
    ),
  );

  void selectPoint(int? index) =>
      emit(state.copyWith(selectedPoint: index, clearEditing: index == null &&
          state.editingRoomId == null));

  // --- reshaping what was traced ------------------------------------------
  //
  // Every one of these goes through [plan_editing.dart], which refuses an edit
  // that would leave a room without a shape rather than applying it. So the
  // "nothing moved" branch below is a real outcome and has to say why, or the
  // contributor drags again harder and assumes the app is broken.

  void movePoint(String roomId, int index, Offset to) {
    final room = _roomOf(roomId);
    if (room == null) return;
    _applyEdit(
      room.hasSpine
          ? moveCorridorPoint(state.plan, roomId, index, to)
          : moveRoomCorner(state.plan, roomId, index, to),
      refused: 'That would fold the room in on itself.',
    );
  }

  void deletePoint(String roomId, int index) {
    final room = _roomOf(roomId);
    if (room == null) return;
    _applyEdit(
      room.hasSpine
          ? deleteCorridorPoint(state.plan, roomId, index)
          : deleteRoomCorner(state.plan, roomId, index),
      refused: room.hasSpine
          ? 'A corridor needs at least two points.'
          : 'A room needs at least three corners.',
    );
  }

  /// Drops the run of corridor past [index] — the fix for one traced further
  /// than the building goes.
  void trimAfter(String roomId, int index) => _applyEdit(
    trimCorridorAfter(state.plan, roomId, index),
    refused: 'Nothing to trim past that point.',
  );

  void trimBefore(String roomId, int index) => _applyEdit(
    trimCorridorBefore(state.plan, roomId, index),
    refused: 'Nothing to trim before that point.',
  );

  /// Adds a corner halfway along the wall leaving [index], ready to be dragged.
  void addCorner(String roomId, int index) => _applyEdit(
    insertRoomCorner(state.plan, roomId, index),
    refused: 'Could not add a corner there.',
  );

  /// The room as stored, which is the frame every edit below writes into.
  Room? _roomOf(String roomId) => state.plan.storedRoomOf(roomId);

  void _applyEdit(EditedPlan edited, {required String refused}) {
    if (edited.plan == state.plan) {
      emit(state.copyWith(hint: refused));
      return;
    }
    final dropped = edited.doorsDropped;
    emit(
      state.copyWith(
        plan: edited.plan,
        // Named because a door disappearing without a word is the kind of loss
        // somebody finds weeks later, walking a route that no longer exists.
        hint: dropped == 0
            ? null
            : '$dropped door${dropped == 1 ? "" : "s"} removed — '
                  'nothing was left to open onto.',
      ),
    );
  }

  /// Puts the floor back exactly as it was the moment before [squareUpFloor].
  ///
  /// The whole plan, not a field of it. [squareFloor] bakes each wing's
  /// placement into the corners it welds, so afterwards there is no separating
  /// "the geometry" from "where the wings were put" — restoring stored rooms
  /// alone would send every wing back to where it was captured and lose an
  /// alignment the contributor may have spent minutes on, and restoring the
  /// placements alone would apply that alignment on top of geometry that
  /// already contains it.
  void undoSquaring() {
    final before = _beforeSquaring;
    if (before == null) {
      emit(state.copyWith(hint: 'Nothing to put back.'));
      return;
    }
    _beforeSquaring = null;
    emit(
      state.copyWith(plan: before, hint: 'Back to the geometry as traced.'),
    );
  }

  /// Puts the selected wing back where its rooms were actually drawn.
  ///
  /// The answer to "this is not a separate wing" — a board re-photographed and
  /// mistaken for a second one, or work parked by a tracer that used to park on
  /// every visit. Its rooms are stored at the coordinates they were traced at,
  /// so clearing the placement is all it takes to land them where the
  /// contributor put them.
  ///
  /// [resetWing] cannot do this job. It restores the placement the plan was
  /// *loaded* with, and a wing that arrived parked was loaded parked — resetting
  /// it is a no-op at exactly the moment somebody needs it undone.
  void unparkWing() {
    final wingId = state.selectedWingId;
    if (wingId == null) return;
    if (state.placementOf(wingId).isIdentity) {
      emit(state.copyWith(hint: 'That wing is already on the floor.'));
      return;
    }
    emit(
      state.copyWith(
        plan: state.plan.placeWing(wingId, const WingPlacement()),
        hint: 'Put back where it was traced.',
      ),
    );
  }

  void resetWing() {
    final wingId = state.selectedWingId;
    if (wingId == null) return;
    emit(
      state.copyWith(
        plan: state.plan.placeWing(
          wingId,
          state.original.wings[wingId] ?? const WingPlacement(),
        ),
      ),
    );
  }

  /// Removes a room and every door that led to it.
  ///
  /// The doors matter as much as the room: an opening naming a room that no
  /// longer exists keeps counting towards a corridor's declared total, so the
  /// door ordinals stay wrong with nothing on screen to explain why.
  void deleteRoom(String roomId) {
    emit(
      state.copyWith(
        plan: state.plan.copyWith(
          storedRooms: [
            for (final room in state.plan.storedRooms)
              if (room.id != roomId) room,
          ],
          storedOpenings: [
            for (final opening in state.plan.storedOpenings)
              if (!opening.touches(roomId)) opening,
          ],
        ),
        clearRoomSelection: true,
      ),
    );
  }

  void editRoom(String roomId, {RoomCategory? category, String? label}) {
    emit(
      state.copyWith(
        plan: state.plan.copyWith(
          storedRooms: [
            for (final room in state.plan.storedRooms)
              if (room.id == roomId)
                room.copyWith(
                  category: category ?? room.category,
                  label: label == null
                      ? room.label
                      : (label.trim().isEmpty ? null : label.trim()),
                )
              else
                room,
          ],
        ),
      ),
    );
  }

  void removeDoor(String openingId) {
    emit(
      state.copyWith(
        plan: state.plan.copyWith(
          storedOpenings: [
            for (final opening in state.plan.storedOpenings)
              if (opening.id != openingId) opening,
          ],
        ),
      ),
    );
  }

  /// Joins two rooms that share a wall but have no door — the missing-connection
  /// prompt from spec §8, accepted.
  void addDoorBetween(String roomAId, String roomBId, Offset at) {
    if (state.plan.storedOpenings.any(
      (o) => o.touches(roomAId) && o.touches(roomBId),
    )) {
      return;
    }
    emit(
      state.copyWith(
        plan: state.plan.copyWith(
          storedOpenings: [
            ...state.plan.storedOpenings,
            Opening(
              id: 'door-${state.plan.highestIdSuffix + 1}',
              roomAId: roomAId,
              roomBId: roomBId,
              at: RoomCorner.of(at),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> save() async {
    if (state.plan.drawableRooms.isEmpty) return;
    emit(state.copyWith(status: PlanEditorStatus.saving));
    try {
      await _plans.save(state.plan);
      if (isClosed) return;
      emit(
        state.copyWith(status: PlanEditorStatus.saved, original: state.plan),
      );
    } catch (error, stack) {
      AppLogger.error('Plan save failed', error, stack);
      if (isClosed) return;
      emit(
        state.copyWith(
          status: PlanEditorStatus.ready,
          error: 'Could not save. Your changes are still here — try again.',
        ),
      );
    }
  }
}
