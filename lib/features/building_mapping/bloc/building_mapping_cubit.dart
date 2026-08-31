import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../../core/models/room_plan.dart';
import '../../../core/utils/logger.dart';
import '../../../services/mapping/floor_mapping_status.dart';
import '../../buildings/building_repository.dart';
import '../../room_trace/room_plan_repository.dart';

part 'building_mapping_state.dart';

/// The state of one building's mapping, floor by floor.
///
/// The thing the feature was missing. Every screen under it was capable and
/// none of them sequenced: a contributor arriving at "I want to map this
/// building" met a list of tools rather than a task, with nothing to say which
/// floor to do next, what was half-finished, or when they could stop.
///
/// Nothing here is stored. A floor's state is computed from its plan every time
/// it is read, so it cannot fall out of step with the geometry — including
/// after somebody else edits the same building.
class BuildingMappingCubit extends Cubit<BuildingMappingState> {
  BuildingMappingCubit(this._buildings, this._plans)
    : super(const BuildingMappingState());

  final BuildingRepository _buildings;
  final RoomPlanRepository _plans;

  Future<void> load(String buildingId) async {
    emit(state.copyWith(status: BuildingMappingStatus.loading));

    try {
      final floors = await _buildings.floorsOf(buildingId);
      if (isClosed) return;

      final statuses = <FloorMappingStatus>[];
      for (final floor in floors) {
        // Sequential rather than concurrent. A building has a handful of
        // floors and the repository is offline-first, so the round trips are
        // cheap — and a failure part-way leaves a partial list rather than
        // taking the whole screen down.
        statuses.add(
          FloorMappingStatus.of(floor, await _planFor(buildingId, floor.id)),
        );
      }
      if (isClosed) return;

      emit(
        state.copyWith(
          status: BuildingMappingStatus.ready,
          buildingId: buildingId,
          progress: BuildingMappingProgress(statuses),
        ),
      );
    } catch (error, stack) {
      AppLogger.error('Building mapping load failed', error, stack);
      if (isClosed) return;
      emit(
        state.copyWith(
          status: BuildingMappingStatus.failed,
          error: 'Could not load this building.',
        ),
      );
    }
  }

  /// A floor whose plan will not load is treated as unmapped rather than as an
  /// error — the rest of the building is still worth showing, and the fix is to
  /// map it anyway.
  Future<RoomPlan?> _planFor(String buildingId, String floorId) async {
    try {
      return await _plans.planFor(buildingId, floorId);
    } catch (error) {
      AppLogger.warn('Plan unavailable for $floorId: $error');
      return null;
    }
  }

  /// Re-reads everything. Called when returning from a capture or an edit,
  /// because the floor that was just worked on has changed underneath.
  Future<void> refresh() =>
      state.buildingId.isEmpty ? Future.value() : load(state.buildingId);
}
