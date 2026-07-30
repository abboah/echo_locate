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
      emit(state.copyWith(
        status: BuildingDetailStatus.success,
        building: building,
        floors: floors,
        selectedFloor: floors.length > 1 ? 1 : 0,
      ));
    } on OperationFailure catch (f) {
      emit(state.copyWith(
        status: BuildingDetailStatus.failure,
        error: f.message,
      ));
    }
  }

  void _onFloorSelected(
    BuildingDetailFloorSelected event,
    Emitter<BuildingDetailState> emit,
  ) {
    emit(state.copyWith(selectedFloor: event.index));
  }
}
