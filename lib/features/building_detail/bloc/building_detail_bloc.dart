import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../../core/models/building.dart';
import '../../../data/repository_mixin.dart';
import '../../buildings/building_repository.dart';

part 'building_detail_event.dart';
part 'building_detail_state.dart';

class BuildingDetailBloc
    extends Bloc<BuildingDetailEvent, BuildingDetailState> {
  BuildingDetailBloc(this._buildings) : super(const BuildingDetailState()) {
    on<BuildingDetailStarted>(_onStarted);
    on<BuildingDetailFloorSelected>(_onFloorSelected);
    on<BuildingDetailSaveToggled>(_onSaveToggled);
  }

  final BuildingRepository _buildings;

  Future<void> _onStarted(
    BuildingDetailStarted event,
    Emitter<BuildingDetailState> emit,
  ) async {
    emit(state.copyWith(status: BuildingDetailStatus.loading));
    try {
      // Prefer the object passed via route `extra` (instant nav from a list);
      // fall back to fetching by id (deep link / restart).
      final building = event.building ?? await _buildings.byId(event.buildingId);
      final floors = await _buildings.floorsOf(building.id);
      final saved = await _buildings.isSaved(building.id);
      emit(state.copyWith(
        status: BuildingDetailStatus.success,
        building: building,
        floors: floors,
        selectedFloor: floors.length > 1 ? 1 : 0,
        saved: saved,
      ));
    } catch (error) {
      // Broad on purpose: catching only OperationFailure let a Hive cache
      // error escape, and this screen sat on its spinner with the floors
      // already fetched and sitting in memory.
      emit(state.copyWith(
        status: BuildingDetailStatus.failure,
        error: OperationFailure.from(error).message,
      ));
    }
  }

  void _onFloorSelected(
    BuildingDetailFloorSelected event,
    Emitter<BuildingDetailState> emit,
  ) {
    emit(state.copyWith(selectedFloor: event.index));
  }

  Future<void> _onSaveToggled(
    BuildingDetailSaveToggled event,
    Emitter<BuildingDetailState> emit,
  ) async {
    final building = state.building;
    if (building == null) return;
    final next = !state.saved;
    // Optimistic: the bookmark flips immediately and reverts if the write
    // fails, so a slow connection never feels like an unresponsive button.
    emit(state.copyWith(saved: next));
    try {
      await _buildings.setSaved(building.id, next);
    } catch (error) {
      emit(state.copyWith(
        saved: !next,
        error: OperationFailure.from(error).message,
      ));
    }
  }
}
