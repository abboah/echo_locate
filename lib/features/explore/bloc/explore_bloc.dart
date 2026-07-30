import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../../core/models/building.dart';
import '../../../data/repository_mixin.dart';
import '../../buildings/building_repository.dart';

part 'explore_event.dart';
part 'explore_state.dart';

class ExploreBloc extends Bloc<ExploreEvent, ExploreState> {
  ExploreBloc(this._buildings) : super(const ExploreState()) {
    on<ExploreStarted>(_onLoad);
    on<ExploreCategoryChanged>(_onCategory);
    on<ExploreQueryChanged>(_onQuery);
  }

  final BuildingRepository _buildings;

  Future<void> _onLoad(ExploreStarted event, Emitter<ExploreState> emit) =>
      _load(emit, category: state.category, query: state.query);

  Future<void> _onCategory(
    ExploreCategoryChanged event,
    Emitter<ExploreState> emit,
  ) =>
      _load(emit, category: event.category, query: state.query);

  Future<void> _onQuery(
    ExploreQueryChanged event,
    Emitter<ExploreState> emit,
  ) =>
      _load(emit, category: state.category, query: event.query);

  Future<void> _load(
    Emitter<ExploreState> emit, {
    required String category,
    required String query,
  }) async {
    emit(state.copyWith(
      status: ExploreStatus.loading,
      category: category,
      query: query,
    ));
    try {
      final results = await _buildings.nearby(category: category, query: query);
      emit(state.copyWith(status: ExploreStatus.success, buildings: results));
    } on OperationFailure catch (f) {
      emit(state.copyWith(status: ExploreStatus.failure, error: f.message));
    }
  }
}
