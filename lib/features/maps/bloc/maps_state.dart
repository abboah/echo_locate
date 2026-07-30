part of 'maps_bloc.dart';

enum MapsStatus { initial, loading, success, failure }

final class MapsState extends Equatable {
  const MapsState({
    this.status = MapsStatus.initial,
    this.saved = const [],
    this.error,
  });

  final MapsStatus status;
  final List<Building> saved;
  final String? error;

  MapsState copyWith({
    MapsStatus? status,
    List<Building>? saved,
    String? error,
  }) {
    return MapsState(
      status: status ?? this.status,
      saved: saved ?? this.saved,
      error: error ?? this.error,
    );
  }

  @override
  List<Object?> get props => [status, saved, error];
}
