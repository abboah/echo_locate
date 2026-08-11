import 'dart:math' as math;

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../../core/models/building.dart';
import '../../../core/models/landmark.dart';
import '../../../core/models/traced_plan.dart';
import '../../../core/utils/logger.dart';
import '../../../data/repository_mixin.dart';
import '../../../services/mapping/plan_photo_service.dart';
import '../../buildings/building_repository.dart';
import '../../routing/route_repository.dart';

part 'plan_trace_event.dart';
part 'plan_trace_state.dart';

/// Turns a photograph of a posted floor plan into a navigable graph.
///
/// The alternative to walking a building with a pedometer, and the reason it
/// exists: a recorded walk derives geometry by chaining step counts and tapped
/// turns, so error accumulates along the route and a loop never closes. Here
/// every position is read off the plan, absolute from the first tap, and the
/// only measurement the contributor makes is one known distance for the scale.
///
/// Localisation is untouched. A traced node still carries the label OCR looks
/// for, so the camera finds the user exactly as before. What changes is where
/// the *map* comes from, not how somebody is found on it.
class PlanTraceBloc extends Bloc<PlanTraceEvent, PlanTraceState> {
  PlanTraceBloc(this._routes, this._photos, this._buildings)
      : super(const PlanTraceState()) {
    on<PlanTraceStarted>(_onStarted);
    on<PlanFloorChanged>(_onFloorChanged);
    on<PlanPhotoTaken>(_onPhotoTaken);
    on<PlanPhotoRetaken>(_onPhotoRetaken);
    on<PlanPhotoSkipped>(_onPhotoSkipped);
    on<PlanNodeAdded>(_onNodeAdded);
    on<PlanNodeTapped>(_onNodeTapped);
    on<PlanSelectionCleared>(_onSelectionCleared);
    on<PlanNodeRemoved>(_onNodeRemoved);
    on<PlanTraceSaved>(_onSaved);
  }

  final RouteRepository _routes;
  final PlanPhotoService _photos;
  final BuildingRepository _buildings;

  /// Distance in plan units within which a tap counts as hitting a point
  /// rather than asking for a new one. A fraction of the plan's width, so it
  /// stays the same size on screen whatever the plan's resolution.
  static const double tapRadius = 0.04;

  PlanPhotoService get photos => _photos;

  int _nextRef = 1;

  Future<void> _onStarted(
    PlanTraceStarted event,
    Emitter<PlanTraceState> emit,
  ) async {
    emit(
      state.copyWith(
        buildingId: event.buildingId,
        floorId: event.floorId,
        stage: PlanTraceStage.photo,
      ),
    );

    // The building's real floors, because a traced node references a floor by
    // its database id. Inventing one here would produce a plan the server
    // rejects — `save_traced_plan` casts the value to a uuid — and the
    // contributor would only find out after tracing the whole floor.
    try {
      final floors = await _buildings.floorsOf(event.buildingId);
      if (isClosed) return;
      if (floors.isNotEmpty) {
        emit(
          state.copyWith(
            floors: floors,
            floorId: floors.first.id,
          ),
        );
      }
    } catch (error, stack) {
      AppLogger.warn('Floors unavailable for ${event.buildingId}: $error');
      AppLogger.error('Floor load failed', error, stack);
    }

    // A camera that will not open is not a dead end: the plan photo is a
    // backdrop to tap against, and the graph is the taps. Tracing carries on
    // over a blank grid.
    final ready = await _photos.start();
    if (isClosed) return;
    emit(state.copyWith(cameraReady: ready));
  }

  void _onFloorChanged(
    PlanFloorChanged event,
    Emitter<PlanTraceState> emit,
  ) =>
      emit(state.copyWith(floorId: event.floorId, clearSelection: true));

  Future<void> _onPhotoTaken(
    PlanPhotoTaken event,
    Emitter<PlanTraceState> emit,
  ) async {
    final path = await _photos.capture();
    if (isClosed) return;
    if (path == null) {
      emit(state.copyWith(error: 'Could not take that photo. Try again.'));
      return;
    }
    await _photos.stop();
    if (isClosed) return;
    emit(
      state.copyWith(
        photoPath: path,
        cameraReady: false,
        stage: PlanTraceStage.trace,
      ),
    );
  }

  Future<void> _onPhotoRetaken(
    PlanPhotoRetaken event,
    Emitter<PlanTraceState> emit,
  ) async {
    // The points are kept: re-shooting is nearly always about a bad angle, and
    // throwing away a half-finished trace to fix a photo would be its own bug.
    emit(state.copyWith(clearPhoto: true, stage: PlanTraceStage.photo));
    final ready = await _photos.start();
    if (isClosed) return;
    emit(state.copyWith(cameraReady: ready));
  }

  Future<void> _onPhotoSkipped(
    PlanPhotoSkipped event,
    Emitter<PlanTraceState> emit,
  ) async {
    await _photos.stop();
    if (isClosed) return;
    emit(
      state.copyWith(
        clearPhoto: true,
        cameraReady: false,
        stage: PlanTraceStage.trace,
      ),
    );
  }

  void _onNodeAdded(PlanNodeAdded event, Emitter<PlanTraceState> emit) {
    final point = PlanPoint(
      ref: 'n${_nextRef++}',
      u: event.u,
      v: event.v,
      kind: event.kind,
      labelText: event.labelText,
      displayName: event.displayName,
      roomId: event.roomId,
    );

    // A new point joins whatever was selected, so tracing a corridor is tap,
    // tap, tap rather than tap-place-then-go-back-and-join.
    final selected = state.selectedRef;
    emit(
      state.copyWith(
        points: [...state.points, point],
        links: selected == null
            ? state.links
            : [...state.links, PlanLink(selected, point.ref)],
        selectedRef: point.ref,
      ),
    );
  }

  void _onNodeTapped(PlanNodeTapped event, Emitter<PlanTraceState> emit) {
    final selected = state.selectedRef;
    if (selected == null) {
      emit(state.copyWith(selectedRef: event.ref));
      return;
    }
    if (selected == event.ref) {
      emit(state.copyWith(clearSelection: true));
      return;
    }

    // Tapping an already-joined pair unjoins it: one gesture for both, so a
    // mis-drawn corridor is undone the same way it was drawn.
    final existing = state.links.where((l) => l.connects(selected, event.ref));
    emit(
      state.copyWith(
        links: existing.isEmpty
            ? [...state.links, PlanLink(selected, event.ref)]
            : [
                for (final link in state.links)
                  if (!link.connects(selected, event.ref)) link,
              ],
        selectedRef: event.ref,
      ),
    );
  }

  void _onSelectionCleared(
    PlanSelectionCleared event,
    Emitter<PlanTraceState> emit,
  ) =>
      emit(state.copyWith(clearSelection: true));

  void _onNodeRemoved(PlanNodeRemoved event, Emitter<PlanTraceState> emit) {
    emit(
      state.copyWith(
        points: [
          for (final point in state.points)
            if (point.ref != event.ref) point,
        ],
        // Its corridors go with it. Leaving them would put an edge on the map
        // naming a node that is not there, which is exactly the unroutable
        // node fromPlan has to defend against.
        links: [
          for (final link in state.links)
            if (link.fromRef != event.ref && link.toRef != event.ref) link,
        ],
        clearSelection: true,
      ),
    );
  }

  Future<void> _onSaved(
    PlanTraceSaved event,
    Emitter<PlanTraceState> emit,
  ) async {
    if (state.points.isEmpty) {
      emit(state.copyWith(error: 'Place at least one landmark before saving.'));
      return;
    }

    emit(state.copyWith(stage: PlanTraceStage.saving));
    try {
      await _routes.saveTracedPlan(toPlan());
      if (isClosed) return;
      emit(state.copyWith(stage: PlanTraceStage.saved));
    } catch (error, stack) {
      AppLogger.error('Saving traced plan failed: $error', error, stack);
      if (isClosed) return;
      emit(
        state.copyWith(
          stage: PlanTraceStage.trace,
          error: OperationFailure.from(error).message,
        ),
      );
    }
  }

  /// The traced plan, ready for the repository.
  ///
  /// Coordinates go out in plan units, and `metresPerUnit` is left null: nobody
  /// has been asked how big the building is, because nobody knows. A* compares
  /// edge lengths with each other, so the route is the same as it would be in
  /// metres, and guidance names landmarks instead of quoting distances.
  ///
  /// Screen v grows downwards and map y grows north, so v is negated on the way
  /// out. Without it every traced building would come out mirrored, and a route
  /// drawn correctly would be spoken as its own mirror image.
  TracedPlan toPlan() {
    return TracedPlan(
      buildingId: state.buildingId,
      nodes: [
        for (final point in state.points)
          TracedNode(
            ref: point.ref,
            x: point.u,
            y: -point.v,
            floorId: state.floorId,
            kind: point.kind,
            labelText: point.labelText,
            displayName: point.displayName,
            roomId: point.roomId,
          ),
      ],
      edges: [
        for (final link in state.links)
          TracedEdge(fromRef: link.fromRef, toRef: link.toRef),
      ],
    );
  }

  /// The placed point a tap at ([u], [v]) hits, or null for empty plan.
  PlanPoint? pointAt(double u, double v) {
    PlanPoint? best;
    var bestDistance = tapRadius;
    for (final point in state.points) {
      final du = point.u - u;
      final dv = point.v - v;
      final distance = math.sqrt(du * du + dv * dv);
      if (distance <= bestDistance) {
        bestDistance = distance;
        best = point;
      }
    }
    return best;
  }

  @override
  Future<void> close() async {
    await _photos.stop();
    return super.close();
  }
}
