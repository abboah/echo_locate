part of 'explore_bloc.dart';

enum ExploreStatus { initial, loading, success, failure }

/// Filter categories shown as chips; ids match `Building.category`.
///
/// [savedCategory] is the exception — it is not a kind of building, it is the
/// ones this user bookmarked, and [ExploreBloc] answers it from a different
/// repository call. It lives here because the bookmark had nowhere left to be
/// seen once the Maps tab became a list of traced floors rather than of saved
/// buildings, and a bookmark nothing ever shows is a button that does nothing.
const exploreCategories = [
  ('all', 'All'),
  (savedCategory, 'Saved'),
  ('campus', 'Campus'),
  ('hospital', 'Hospitals'),
  ('mall', 'Malls'),
];

/// The pseudo-category that means "buildings I bookmarked".
const String savedCategory = 'saved';

final class ExploreState extends Equatable {
  const ExploreState({
    this.status = ExploreStatus.initial,
    this.buildings = const [],
    this.category = 'all',
    this.query = '',
    this.located = false,
    this.error,
  });

  final ExploreStatus status;
  final List<Building> buildings;
  final String category;
  final String query;

  /// Whether the distances on these rows were measured from the user.
  ///
  /// Said on screen rather than assumed: without a position every row is
  /// measured from the server's default origin, and a confident "0.4 km" that
  /// is not relative to you is worse than no distance at all.
  final bool located;

  final String? error;

  ExploreState copyWith({
    ExploreStatus? status,
    List<Building>? buildings,
    String? category,
    String? query,
    bool? located,
    String? error,
  }) {
    return ExploreState(
      status: status ?? this.status,
      buildings: buildings ?? this.buildings,
      category: category ?? this.category,
      query: query ?? this.query,
      located: located ?? this.located,
      error: error ?? this.error,
    );
  }

  @override
  List<Object?> get props => [
    status,
    buildings,
    category,
    query,
    located,
    error,
  ];
}
