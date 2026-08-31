import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../../core/models/building.dart';
import '../../../core/models/room_plan.dart';
import '../../../data/repository_mixin.dart';
import '../../../services/mapping/floor_label.dart';
import '../../../services/mapping/floor_mapping_status.dart';
import '../../buildings/building_repository.dart';
import '../../room_trace/room_plan_repository.dart';

part 'maps_event.dart';
part 'maps_state.dart';

/// The Maps tab: the traced floors this phone can walk, grouped by building.
///
/// It used to list *bookmarked buildings*, which was a list of places somebody
/// had tapped a bookmark on — not a list of anything walkable. A building could
/// sit here with no floor traced at all, and the floors that were traced
/// appeared nowhere in the app outside the contributor hub. So the tab is now
/// the plans themselves: one section per building, one row per floor, and the
/// row walks it.
///
/// The building index is a *decoration* here, not a dependency. Names and floor
/// labels make the list readable, and every one of them is optional: this is
/// the screen a person opens in a basement with no signal, and it has to render
/// from what is on the device.
class MapsBloc extends Bloc<MapsEvent, MapsState> {
  MapsBloc(this._buildings, this._plans) : super(const MapsState()) {
    on<MapsStarted>(_onStarted);
    on<MapsFloorDeleted>(_onFloorDeleted);
  }

  final BuildingRepository _buildings;
  final RoomPlanRepository _plans;

  Future<void> _onStarted(MapsStarted event, Emitter<MapsState> emit) async {
    emit(state.copyWith(status: MapsStatus.loading));
    try {
      final plans = await _plans.allPlans();
      final grouped = <String, List<RoomPlan>>{};
      for (final plan in plans) {
        // An empty floor is a plan record with nothing traced into it. It is
        // not a map and cannot be walked, so it is not on the list.
        if (plan.isEmpty) continue;
        grouped.putIfAbsent(plan.buildingId, () => []).add(plan);
      }

      final mapped = <MappedBuilding>[];
      for (final entry in grouped.entries) {
        mapped.add(await _describe(entry.key, entry.value));
      }
      // Most floors first: the building somebody has actually worked on is the
      // one they came here for.
      mapped.sort((a, b) {
        final byFloors = b.floors.length.compareTo(a.floors.length);
        return byFloors != 0 ? byFloors : a.name.compareTo(b.name);
      });

      emit(state.copyWith(status: MapsStatus.success, buildings: mapped));
    } catch (error) {
      // Broad on purpose: a narrow catch let Supabase, socket and
      // Hive errors escape, and a Bloc that never emits leaves the
      // screen spinning forever.
      emit(
        state.copyWith(
          status: MapsStatus.failure,
          error: OperationFailure.from(error).message,
        ),
      );
    }
  }

  /// Deletes one traced floor, then reloads.
  ///
  /// Reloading rather than removing the row locally: a building whose last
  /// floor has gone should disappear from the list entirely, and re-deriving
  /// that from the store is simpler than maintaining it by hand.
  Future<void> _onFloorDeleted(
    MapsFloorDeleted event,
    Emitter<MapsState> emit,
  ) async {
    try {
      await _plans.delete(event.buildingId, event.floorId);
    } catch (error) {
      emit(
        state.copyWith(
          status: MapsStatus.success,
          error: OperationFailure.from(error).message,
        ),
      );
      return;
    }
    await _onStarted(const MapsStarted(), emit);
  }

  /// Names one building's floors as well as the device currently can.
  ///
  /// Both lookups are allowed to fail without taking the section with them —
  /// a traced floor is still walkable when the index that would have named its
  /// building is unreachable.
  Future<MappedBuilding> _describe(
    String buildingId,
    List<RoomPlan> plans,
  ) async {
    String name = buildingId;
    String? area;
    var labels = <String, String>{};

    try {
      final building = await _buildings.byId(buildingId);
      name = building.name;
      area = building.area;
    } catch (_) {
      // Offline, or a building traced before it reached the index.
    }
    try {
      labels = {
        for (final floor in await _buildings.floorsOf(buildingId))
          floor.id: floor.label,
      };
    } catch (_) {
      // Fall through to the floor id, which [MappedFloor.label] can read.
    }

    final floors = [
      for (final plan in plans)
        MappedFloor(plan: plan, storedLabel: labels[plan.floorId]),
    ]..sort((a, b) => a.label.compareTo(b.label));

    return MappedBuilding(
      id: buildingId,
      name: name,
      area: area,
      floors: floors,
    );
  }
}
