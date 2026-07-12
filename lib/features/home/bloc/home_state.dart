part of 'home_bloc.dart';

enum HomeStatus { initial, loading, success, failure }

final class HomeState extends Equatable {
  const HomeState({
    this.status = HomeStatus.initial,
    this.recent = const [],
    this.error,
  });

  final HomeStatus status;
  final List<Building> recent;
  final String? error;

  HomeState copyWith({
    HomeStatus? status,
    List<Building>? recent,
    String? error,
  }) {
    return HomeState(
      status: status ?? this.status,
      recent: recent ?? this.recent,
      error: error ?? this.error,
    );
  }

  @override
  List<Object?> get props => [status, recent, error];
}
