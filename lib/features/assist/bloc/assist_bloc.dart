import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../../services/sensing/callout_policy.dart';
import '../../../services/sensing/detected_obstacle.dart';
import '../../../services/sensing/detection_service.dart';
import '../../../services/speech/speech_service.dart';

part 'assist_event.dart';
part 'assist_state.dart';

/// Assist Mode brain: starts the camera pipeline, filters detections
/// through [CalloutPolicy], speaks the result, and falls back to a scripted
/// demo loop when no camera is available (emulator, permission denied).
class AssistBloc extends Bloc<AssistEvent, AssistState> {
  AssistBloc(this._detection, this._speech) : super(const AssistState()) {
    on<AssistStarted>(_onStarted);
    on<AssistVoiceToggled>(_onVoiceToggled);
    on<_ObstaclesArrived>(_onObstacles);
    on<_DemoTick>(_onDemoTick);
  }

  final DetectionService _detection;
  final SpeechService _speech;
  final CalloutPolicy _policy = CalloutPolicy();

  StreamSubscription<List<DetectedObstacle>>? _subscription;
  Timer? _demoTimer;
  int _demoIndex = 0;

  static const _demoCallouts = [
    AssistCallout(
        title: 'Door ahead', detail: 'about 3 steps', urgent: false, label: 'doorway'),
    AssistCallout(
        title: 'Chair on your left', detail: 'close', urgent: false, label: 'furniture'),
    AssistCallout(
        title: 'Path bends right', detail: 'in 5 steps', urgent: false, label: 'path'),
    AssistCallout(
        title: 'Sign: "Room 204"', detail: 'on your right', urgent: false, label: 'sign'),
  ];

  Future<void> _onStarted(
    AssistStarted event,
    Emitter<AssistState> emit,
  ) async {
    final live = await _detection.start();
    if (isClosed) return;

    if (live) {
      emit(state.copyWith(status: AssistStatus.live));
      _speak('Assistance started. I will call out what I see.');
      await _subscription?.cancel();
      _subscription = _detection.obstacles
          .listen((obstacles) => add(_ObstaclesArrived(obstacles)));
    } else {
      // No camera — scripted loop so the flow stays demonstrable.
      emit(state.copyWith(status: AssistStatus.demo));
      _speak('Assistance demo. Connect a camera for live detection.');
      add(const _DemoTick());
      _demoTimer = Timer.periodic(
        const Duration(seconds: 4),
        (_) => add(const _DemoTick()),
      );
    }
  }

  void _onObstacles(_ObstaclesArrived event, Emitter<AssistState> emit) {
    final callout = _policy.evaluate(event.obstacles);
    if (callout == null) return;
    emit(state.copyWith(callout: callout));
    _speak(callout.spoken, interrupt: callout.urgent);
  }

  void _onDemoTick(_DemoTick event, Emitter<AssistState> emit) {
    final callout = _demoCallouts[_demoIndex % _demoCallouts.length];
    _demoIndex++;
    emit(state.copyWith(callout: callout));
    _speak(callout.spoken);
  }

  void _onVoiceToggled(AssistVoiceToggled event, Emitter<AssistState> emit) {
    final voiceOn = !state.voiceOn;
    emit(state.copyWith(voiceOn: voiceOn));
    if (!voiceOn) _speech.stop();
  }

  void _speak(String text, {bool interrupt = false}) {
    if (state.voiceOn) _speech.speak(text, interrupt: interrupt);
  }

  @override
  Future<void> close() async {
    _demoTimer?.cancel();
    await _subscription?.cancel();
    await _detection.stop();
    await _speech.stop();
    _policy.reset();
    return super.close();
  }
}
