import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../../core/models/building.dart';
import '../../../data/repository_mixin.dart';
import '../../buildings/building_repository.dart';

part 'maps_event.dart';
part 'maps_state.dart';

class MapsBloc extends Bloc<MapsEvent, MapsState> {
  MapsBloc(this._buildings) : super(const MapsState()) {
    on<MapsStarted>(_onStarted);
  }

  final BuildingRepository _buildings;

  Future<void> _onStarted(MapsStarted event, Emitter<MapsState> emit) async {
    emit(state.copyWith(status: MapsStatus.loading));
    try {
      final saved = await _buildings.savedMaps();
      emit(state.copyWith(status: MapsStatus.success, saved: saved));
    } on OperationFailure catch (f) {
      emit(state.copyWith(status: MapsStatus.failure, error: f.message));
    }
  }
}
