import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../../core/models/building.dart';
import '../../../core/models/landmark.dart';
import '../../../core/models/walk_route.dart';
import '../../../data/repository_mixin.dart';
import '../../../services/mapping/floor_graph.dart';
import '../../../services/mapping/map_node.dart';
import '../../../services/mapping/route_planner.dart';
import '../../../services/speech/speech_service.dart';
import '../../buildings/building_repository.dart';
import '../route_repository.dart';

part 'floor_plan_event.dart';
part 'floor_plan_state.dart';

/// Owns the 2D plan for one building: loads its landmarks and routes, merges
/// them into a graph, and plans journeys across it.
///
/// The merge and the planner are built once per load rather than per frame —
/// the graph does not change while the screen is open, and rebuilding it on
/// every floor tap would be work for nothing.
class FloorPlanBloc extends Bloc<FloorPlanEvent, FloorPlanState> {
  FloorPlanBloc(this._routes, this._buildings, [this._speech])
      : super(const FloorPlanState()) {
    on<FloorPlanStarted>(_onStarted);
    on<FloorPlanFloorSelected>(_onFloorSelected);
    on<FloorPlanDestinationSelected>(_onDestinationSelected);
    on<FloorPlanPositionChanged>(_onPositionChanged);
    on<FloorPlanRouteCleared>(_onRouteCleared);
    on<FloorPlanVoiceToggled>(_onVoiceToggled);
  }

  final RouteRepository _routes;
  final BuildingRepository _buildings;

  /// Optional so widget tests and the layout code can build a bloc without a
  /// TTS engine; on a device it is always present.
  final SpeechService? _speech;

  RoutePlanner? _planner;

  /// The utterance already spoken, so a rebuild does not repeat it.
  String? _spokenKey;

  /// Speaks each leg as it becomes current.
  ///
  /// Driven from [onChange] rather than from the handlers because every one of
  /// them can move the user onto a different leg — arriving, replanning,
  /// choosing a new destination — and guidance that only some of those
  /// triggered would go quiet exactly when the route changed under the user.
  @override
  void onChange(Change<FloorPlanState> change) {
    super.onChange(change);

    final next = change.nextState;
    if (!next.voiceOn) {
      // Cleared rather than remembered, so unmuting re-speaks the current leg
      // instead of silently waiting for the next one.
      _spokenKey = null;
      return;
    }

    final key = next.guidanceKey;
    if (key == null || key == _spokenKey) return;
    _spokenKey = key;

    final line = next.spokenGuidance;
    if (line == null) return;
    // Interrupts: the previous sentence describes a leg the user has left, and
    // waiting for it to finish delays the one that is true now.
    unawaited(_speech?.speak(line, interrupt: true));
  }

  @override
  Future<void> close() {
    unawaited(_speech?.stop());
    return super.close();
  }

  Future<void> _onStarted(
    FloorPlanStarted event,
    Emitter<FloorPlanState> emit,
  ) async {
    emit(state.copyWith(status: FloorPlanStatus.loading, clearError: true));

    try {
      final landmarks = await _routes.landmarksOf(event.buildingId);
      final routes = await _routes.routesOf(event.buildingId);
      final floors = await _buildings.floorsOf(event.buildingId);

      final merged = mergeWithDiagnostics(routes, landmarks);
      final planner = RoutePlanner(
        graph: merged.graph,
        recorded: routes,
        landmarks: landmarks,
      );
      _planner = planner;

      if (merged.graph.isEmpty) {
        // Not an error: a building nobody has walked yet is the normal state
        // of a crowdsourced map, and the screen invites the user to record it.
        emit(
          state.copyWith(
            status: FloorPlanStatus.success,
            graph: merged.graph,
            landmarks: {for (final l in landmarks) l.id: l},
            floors: const [],
            emptyReason: FloorPlanEmptyReason.noRoutes,
            clearRoute: true,
          ),
        );
        return;
      }

      final mapped = _mappedFloors(floors, merged.graph);
      final route = event.destinationRoomId == null
          ? null
          : _planTo(planner, event.destinationRoomId!);

      emit(
        state.copyWith(
          status: FloorPlanStatus.success,
          graph: merged.graph,
          landmarks: {for (final l in landmarks) l.id: l},
          floors: mapped,
          activeFloorId: _floorToShow(mapped, route, merged.graph),
          route: route,
          currentLandmarkId: route?.startLandmarkId,
          emptyReason: event.destinationRoomId != null && route == null
              ? FloorPlanEmptyReason.unreachableDestination
              : FloorPlanEmptyReason.none,
          worstSpreadM: merged.worstSpreadM,
        ),
      );
    } on OperationFailure catch (f) {
      emit(state.copyWith(status: FloorPlanStatus.failure, error: f.message));
    }
  }

  void _onFloorSelected(
    FloorPlanFloorSelected event,
    Emitter<FloorPlanState> emit,
  ) {
    emit(state.copyWith(activeFloorId: event.floorId));
  }

  void _onDestinationSelected(
    FloorPlanDestinationSelected event,
    Emitter<FloorPlanState> emit,
  ) {
    final planner = _planner;
    if (planner == null) return;

    final route = _planTo(planner, event.roomId);
    if (route == null) {
      // Nobody has recorded a landmark at that door, or no walk connects it to
      // where the user is. Both are worth saying out loud.
      emit(
        state.copyWith(
          emptyReason: FloorPlanEmptyReason.unreachableDestination,
          clearRoute: true,
        ),
      );
      return;
    }

    emit(
      state.copyWith(
        route: route,
        currentLandmarkId: route.startLandmarkId,
        activeFloorId: _floorToShow(state.floors, route, state.graph),
        emptyReason: FloorPlanEmptyReason.none,
      ),
    );
  }

  void _onPositionChanged(
    FloorPlanPositionChanged event,
    Emitter<FloorPlanState> emit,
  ) {
    // Follow them up the stairs; a plan of the floor they have left is worse
    // than useless while they are walking.
    final floorId = state.graph.nodes[event.landmarkId]?.floorId;
    final route = state.route;
    final planner = _planner;

    // Arriving at a landmark the route already passes through is progress:
    // keep the recording and let `currentStep` advance along it. Arriving
    // anywhere else means the route no longer starts where the user stands,
    // so plan a new one from here — showing somebody who has walked off the
    // route "leg 1 of 5" describes a journey they are no longer making.
    final offRoute = route != null &&
        planner != null &&
        !route.landmarkIds.contains(event.landmarkId);

    if (offRoute) {
      final replanned = planner.planToRoom(
        fromLandmarkId: event.landmarkId,
        roomId: route.destinationRoomId,
      );

      emit(
        replanned == null
            // Nothing in the graph connects where they are to where they are
            // going. Say so, rather than leaving a route on screen that starts
            // somewhere they are not.
            ? state.copyWith(
                currentLandmarkId: event.landmarkId,
                activeFloorId: floorId ?? state.activeFloorId,
                emptyReason: FloorPlanEmptyReason.unreachableDestination,
                clearRoute: true,
              )
            : state.copyWith(
                route: replanned,
                currentLandmarkId: event.landmarkId,
                activeFloorId: floorId ?? state.activeFloorId,
                emptyReason: FloorPlanEmptyReason.none,
              ),
      );
      return;
    }

    emit(
      state.copyWith(
        currentLandmarkId: event.landmarkId,
        activeFloorId: floorId ?? state.activeFloorId,
      ),
    );
  }

  void _onRouteCleared(
    FloorPlanRouteCleared event,
    Emitter<FloorPlanState> emit,
  ) {
    // Cut the sentence off mid-word if need be: the user has just said they
    // are not going there, and hearing the rest of the directions is noise.
    unawaited(_speech?.stop());
    _spokenKey = null;
    emit(
      state.copyWith(
        clearRoute: true,
        emptyReason: FloorPlanEmptyReason.none,
      ),
    );
  }

  void _onVoiceToggled(
    FloorPlanVoiceToggled event,
    Emitter<FloorPlanState> emit,
  ) {
    if (!event.on) unawaited(_speech?.stop());
    emit(state.copyWith(voiceOn: event.on));
  }

  /// Routes from wherever the user is, falling back to the building entrance —
  /// which is where somebody consulting a map of a building they have not
  /// entered actually is.
  WalkRoute? _planTo(RoutePlanner planner, String roomId) {
    final from = state.currentLandmarkId ?? _entranceOf(planner);
    if (from == null) return null;
    return planner.planToRoom(fromLandmarkId: from, roomId: roomId);
  }

  String? _entranceOf(RoutePlanner planner) {
    for (final id in planner.graph.nodes.keys) {
      if (state.landmarks[id]?.kind == LandmarkKind.entrance) return id;
    }
    // No landmark was labelled an entrance; the first node is at least
    // somewhere a contributor started walking from.
    return planner.graph.nodes.keys.firstOrNull;
  }

  /// Only floors that carry landmarks, in the building's own order.
  ///
  /// A building may declare eight storeys while one has been walked; offering
  /// seven empty tabs would imply the map is broken rather than incomplete.
  List<BuildingFloor> _mappedFloors(
    List<BuildingFloor> floors,
    FloorGraph graph,
  ) {
    final mapped = graph.floorIds;
    final known = floors.where((f) => mapped.contains(f.id)).toList();
    if (known.isNotEmpty) return known;

    // The building's floor ids do not match the landmarks' — an older capture,
    // or a building record that has been rebuilt. Fall back to naming the
    // planes after the graph so the map still works.
    return [for (final id in mapped) BuildingFloor(id: id, label: id, rooms: const [])];
  }

  String? _floorToShow(
    List<BuildingFloor> floors,
    WalkRoute? route,
    FloorGraph graph,
  ) {
    // Start on the floor the journey starts on, not the ground floor: a user
    // routing out of the Reading Hall wants to see where they are standing.
    if (route != null) {
      final startFloor = graph.nodes[route.startLandmarkId]?.floorId;
      if (startFloor != null) return startFloor;
    }
    if (state.activeFloorId != null &&
        graph.floorIds.contains(state.activeFloorId)) {
      return state.activeFloorId;
    }
    return floors.isNotEmpty ? floors.first.id : graph.floorIds.firstOrNull;
  }
}
