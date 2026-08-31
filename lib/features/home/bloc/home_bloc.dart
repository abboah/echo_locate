import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../../core/models/building.dart';
import '../../../core/models/room_plan.dart';
import '../../../data/repository_mixin.dart';
import '../../../services/location/location_service.dart';
import '../../../services/mapping/floor_label.dart';
import '../../../services/mapping/floor_mapping_status.dart';
import '../../buildings/building_repository.dart';
import '../../room_trace/room_plan_repository.dart';

part 'home_event.dart';
part 'home_state.dart';

/// Home: where the user is, what they can search, and what they have mapped.
///
/// Three things that were all placeholders. The header read `KNUST, Kumasi` as
/// a literal on every phone. The search field was `readOnly` and pushed the
/// Explore tab on tap, so typing into it was impossible and it existed to look
/// like a search box. And the cards drew a generic building glyph even for
/// buildings whose floors this device had traced and could draw.
class HomeBloc extends Bloc<HomeEvent, HomeState> {
  HomeBloc(this._buildings, this._plans, this._location)
    : super(const HomeState()) {
    on<HomeStarted>(_onStarted);
    on<HomeLocationRequested>(_onLocation);
    on<HomeSearchChanged>(
      _onSearch,
      // Typing "College of Science" is nineteen keystrokes and would be
      // nineteen queries. Only the last one after a pause is worth asking.
      transformer: _debounce(const Duration(milliseconds: 280)),
    );
    on<HomeSearchCleared>(_onSearchCleared);
  }

  final BuildingRepository _buildings;
  final RoomPlanRepository _plans;
  final LocationService _location;

  Future<void> _onStarted(HomeStarted event, Emitter<HomeState> emit) async {
    emit(state.copyWith(status: HomeStatus.loading));
    try {
      final recent = await _buildings.recentlyMapped();
      final floors = await _tracedFloors();
      emit(
        state.copyWith(
          status: HomeStatus.success,
          recent: recent,
          // The floors this device holds, so a card can show the building's
          // actual shape instead of a stock icon.
          thumbnails: _thumbnailsFrom(floors),
          walkable: await _walkable(floors),
        ),
      );
    } catch (error) {
      // Broad on purpose: a narrow catch let Supabase, socket and
      // Hive errors escape, and a Bloc that never emits leaves the
      // screen spinning forever.
      emit(
        state.copyWith(
          status: HomeStatus.failure,
          error: OperationFailure.from(error).message,
        ),
      );
    }
  }

  /// Every traced floor on the device, read once and used twice.
  ///
  /// Once to draw a building's real shape on its card, and once for the
  /// "Walk a floor" row — which is the point of the whole app and, until now,
  /// took four taps to reach from the screen the app opens on.
  Future<List<RoomPlan>> _tracedFloors() async {
    try {
      return [
        for (final plan in await _plans.allPlans())
          if (!plan.isEmpty) plan,
      ];
    } catch (_) {
      // The card falls back to its glyph and the walk row hides itself.
      return const [];
    }
  }

  /// One floor per building, for the card art.
  ///
  /// The ground floor where there is one — it is the floor somebody recognises
  /// a building by — otherwise whichever was traced first.
  static Map<String, RoomPlan> _thumbnailsFrom(List<RoomPlan> floors) {
    final byBuilding = <String, RoomPlan>{};
    for (final plan in floors) {
      final existing = byBuilding[plan.buildingId];
      if (existing == null || _isGround(plan) && !_isGround(existing)) {
        byBuilding[plan.buildingId] = plan;
      }
    }
    return byBuilding;
  }

  /// The floors somebody can be guided along right now.
  ///
  /// Only walkable ones: a floor with rooms and no doors is drawn correctly,
  /// routes nowhere, and offering to walk it is a promise the app cannot keep.
  /// Half-finished floors live on the Maps tab, where finishing them is the
  /// point.
  Future<List<WalkableFloor>> _walkable(List<RoomPlan> floors) async {
    final names = <String, String>{};
    final labels = <String, String>{};
    final walkable = <WalkableFloor>[];

    for (final plan in floors) {
      final status = FloorMappingStatus.of(
        BuildingFloor(id: plan.floorId, label: '', rooms: const []),
        plan,
      );
      if (!status.stage.isNavigable) continue;

      // Once per building, not once per floor.
      if (!names.containsKey(plan.buildingId)) {
        try {
          names[plan.buildingId] = (await _buildings.byId(
            plan.buildingId,
          )).name;
        } catch (_) {
          // Offline, or traced before the building reached the index. The id
          // is a slug of the name, so it is a readable last resort.
          names[plan.buildingId] = plan.buildingId;
        }
        try {
          for (final floor in await _buildings.floorsOf(plan.buildingId)) {
            labels['${plan.buildingId}/${floor.id}'] = floor.label;
          }
        } catch (_) {
          // The label falls back to the floor id, which reads well enough.
        }
      }
      walkable.add(
        WalkableFloor(
          plan: plan,
          buildingName: names[plan.buildingId]!,
          storedLabel: labels['${plan.buildingId}/${plan.floorId}'],
        ),
      );
    }

    walkable.sort((a, b) {
      final byBuilding = a.buildingName.compareTo(b.buildingName);
      return byBuilding != 0
          ? byBuilding
          : a.floorLabel.compareTo(b.floorLabel);
    });
    return walkable;
  }

  static bool _isGround(RoomPlan plan) =>
      plan.floorId.toLowerCase().endsWith('g') ||
      plan.floorId.toLowerCase().contains('ground');

  /// Names where the user is, and remembers the position for Explore.
  ///
  /// Everything about this is allowed to fail quietly. Location is not needed
  /// to use the app — it orders a list and labels a header — so a refusal
  /// leaves the header saying nothing rather than saying something wrong.
  Future<void> _onLocation(
    HomeLocationRequested event,
    Emitter<HomeState> emit,
  ) async {
    if (!await _location.isGranted) return;
    final position = await _location.current();
    if (position == null || isClosed) return;
    final name = await _location.placeName(position);
    if (isClosed || name == null || name.isEmpty) return;
    emit(state.copyWith(placeName: name));
  }

  Future<void> _onSearch(
    HomeSearchChanged event,
    Emitter<HomeState> emit,
  ) async {
    final query = event.query.trim();
    if (query.isEmpty) {
      emit(state.clearedSearch());
      return;
    }

    emit(state.copyWith(query: query, searching: true));
    try {
      final position = _location.lastKnown;
      final results = await _buildings.nearby(
        query: query,
        latitude: position?.latitude,
        longitude: position?.longitude,
      );
      if (isClosed) return;
      // A result that arrived after the user typed on is not this search's.
      if (state.query != query) return;
      emit(
        state.copyWith(
          status: HomeStatus.success,
          results: results,
          searching: false,
        ),
      );
    } catch (error) {
      if (isClosed) return;
      emit(
        state.copyWith(
          searching: false,
          error: OperationFailure.from(error).message,
        ),
      );
    }
  }

  void _onSearchCleared(HomeSearchCleared event, Emitter<HomeState> emit) =>
      emit(state.clearedSearch());
}

/// Drops every event but the last in a quiet window.
///
/// Written here rather than pulled in from `bloc_concurrency`, which is not a
/// dependency and would be one package for one function.
EventTransformer<T> _debounce<T>(Duration duration) {
  return (events, mapper) =>
      events.debounceBuffer(duration).asyncExpand(mapper);
}

extension<T> on Stream<T> {
  /// Emits an event only once [duration] has passed without another.
  Stream<T> debounceBuffer(Duration duration) {
    Timer? timer;
    late StreamController<T> controller;
    StreamSubscription<T>? subscription;

    controller = StreamController<T>(
      onListen: () {
        subscription = listen(
          (event) {
            timer?.cancel();
            timer = Timer(duration, () {
              if (!controller.isClosed) controller.add(event);
            });
          },
          onError: controller.addError,
          onDone: () {
            // A pending event still fires: the last keystroke before the
            // screen closes is the search the user actually wanted.
            timer?.cancel();
            controller.close();
          },
        );
      },
      onCancel: () async {
        timer?.cancel();
        await subscription?.cancel();
      },
    );

    return controller.stream;
  }
}
