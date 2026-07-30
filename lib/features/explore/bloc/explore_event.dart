part of 'explore_bloc.dart';

sealed class ExploreEvent extends Equatable {
  const ExploreEvent();

  @override
  List<Object?> get props => [];
}

final class ExploreStarted extends ExploreEvent {
  const ExploreStarted();
}

final class ExploreCategoryChanged extends ExploreEvent {
  const ExploreCategoryChanged(this.category);

  final String category;

  @override
  List<Object?> get props => [category];
}

final class ExploreQueryChanged extends ExploreEvent {
  const ExploreQueryChanged(this.query);

  final String query;

  @override
  List<Object?> get props => [query];
}
