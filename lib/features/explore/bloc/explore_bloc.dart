import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../../core/models/building.dart';
import '../../../data/repository_mixin.dart';
import '../../../services/location/location_service.dart';
import '../../buildings/building_repository.dart';

part 'explore_event.dart';
part 'explore_state.dart';

class ExploreBloc extends Bloc<ExploreEvent, ExploreState> {
  ExploreBloc(this._buildings, this._location) : super(const ExploreState()) {
    on<ExploreStarted>(_onLoad);
    on<ExploreCategoryChanged>(_onCategory);
    on<ExploreQueryChanged>(_onQuery);
  }

  final BuildingRepository _buildings;
  final LocationService _location;

  Future<void> _onLoad(ExploreStarted event, Emitter<ExploreState> emit) =>
      _load(emit, category: state.category, query: state.query);

  Future<void> _onCategory(
    ExploreCategoryChanged event,
    Emitter<ExploreState> emit,
  ) => _load(emit, category: event.category, query: state.query);

  Future<void> _onQuery(
    ExploreQueryChanged event,
    Emitter<ExploreState> emit,
  ) => _load(emit, category: state.category, query: event.query);

  Future<void> _load(
    Emitter<ExploreState> emit, {
    required String category,
    required String query,
  }) async {
    emit(
      state.copyWith(
        status: ExploreStatus.loading,
        category: category,
        query: query,
      ),
    );
    try {
      // Taken before the query so the list is ordered around where the user
      // actually is. Null when location was refused or is unavailable, which
      // the server reads as "measure from the default origin" — the behaviour
      // every user got, unconditionally, before this was wired up.
      final position = await _location.current();
      // "Saved" is not a kind of building, so it cannot be answered by the
      // same query as the others. The search box still applies to it — a
      // bookmark list somebody cannot search is one they scroll.
      final results = category == savedCategory
          ? _matching(await _buildings.savedMaps(), query)
          : await _buildings.nearby(
              category: category,
              query: query,
              latitude: position?.latitude,
              longitude: position?.longitude,
            );
      emit(
        state.copyWith(
          status: ExploreStatus.success,
          buildings: results,
          located: position != null,
        ),
      );
    } catch (error) {
      // Broad on purpose: a narrow catch let Supabase, socket and
      // Hive errors escape, and a Bloc that never emits leaves the
      // screen spinning forever.
      emit(
        state.copyWith(
          status: ExploreStatus.failure,
          error: OperationFailure.from(error).message,
        ),
      );
    }
  }

  /// Name-or-area match, matching what `nearby` does for the other chips so
  /// searching does not mean something different once "Saved" is selected.
  static List<Building> _matching(List<Building> buildings, String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return buildings;
    return [
      for (final building in buildings)
        if (building.name.toLowerCase().contains(needle) ||
            building.area.toLowerCase().contains(needle))
          building,
    ];
  }
}
