import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../../core/models/building.dart';
import '../../../core/utils/logger.dart';
import '../../../data/repository_mixin.dart';
import '../../buildings/building_repository.dart';

enum MapBuildingStatus { loading, ready, creating, created, failure }

class MapBuildingState extends Equatable {
  const MapBuildingState({
    this.status = MapBuildingStatus.loading,
    this.listed = const [],
    this.created,
    this.error,
  });

  final MapBuildingStatus status;

  /// Buildings somebody has already added, to extend rather than duplicate.
  final List<Building> listed;

  /// Set once a new building exists, so the screen can go straight into
  /// tracing it.
  final Building? created;

  final String? error;

  MapBuildingState copyWith({
    MapBuildingStatus? status,
    List<Building>? listed,
    Building? created,
    String? error,
  }) => MapBuildingState(
    status: status ?? this.status,
    listed: listed ?? this.listed,
    created: created ?? this.created,
    error: error,
  );

  @override
  List<Object?> get props => [status, listed, created, error];
}

/// Choosing what to map: a building nobody has listed, or one that is.
///
/// This screen exists because the index is crowdsourced. Sending a contributor
/// to Explore only ever offers buildings somebody already thought of, which
/// leaves the person standing in an unlisted building — the exact case mapping
/// is for — with nowhere to go.
class MapBuildingCubit extends Cubit<MapBuildingState> {
  MapBuildingCubit(this._buildings) : super(const MapBuildingState());

  final BuildingRepository _buildings;

  Future<void> load() async {
    emit(state.copyWith(status: MapBuildingStatus.loading));
    try {
      final listed = await _buildings.nearby();
      if (isClosed) return;
      emit(state.copyWith(status: MapBuildingStatus.ready, listed: listed));
    } catch (error, stack) {
      AppLogger.error('Could not list buildings: $error', error, stack);
      if (isClosed) return;
      // Not fatal: adding a new building does not need the list, and the list
      // is only there to stop duplicates.
      emit(
        state.copyWith(
          status: MapBuildingStatus.ready,
          listed: const [],
          error: OperationFailure.from(error).message,
        ),
      );
    }
  }

  Future<void> create({
    required String name,
    required String area,
    required int floors,
    String category = 'campus',
  }) async {
    if (name.trim().isEmpty) {
      emit(state.copyWith(error: 'Give the building a name'));
      return;
    }

    emit(state.copyWith(status: MapBuildingStatus.creating));
    try {
      final building = await _buildings.create(
        name: name,
        area: area,
        category: category,
        floors: floors < 1 ? 1 : floors,
      );
      if (isClosed) return;
      emit(
        state.copyWith(status: MapBuildingStatus.created, created: building),
      );
    } catch (error, stack) {
      AppLogger.error('Could not add building: $error', error, stack);
      if (isClosed) return;
      emit(
        state.copyWith(
          status: MapBuildingStatus.ready,
          error: OperationFailure.from(error).message,
        ),
      );
    }
  }
}
