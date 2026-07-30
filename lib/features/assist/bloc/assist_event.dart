part of 'assist_bloc.dart';

sealed class AssistEvent extends Equatable {
  const AssistEvent();

  @override
  List<Object?> get props => [];
}

final class AssistStarted extends AssistEvent {
  const AssistStarted();
}

final class AssistVoiceToggled extends AssistEvent {
  const AssistVoiceToggled();
}

/// Internal: a camera frame's detections arrived.
final class _ObstaclesArrived extends AssistEvent {
  const _ObstaclesArrived(this.obstacles);

  final List<DetectedObstacle> obstacles;

  @override
  List<Object?> get props => [obstacles];
}

/// Internal: demo-mode timer tick (no camera available).
final class _DemoTick extends AssistEvent {
  const _DemoTick();
}
