import 'dart:ui' show Offset;

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../../core/models/room_plan.dart';
import '../../../core/utils/logger.dart';
import '../../../services/mapping/room_directions.dart';
import '../../../services/mapping/room_graph.dart';
import '../../../services/mapping/room_plan_bridge.dart';
import '../../guidance/guidance_session.dart';
import '../../profile/profile_repository.dart';
import '../../room_trace/room_plan_repository.dart';

part 'room_navigate_state.dart';

/// Navigating a traced or captured floor.
///
/// The join that was missing. `RoomPlanBridge` could turn a [RoomPlan] into
/// everything `GuidanceBloc` consumes, and nothing called it — so a floor could
/// be mapped in full and then not walked, which is the entire point of mapping
/// it. This screen is the caller.
///
/// It does not reimplement guidance. It assembles a [GuidanceSession] and hands
/// it to the same screen that guides a recorded walk, so a room plan and a
/// contributor's recording are followed by identical code. The door-counted
/// sentence rides in as a leg's instruction and is spoken verbatim.
class RoomNavigateCubit extends Cubit<RoomNavigateState> {
  RoomNavigateCubit(this._plans, [this._profiles])
    : super(const RoomNavigateState());

  final RoomPlanRepository _plans;

  /// Optional so the screen can be tested without one. Used for a single
  /// question: has this user measured their step? Guidance divides every leg
  /// through that number, so on a floor with a scale it is the difference
  /// between a spoken distance that is theirs and one that is a generic
  /// adult's — and the walk screen is the first place that matters.
  final ProfileRepository? _profiles;

  /// Opens [floorId] of [buildingId], ready to walk.
  ///
  /// [destinationRoomId] is set when the user already said where they were
  /// going — they tapped a room on the building screen — so the screen opens
  /// on that route rather than asking them to pick it a second time. A room id
  /// this floor does not contain is ignored rather than fatal: the plan may
  /// have been retraced since the link was made, and landing on the floor with
  /// a sensible default beats an error about a room.
  Future<void> load({
    required String buildingId,
    required String floorId,
    String? destinationRoomId,
  }) async {
    emit(state.copyWith(status: RoomNavigateStatus.loading));
    try {
      final plan = await _plans.planFor(buildingId, floorId);
      if (isClosed) return;

      if (plan == null || plan.drawableRooms.length < 2) {
        emit(
          state.copyWith(
            status: RoomNavigateStatus.empty,
            buildingId: buildingId,
            floorId: floorId,
          ),
        );
        return;
      }

      final rooms = plan.drawableRooms.toList()
        ..sort((a, b) => a.spokenName.compareTo(b.spokenName));
      // Somewhere to start and somewhere to go, chosen so the screen opens
      // with a route drawn rather than two empty pickers.
      final from = rooms.firstWhere(
        (room) => !room.isCirculation,
        orElse: () => rooms.first,
      );
      final asked = destinationRoomId == null
          ? null
          : rooms.where((room) => room.id == destinationRoomId).firstOrNull;
      final to =
          asked ??
          rooms.lastWhere(
            (room) => !room.isCirculation && room.id != from.id,
            orElse: () => rooms.last,
          );
      // Starting where you are going is not a route. When the tapped room
      // happens to be the default origin, the origin moves instead — the
      // destination is the part the user actually chose.
      final origin = from.id == to.id
          ? rooms.firstWhere(
              (room) => !room.isCirculation && room.id != to.id,
              orElse: () => rooms.firstWhere(
                (room) => room.id != to.id,
                orElse: () => from,
              ),
            )
          : from;

      emit(
        state.copyWith(
          status: RoomNavigateStatus.ready,
          buildingId: buildingId,
          floorId: floorId,
          plan: plan,
          fromRoomId: origin.id,
          toRoomId: to.id,
        ),
      );

      // After the screen is up, never before: it is a hint, and nothing about
      // the route waits on it.
      await refreshStride();
    } catch (error, stack) {
      AppLogger.error('Room navigation load failed', error, stack);
      if (isClosed) return;
      emit(
        state.copyWith(
          status: RoomNavigateStatus.empty,
          error: 'Could not open this floor.',
        ),
      );
    }
  }

  /// Re-reads whether the user has measured their step.
  ///
  /// Called on open and again on returning from the calibration screen, so the
  /// prompt disappears the moment it has been answered.
  Future<void> refreshStride() async {
    final profiles = _profiles;
    if (profiles == null) return;
    try {
      final metres = (await profiles.currentProfile()).strideLengthM;
      if (isClosed) return;
      emit(state.copyWith(strideCalibrated: metres != null));
    } catch (_) {
      // Offline or signed out. The prompt stays hidden rather than nagging
      // somebody who cannot act on it.
    }
  }

  void selectFrom(String roomId) => emit(state.copyWith(fromRoomId: roomId));

  void selectTo(String roomId) => emit(state.copyWith(toRoomId: roomId));

  /// Swaps the ends. Walking back is a different route, not the same one
  /// reversed — every ordinal and every turn changes with the heading.
  void reverse() => emit(
    state.copyWith(fromRoomId: state.toRoomId, toRoomId: state.fromRoomId),
  );

  /// Everything `GuidanceBloc` needs, or null when there is no route.
  ///
  /// Built here rather than in the screen so the assembly is testable without
  /// a widget tree — it is the piece that has to be right for anything to be
  /// spoken at all.
  GuidanceSession? sessionFor({Offset? initialHeading}) {
    final plan = state.plan;
    final from = state.fromRoomId;
    final to = state.toRoomId;
    if (plan == null || from == null || to == null || from == to) return null;

    final route = RoomPlanBridge.plannedRouteFrom(
      plan,
      fromRoomId: from,
      toRoomId: to,
      initialHeading: initialHeading,
    );
    if (route == null) return null;

    return GuidanceSession(
      plan: route,
      landmarks: RoomPlanBridge.landmarksFrom(plan),
      destinationName: plan.roomOf(to)?.spokenName ?? 'your destination',
      // The whole floor, so a user who has walked into the wrong corridor can
      // be relocated against any room on it rather than only this route's.
      graph: RoomPlanBridge.floorGraphFrom(plan),
      // A traced plan nobody measured routes correctly and cannot be spoken in
      // metres; guidance leans on reading the door plate instead.
      metric: plan.isMetric,
      // The line itself, for the AR layer to lay into the room. Null on a plan
      // with no scale — see [RoomPlanBridge.routePathFrom].
      routePath: RoomPlanBridge.routePathFrom(
        plan,
        fromRoomId: from,
        toRoomId: to,
      ),
      // The floor itself, so the guidance screen can draw the route through
      // the rooms it passes rather than across an empty card.
      floorPlan: plan,
    );
  }
}
