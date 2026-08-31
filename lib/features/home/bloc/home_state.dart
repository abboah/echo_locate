part of 'home_bloc.dart';

enum HomeStatus { initial, loading, success, failure }

/// A traced floor that can be walked right now, named for a card.
final class WalkableFloor extends Equatable {
  const WalkableFloor({
    required this.plan,
    required this.buildingName,
    this.storedLabel,
  });

  final RoomPlan plan;
  final String buildingName;

  /// The label the building index gives this floor, when it could be reached.
  final String? storedLabel;

  /// What to call this floor. The index's own label where there is one, read
  /// off the id otherwise — this shelf has to render with no connection.
  String get floorLabel {
    final stored = storedLabel?.trim();
    if (stored != null && stored.isNotEmpty) return stored;
    return floorLabelFromId(plan.floorId);
  }

  String get floorTitle => floorTitleFor(floorLabel);

  int get roomCount => plan.drawableRooms.length;

  @override
  List<Object?> get props => [plan, buildingName, storedLabel];
}

final class HomeState extends Equatable {
  const HomeState({
    this.status = HomeStatus.initial,
    this.recent = const [],
    this.results = const [],
    this.thumbnails = const {},
    this.walkable = const [],
    this.query = '',
    this.searching = false,
    this.placeName,
    this.error,
  });

  final HomeStatus status;

  /// What the user has mapped, for the grid.
  final List<Building> recent;

  /// Matches for [query]. Empty and unused until somebody types.
  final List<Building> results;

  /// A traced floor per building id, so a card can draw the real thing.
  final Map<String, RoomPlan> thumbnails;

  /// Floors that can be guided along right now. Empty on a fresh install, and
  /// the section hides itself rather than showing an empty shelf.
  final List<WalkableFloor> walkable;

  final String query;
  final bool searching;

  /// Where the user is, named — "Kumasi, Ashanti". Null until located, which
  /// includes "they said no", so the header must read acceptably without it.
  final String? placeName;

  final String? error;

  bool get isSearching => query.isNotEmpty;

  /// A search that finished and matched nothing — distinct from one still
  /// running, which must not flash "no buildings" on the way to results.
  bool get foundNothing => isSearching && !searching && results.isEmpty;

  /// The floor to draw on [building]'s card, if this device has one.
  RoomPlan? planFor(String buildingId) => thumbnails[buildingId];

  HomeState copyWith({
    HomeStatus? status,
    List<Building>? recent,
    List<Building>? results,
    Map<String, RoomPlan>? thumbnails,
    List<WalkableFloor>? walkable,
    String? query,
    bool? searching,
    String? placeName,
    String? error,
  }) {
    return HomeState(
      status: status ?? this.status,
      recent: recent ?? this.recent,
      results: results ?? this.results,
      thumbnails: thumbnails ?? this.thumbnails,
      walkable: walkable ?? this.walkable,
      query: query ?? this.query,
      searching: searching ?? this.searching,
      placeName: placeName ?? this.placeName,
      error: error ?? this.error,
    );
  }

  /// Back to the un-searched screen.
  ///
  /// Its own method because `copyWith` cannot do it: passing `query: ''` and
  /// `results: []` is indistinguishable from passing nothing, so clearing a
  /// search through it would silently leave the previous results on screen.
  HomeState clearedSearch() => HomeState(
    status: status,
    recent: recent,
    thumbnails: thumbnails,
    walkable: walkable,
    placeName: placeName,
  );

  @override
  List<Object?> get props => [
    status,
    recent,
    results,
    thumbnails,
    walkable,
    query,
    searching,
    placeName,
    error,
  ];
}
