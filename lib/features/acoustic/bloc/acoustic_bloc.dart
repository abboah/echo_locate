import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../../services/acoustic/reverb_features.dart';
import '../../../services/acoustic/reverb_measurement.dart';
import '../../../services/acoustic/room_classification.dart';
import '../../../services/acoustic/room_classifier.dart';
import '../../../services/audio/sonar_audio_service.dart';

part 'acoustic_event.dart';
part 'acoustic_state.dart';

/// Acoustic room classification (M5).
///
/// Turns [AcousticMeasureRequested] into one impulse-response capture, then
/// names the space from how long it rings. Shares [SonarAudioService] with the
/// sonar feature — same speaker, same mic, same chirp — but a different
/// capture shape: one excitation and a long silence rather than a train.
class AcousticBloc extends Bloc<AcousticEvent, AcousticState> {
  AcousticBloc(
    this._audio, {
    RoomClassifier classifier = const RoomClassifier(),
  }) : _classifier = classifier,
       super(const AcousticState()) {
    on<AcousticStarted>(_onStarted);
    on<AcousticMeasureRequested>(_onMeasure);
  }

  final SonarAudioService _audio;
  final RoomClassifier _classifier;

  Future<void> _onStarted(
    AcousticStarted event,
    Emitter<AcousticState> emit,
  ) async {
    final available = await _audio.start();
    if (isClosed) return;

    emit(
      state.copyWith(
        status: available ? AcousticStatus.idle : AcousticStatus.unavailable,
      ),
    );
  }

  Future<void> _onMeasure(
    AcousticMeasureRequested event,
    Emitter<AcousticState> emit,
  ) async {
    if (state.status != AcousticStatus.idle) return;
    emit(state.copyWith(status: AcousticStatus.listening));

    final measurement = await _audio.measureReverb();
    if (isClosed) return;

    final classification = _classifier.classify(measurement.features);

    emit(
      AcousticState(
        status: AcousticStatus.idle,
        // Held even when the verdict is `unknown`: the reverberation numbers are
        // the evidence, and showing them is what lets a user (or an examiner)
        // see why the space could not be named.
        lastClassification: classification,
        // A failed capture is reported as ITS cause, not the classifier's. The
        // classifier can only say "no usable measurement", which would blame the
        // room for a measurement the microphone never got to take.
        error: switch ((measurement.failure, classification.type)) {
          (final ReverbFailure failure, _) =>
            'Could not measure — ${failure.message}',
          (_, RoomType.unknown) =>
            'Could not identify the space — ${classification.reason}',
          _ => null,
        },
      ),
    );
  }
}
