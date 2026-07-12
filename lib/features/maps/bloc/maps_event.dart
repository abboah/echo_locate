part of 'maps_bloc.dart';

sealed class MapsEvent extends Equatable {
  const MapsEvent();

  @override
  List<Object?> get props => [];
}

final class MapsStarted extends MapsEvent {
  const MapsStarted();
}
