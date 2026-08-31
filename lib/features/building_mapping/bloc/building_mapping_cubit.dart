import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../../core/models/building.dart';
import '../../../core/models/room_plan.dart';
import '../../../core/utils/logger.dart';
import '../../../services/mapping/floor_mapping_status.dart';
import '../../buildings/building_repository.dart';
import '../../room_trace/room_plan_repository.dart';

part 'building_mapping_state.dart';

/// One building: what it is called, and where each of its floors stands.
///
/// **This is now the building screen**, not just a contributor hub. Tapping a
/// building anywhere in the app lands here. There used to be a separate detail
/// screen in front of it — a hero, a room list and a "Floors and plans" button
/// that led here anyway — so seeing a building's floors took two taps through a
/// screen whose own room list came from a table nothing writes to.
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

      // The building itself, for the header. Tolerated separately: a building
      // whose index row cannot be read still has floors worth showing, and the
      // screen falls back to whatever name it was opened with.
      Building? building;
      var saved = false;
      try {
        building = await _buildings.byId(buildingId);
        saved = await _buildings.isSaved(buildingId);
      } catch (error) {
        AppLogger.warn('Building details unavailable: $error');
      }
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
          building: building,
          saved: saved,
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

  /// Keeps this building for offline use, or stops.
  Future<void> toggleSaved() async {
    final id = state.buildingId;
    if (id.isEmpty) return;
    final next = !state.saved;
    // Optimistic: the bookmark flips at once and reverts if the write fails,
    // so a slow connection never reads as an unresponsive button.
    emit(state.copyWith(saved: next));
    try {
      await _buildings.setSaved(id, next);
    } catch (error) {
      AppLogger.warn('Could not save $id: $error');
      if (isClosed) return;
      emit(
        state.copyWith(saved: !next, error: 'Could not save this building.'),
      );
    }
  }

  /// Renames the building.
  ///
  /// The index is crowdsourced, so a building's name is whatever the first
  /// contributor typed — often a working title, sometimes simply wrong. Before
  /// this the only remedy was to add a second building beside the first and
  /// leave both in the list.
  ///
  /// The **id does not change**: it is the key every floor, traced plan and
  /// bookmark already points at, so re-slugging on rename would orphan the very
  /// work being corrected.
  Future<bool> rename({required String name, String? area}) async {
    final id = state.buildingId;
    if (id.isEmpty) return false;
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      emit(state.copyWith(error: 'A building needs a name.'));
      return false;
    }
    if (trimmed == state.building?.name &&
        (area == null || area.trim().isEmpty)) {
      return true;
    }

    try {
      final renamed = await _buildings.rename(id, name: trimmed, area: area);
      if (isClosed) return false;
      emit(state.copyWith(building: renamed));
      return true;
    } catch (error, stack) {
      AppLogger.error('Rename failed for $id', error, stack);
      if (isClosed) return false;
      emit(state.copyWith(error: 'Could not rename this building.'));
      return false;
    }
  }
}
