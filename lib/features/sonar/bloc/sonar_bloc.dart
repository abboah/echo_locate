import 'dart:async';
import 'dart:math' as math;

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../../../core/utils/logger.dart';
import '../../../services/audio/sonar_audio_service.dart';
import '../../../services/dsp/tof_calculator.dart';

part 'sonar_event.dart';
part 'sonar_state.dart';

/// Sonar feature brain: brings up the mic/speaker, turns [SonarMeasureRequested]
/// into one [SonarAudioService.ping], and tracks a live (uncompensated)
/// compass heading for the radar view.
class SonarBloc extends Bloc<SonarEvent, SonarState> {
  SonarBloc(this._audio) : super(const SonarState()) {
    on<SonarStarted>(_onStarted);
    on<SonarMeasureRequested>(_onMeasure);
    on<SonarCalibrateRequested>(_onCalibrate);
    on<_HeadingChanged>(_onHeadingChanged);
  }

  final SonarAudioService _audio;
  StreamSubscription<MagnetometerEvent>? _headingSubscription;

  Future<void> _onStarted(SonarStarted event, Emitter<SonarState> emit) async {
    final available = await _audio.start();
    if (isClosed) return;

    if (!available) {
      emit(state.copyWith(status: SonarStatus.unavailable));
      return;
    }
    // A clutter profile persists across sessions, and [SonarAudioService.start]
    // has just restored it if one was stored. Without asking, the UI reported
    // "Calibration needed" on every fresh launch — telling the user to redo
    // work that was already done and already being applied to every ping.
    emit(state.copyWith(
      status: SonarStatus.idle,
      isCalibrated: _audio.hasClutterProfile,
    ));

    await _headingSubscription?.cancel();
    _headingSubscription = magnetometerEventStream().listen(
      (event) =>
          add(_HeadingChanged(_headingFromMagnetometer(event.x, event.y))),
      onError: (Object e) =>
          AppLogger.warn('Magnetometer stream unavailable: $e'),
    );
  }

  Future<void> _onMeasure(
    SonarMeasureRequested event,
    Emitter<SonarState> emit,
  ) async {
    if (state.status != SonarStatus.idle) return;
    emit(state.copyWith(status: SonarStatus.measuring));

    final result = await _audio.measure();
    if (isClosed) return;

    emit(SonarState(
      status: SonarStatus.idle,
      headingDegrees: state.headingDegrees,
      lastMeasurement: result ?? state.lastMeasurement,
      isCalibrated: state.isCalibrated,
      error: result == null
          ? state.isCalibrated
              ? 'No echo detected — try facing a flatter surface'
              : 'No echo detected — calibrate first for close-range readings'
          : null,
    ));
  }

  Future<void> _onCalibrate(
    SonarCalibrateRequested event,
    Emitter<SonarState> emit,
  ) async {
    if (state.status != SonarStatus.idle) return;
    emit(state.copyWith(status: SonarStatus.calibrating));

    final ok = await _audio.calibrateClutter();
    if (isClosed) return;

    emit(SonarState(
      status: SonarStatus.idle,
      headingDegrees: state.headingDegrees,
      lastMeasurement: state.lastMeasurement,
      isCalibrated: ok || state.isCalibrated,
      error: ok
          ? null
          : 'Calibration failed — hold the phone still and try again',
    ));
  }

  void _onHeadingChanged(_HeadingChanged event, Emitter<SonarState> emit) {
    emit(state.copyWith(headingDegrees: event.degrees));
  }

  /// Flat-phone approximation: no accelerometer tilt compensation, so this
  /// only reads true while the phone is held roughly upright and level.
  /// A full compass needs sensor fusion — out of scope for the "lite" radar
  /// demo (see CLAUDE.md).
  double _headingFromMagnetometer(double x, double y) {
    final radians = math.atan2(-x, y);
    final degrees = radians * 180 / math.pi;
    return (degrees + 360) % 360;
  }

  @override
  Future<void> close() async {
    await _headingSubscription?.cancel();
    await _audio.stop();
    return super.close();
  }
}
