part of 'explore_bloc.dart';

enum ExploreStatus { initial, loading, success, failure }

/// Filter categories shown as chips; ids match `Building.category`.
const exploreCategories = [
  ('all', 'All'),
  ('campus', 'Campus'),
  ('hospital', 'Hospitals'),
  ('mall', 'Malls'),
];

final class ExploreState extends Equatable {
  const ExploreState({
    this.status = ExploreStatus.initial,
    this.buildings = const [],
    this.category = 'all',
    this.query = '',
    this.error,
  });

  final ExploreStatus status;
  final List<Building> buildings;
  final String category;
  final String query;
  final String? error;

  ExploreState copyWith({
    ExploreStatus? status,
    List<Building>? buildings,
    String? category,
    String? query,
    String? error,
  }) {
    return ExploreState(
      status: status ?? this.status,
      buildings: buildings ?? this.buildings,
      category: category ?? this.category,
      query: query ?? this.query,
      error: error ?? this.error,
    );
  }

  @override
  List<Object?> get props => [status, buildings, category, query, error];
}
