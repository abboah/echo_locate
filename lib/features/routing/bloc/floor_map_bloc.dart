import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../../core/models/landmark.dart';
import '../../../core/models/walk_route.dart';
import '../../../core/utils/logger.dart';
import '../../../services/mapping/floor_graph.dart';
import '../../../services/mapping/route_planner.dart';
import '../../buildings/building_repository.dart';
import '../route_repository.dart';

part 'floor_map_event.dart';
part 'floor_map_state.dart';

/// Turns a building's recorded walks into a map, and answers routes over it.
///
/// The screen this drives is for sighted contributors, for verifying a
/// capture, and for examiners — a blind user never sees it, and is served by
/// the same graph through voice. Both come from here, which is the point: the
/// picture and the spoken directions cannot disagree because they are the same
/// data structure.
class FloorMapBloc extends Bloc<FloorMapEvent, FloorMapState> {
  FloorMapBloc(
    this._routes, {
    BuildingRepository? buildings,
    RoutePlanner planner = const RoutePlanner(),
  })  : _buildings = buildings,
        _planner = planner,
        super(const FloorMapState()) {
    on<FloorMapRequested>(_onRequested);
    on<FloorMapFromSelected>(_onFromSelected);
    on<FloorMapToSelected>(_onToSelected);
  }

  final RouteRepository _routes;

  /// Only for the building's name, so a link straight to the map — from the
  /// Profile shortcuts, or a restored navigation stack — is not headed
  /// "Building". Optional: the map itself does not need it.
  final BuildingRepository? _buildings;

  final RoutePlanner _planner;

  Future<void> _onRequested(
    FloorMapRequested event,
    Emitter<FloorMapState> emit,
  ) async {
    // Clearing the error here is what makes "Try again" a real retry: without
    // it the message from the failed load outlives the load that succeeded.
    emit(
      state.copyWith(
        status: FloorMapStatus.loading,
        buildingId: event.buildingId,
        clearError: true,
      ),
    );
    try {
      final landmarks = await _routes.landmarksOf(event.buildingId);
      final plan = await _routes.tracedPlanOf(event.buildingId);
      final recorded = await _routes.routesOf(event.buildingId);

      // A traced plan wins over recorded walks. Both yield the same kind of
      // graph, but a plan's coordinates are read off the building's own posted
      // floor plan and are absolute, where a walk's are chained from step
      // counts and tapped turns and drift along the route. Where a building has
      // both, the accurate geometry is the one to draw and route over.
      final traced = plan != null && !plan.isEmpty;
      final graph =
          traced ? FloorGraph.fromPlan(plan) : FloorGraph.merge(recorded);

      // Best-effort: a missing name costs a heading, not the map.
      if (_buildings != null) {
        try {
          final building = await _buildings.byId(event.buildingId);
          if (!isClosed) emit(state.copyWith(buildingName: building.name));
        } catch (error) {
          AppLogger.warn('Building name unavailable: $error');
        }
      }

      if (graph.isEmpty) {
        emit(
          state.copyWith(
            status: FloorMapStatus.empty,
            landmarks: landmarks,
            routes: recorded,
            graph: graph,
          ),
        );
        return;
      }

      emit(
        state.copyWith(
          status: FloorMapStatus.ready,
          landmarks: landmarks,
          routes: recorded,
          graph: graph,
          // Where a visitor arrives. A recorded walk says so directly — its
          // first contributor started at the front door. A traced plan has no
          // walking order, so the entrance is found by kind, falling back to
          // any node on the map rather than leaving the picker empty.
          fromId: traced
              ? _entranceOf(graph, landmarks)
              : recorded.first.startLandmarkId,
        ),
      );
    } catch (e, stack) {
      AppLogger.error('Floor map load failed: $e', e, stack);
      emit(
        state.copyWith(
          status: FloorMapStatus.failure,
          error: 'Could not load this building’s map.',
        ),
      );
    }
  }

  /// The node a visitor most likely starts from on a traced plan.
  ///
  /// Returns null only for a graph with no nodes, which the caller has already
  /// ruled out — so the "where are you" picker always opens on something.
  static String? _entranceOf(FloorGraph graph, List<Landmark> landmarks) {
    for (final landmark in landmarks) {
      if (landmark.kind == LandmarkKind.entrance &&
          graph.nodes.containsKey(landmark.id)) {
        return landmark.id;
      }
    }
    return graph.nodes.keys.isEmpty ? null : graph.nodes.keys.first;
  }

  void _onFromSelected(
    FloorMapFromSelected event,
    Emitter<FloorMapState> emit,
  ) =>
      emit(_replanned(state.copyWith(fromId: event.landmarkId)));

  void _onToSelected(
    FloorMapToSelected event,
    Emitter<FloorMapState> emit,
  ) =>
      emit(_replanned(state.copyWith(toId: event.landmarkId)));

  FloorMapState _replanned(FloorMapState next) {
    final from = next.fromId;
    final to = next.toId;
    if (from == null || to == null || from == to) {
      return next.copyWith(clearPlan: true);
    }
    final plan = _planner.plan(next.graph, from: from, to: to);
    // A null plan is a real answer — these two landmarks are not connected by
    // anything anybody has walked — so it is shown, not treated as an error.
    return plan == null ? next.copyWith(clearPlan: true) : next.copyWith(plan: plan);
  }
}
