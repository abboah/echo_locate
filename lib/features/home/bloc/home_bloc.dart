import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../../core/models/building.dart';
import '../../../data/repository_mixin.dart';
import '../../buildings/building_repository.dart';

part 'home_event.dart';
part 'home_state.dart';

class HomeBloc extends Bloc<HomeEvent, HomeState> {
  HomeBloc(this._buildings) : super(const HomeState()) {
    on<HomeStarted>(_onStarted);
  }

  final BuildingRepository _buildings;

  Future<void> _onStarted(HomeStarted event, Emitter<HomeState> emit) async {
    emit(state.copyWith(status: HomeStatus.loading));
    try {
      final recent = await _buildings.recentlyMapped();
      emit(state.copyWith(status: HomeStatus.success, recent: recent));
    } catch (error) {
      // Broad on purpose: a narrow catch let Supabase, socket and
      // Hive errors escape, and a Bloc that never emits leaves the
      // screen spinning forever.
      emit(state.copyWith(
        status: HomeStatus.failure,
        error: OperationFailure.from(error).message,
      ));
    }
  }
}
