import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../../core/models/building.dart' show BuildingFloor;
import '../../../core/models/room_plan.dart';
import '../../../core/utils/logger.dart';
import '../../../services/mapping/floor_squaring.dart';
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

  Future<void> load({
    required String buildingId,
    required String floorId,
  }) async {
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
    emit(
      state.copyWith(
        plan: squared,
        hint: 'Floor squared up. Undo if it is not right.',
      ),
    );
  }

  /// Restores the geometry exactly as it was traced.
  ///
  /// Rooms and openings only: a wing the contributor has since dragged into
  /// place is their work, not the squaring's, and throwing it away because they
  /// disliked the snap would cost them the alignment too.
  void undoSquaring() {
    emit(
      state.copyWith(
        plan: state.plan.copyWith(
          storedRooms: state.original.rooms,
          storedOpenings: state.original.openings,
        ),
        hint: 'Back to the geometry as traced.',
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
