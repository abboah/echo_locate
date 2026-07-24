part of 'assist_bloc.dart';

/// starting → live (camera running) | demo (no camera: emulator/denied).
enum AssistStatus { starting, live, demo }

final class AssistState extends Equatable {
  const AssistState({
    this.status = AssistStatus.starting,
    this.callout,
    this.voiceOn = true,
  });

  final AssistStatus status;
  final AssistCallout? callout;
  final bool voiceOn;

  AssistState copyWith({
    AssistStatus? status,
    AssistCallout? callout,
    bool? voiceOn,
  }) {
    return AssistState(
      status: status ?? this.status,
      callout: callout ?? this.callout,
      voiceOn: voiceOn ?? this.voiceOn,
    );
  }

  @override
  List<Object?> get props => [status, callout, voiceOn];
}
