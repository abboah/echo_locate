import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../../core/models/landmark.dart';
import '../../../core/models/route_draft.dart';
import '../../../core/utils/logger.dart';
import '../../../services/motion/step_service.dart';
import '../../../services/motion/stride_profile.dart';
import '../../../services/sensing/detection_service.dart';
import '../../../services/sensing/landmark_matcher.dart';
import '../../../services/sensing/text_recognition_service.dart';
import '../../routing/route_repository.dart';

part 'capture_event.dart';
part 'capture_state.dart';

/// Records a building by walking it once.
///
/// The contributor stands at a sign, confirms what the camera read, walks to
/// the next one while the phone counts steps, taps the turn they took and says
/// what they would tell someone else. That loop, repeated to a destination
/// door, is the whole mapping engine — no depth sensor, no ARCore, no survey.
///
/// Two rules the rest of the system depends on:
///
/// * **Steps are converted to metres here and nowhere else** (spec §4). The
///   contributor's count is meaningless to a user with a different stride; the
///   raw count is kept alongside only as evidence for the evaluation chapter.
/// * **A failed upload never loses the walk.** Twenty minutes of corridor is
///   not something to re-record because a corridor had no signal, so the draft
///   survives in state and the upload can simply be retried.
class CaptureBloc extends Bloc<CaptureEvent, CaptureState> {
  CaptureBloc({
    required DetectionService detection,
    required TextRecognitionService textRecognition,
    required StepService steps,
    required RouteRepository routes,
    LandmarkMatcher matcher = const LandmarkMatcher(),
  }) : _detection = detection,
       _textRecognition = textRecognition,
       _steps = steps,
       _routes = routes,
       _matcher = matcher,
       super(const CaptureState()) {
    on<CaptureStarted>(_onStarted);
    on<CaptureLandmarkAccepted>(_onLandmarkAccepted);
    on<CaptureLegDescribed>(_onLegDescribed);
    on<CaptureFinished>(_onFinished);
    on<_ReadsArrived>(_onReadsArrived);
    on<_StepsTicked>(_onStepsTicked);
  }

  final DetectionService _detection;
  final TextRecognitionService _textRecognition;
  final StepService _steps;
  final RouteRepository _routes;
  final LandmarkMatcher _matcher;

  StreamSubscription<List<String>>? _readSubscription;
  StreamSubscription<int>? _stepSubscription;

  List<Landmark> _known = const [];

  /// How many reads to offer at once. A directory board is a dozen lines and
  /// the contributor is choosing one at arm's length: a longer list is a worse
  /// list.
  static const int _maxProposals = 6;

  Future<void> _onStarted(
    CaptureStarted event,
    Emitter<CaptureState> emit,
  ) async {
    _known = event.knownLandmarks;

    final camera = await _detection.start();
    if (isClosed) return;
    if (camera) {
      _textRecognition.start();
      _readSubscription = _textRecognition.reads.listen((lines) {
        if (!isClosed) add(_ReadsArrived(lines));
      });
    } else {
      AppLogger.warn('Capture has no camera — landmarks must be typed');
    }

    final counting = await _steps.start();
    if (isClosed) return;
    if (counting) {
      _steps.reset();
      _stepSubscription = _steps.steps.listen((count) {
        if (!isClosed) add(_StepsTicked(count));
      });
    }

    emit(
      state.copyWith(
        status: CaptureStatus.sighting,
        buildingId: event.buildingId,
        floorId: event.floorId,
        stride: event.stride,
        stepCounting: counting,
        signReading: camera,
      ),
    );
  }

  void _onReadsArrived(_ReadsArrived event, Emitter<CaptureState> emit) {
    if (state.status == CaptureStatus.saving ||
        state.status == CaptureStatus.saved) {
      return;
    }

    final proposals = [...state.proposals];
    for (final line in event.lines) {
      final text = line.trim();
      if (text.length < 2) continue;
      final normalised = Landmark.normalise(text);
      if (proposals.any((p) => Landmark.normalise(p.text) == normalised)) {
        continue;
      }
      proposals.insert(
        0,
        CaptureProposal(text: text, existing: _matcher.match(text, _known)),
      );
    }
    if (proposals.length > _maxProposals) {
      proposals.removeRange(_maxProposals, proposals.length);
    }
    emit(state.copyWith(proposals: proposals));
  }

  void _onStepsTicked(_StepsTicked event, Emitter<CaptureState> emit) {
    emit(state.copyWith(stepsThisLeg: event.steps));
  }

  void _onLandmarkAccepted(
    CaptureLandmarkAccepted event,
    Emitter<CaptureState> emit,
  ) {
    if (state.status == CaptureStatus.describing) return;

    final landmark = DraftLandmark(
      ref: 'L${state.landmarks.length + 1}',
      floorId: state.floorId,
      kind: event.kind,
      labelText: Landmark.normalise(event.labelText),
      displayName: event.displayName,
      aliases: event.aliases,
    );

    // The opening landmark has no leg behind it: start counting and walk.
    if (state.landmarks.isEmpty) {
      _steps.reset();
      emit(
        state.copyWith(
          status: CaptureStatus.walking,
          landmarks: [landmark],
          stepsThisLeg: 0,
          proposals: const [],
        ),
      );
      return;
    }

    // Freeze the count now. The contributor is about to stand still typing an
    // instruction, and those steps belong to no leg.
    emit(
      state.copyWith(
        status: CaptureStatus.describing,
        pendingLandmark: landmark,
        pendingSteps: state.stepsThisLeg,
        proposals: const [],
      ),
    );
  }

  void _onLegDescribed(CaptureLegDescribed event, Emitter<CaptureState> emit) {
    final pending = state.pendingLandmark;
    if (pending == null || state.landmarks.isEmpty) return;

    final counted = state.stepCounting && state.pendingSteps > 0
        ? state.pendingSteps
        : null;
    final distanceM =
        event.distanceM ??
        (counted == null ? 0.0 : state.stride.distanceFor(counted));

    // A zero-length leg is not a leg. Refusing it keeps the walk intact — the
    // contributor types the distance and saves again — rather than quietly
    // recording two landmarks in the same spot.
    if (distanceM <= 0) {
      emit(
        state.copyWith(
          error:
              'No steps were counted for this leg. Enter how far you '
              'walked, in metres.',
        ),
      );
      return;
    }

    final step = DraftStep(
      seq: state.steps.length + 1,
      fromRef: state.landmarks.last.ref,
      toRef: pending.ref,
      instruction: event.instruction,
      distanceM: distanceM,
      turnDeg: event.turnDeg,
      stepsRecorded: counted,
    );

    _steps.reset();
    emit(
      state.copyWith(
        status: CaptureStatus.walking,
        landmarks: [...state.landmarks, pending],
        steps: [...state.steps, step],
        stepsThisLeg: 0,
        pendingSteps: 0,
        clearPending: true,
        clearError: true,
      ),
    );
  }

  Future<void> _onFinished(
    CaptureFinished event,
    Emitter<CaptureState> emit,
  ) async {
    if (state.steps.isEmpty) {
      emit(
        state.copyWith(
          error: 'Record at least one leg before uploading this route.',
        ),
      );
      return;
    }

    // The last landmark is the destination door, so it is the one that carries
    // the room — that link is what lets guidance answer "take me to room 204".
    final landmarks = [...state.landmarks];
    landmarks[landmarks.length - 1] = landmarks.last.copyWith(
      roomId: event.destinationRoomId,
    );

    final draft = RouteDraft(
      buildingId: state.buildingId,
      destinationRoomId: event.destinationRoomId,
      landmarks: landmarks,
      steps: state.steps,
    );

    emit(state.copyWith(status: CaptureStatus.saving, clearError: true));
    try {
      final id = await _routes.saveRoute(draft);
      if (isClosed) return;
      emit(
        state.copyWith(
          status: CaptureStatus.saved,
          savedRouteId: id,
          landmarks: landmarks,
        ),
      );
    } catch (e, stack) {
      AppLogger.error('Route upload failed: $e', e, stack);
      if (isClosed) return;
      // Everything walked is still in state; the same event retries it.
      emit(
        state.copyWith(
          status: CaptureStatus.failed,
          error:
              'Could not upload the route. Check your connection and '
              'try again — nothing you recorded has been lost.',
        ),
      );
    }
  }

  @override
  Future<void> close() async {
    await _readSubscription?.cancel();
    await _stepSubscription?.cancel();
    await _detection.stop();
    await _textRecognition.stop();
    await _steps.stop();
    return super.close();
  }
}
