part of 'home_bloc.dart';

sealed class HomeEvent extends Equatable {
  const HomeEvent();

  @override
  List<Object?> get props => [];
}

final class HomeStarted extends HomeEvent {
  const HomeStarted();
}

/// Name where the user is, if they have already allowed it.
///
/// Separate from [HomeStarted] because it must never block the screen: the
/// grid renders while the fix is still being taken, and on a phone indoors the
/// fix may never arrive at all.
final class HomeLocationRequested extends HomeEvent {
  const HomeLocationRequested();
}

/// The user typed in Home's search field.
final class HomeSearchChanged extends HomeEvent {
  const HomeSearchChanged(this.query);

  final String query;

  @override
  List<Object?> get props => [query];
}

/// The field was emptied or dismissed — back to the ordinary Home.
final class HomeSearchCleared extends HomeEvent {
  const HomeSearchCleared();
}
