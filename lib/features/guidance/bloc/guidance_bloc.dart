import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../../core/models/landmark.dart';
import '../../../core/utils/logger.dart';
import '../../../services/audio/audio_arbiter.dart';
import '../../../services/haptics/haptic_service.dart';
import '../../../services/mapping/route_planner.dart';
import '../../../services/motion/step_service.dart';
import '../../../services/sensing/callout_policy.dart';
import '../../../services/sensing/detected_obstacle.dart';
import '../../../services/sensing/detection_service.dart';
import '../../../services/sensing/landmark_matcher.dart';
import '../../../services/sensing/text_recognition_service.dart';
import '../../../services/speech/speech_service.dart';
import '../guidance_session.dart';

part 'guidance_event.dart';
part 'guidance_state.dart';

/// Walks a user along a route by ear.
///
/// Two senses, each covering the other's blind spot: the step counter says how
/// far along a leg the user is, and reading the sign at the end of it says they
/// have arrived. Dead reckoning alone drifts without bound; sign reading alone
/// cannot say how far to walk. **An OCR match advances the leg whatever the
/// count says**, which is what stops step error accumulating over a route —
/// every landmark returns it to zero.
///
/// Degrades down the ladder in spec §7 B5 rather than failing: no step counter
/// means sign-reading alone, no camera means confirming landmarks by hand,
/// nothing recognised means a recovery sweep, and a sweep that finds nothing
/// means telling the user to ask a person. The last rung is a designed
/// outcome, not a crash — it is what blind travellers already do.
class GuidanceBloc extends Bloc<GuidanceEvent, GuidanceState> {
  GuidanceBloc({
    required DetectionService detection,
    required TextRecognitionService textRecognition,
    required StepService steps,
    required SpeechService speech,
    required HapticService haptics,
    LandmarkMatcher matcher = const LandmarkMatcher(),
    RoutePlanner planner = const RoutePlanner(),
  })  : _detection = detection,
        _textRecognition = textRecognition,
        _steps = steps,
        _speech = speech,
        _haptics = haptics,
        _matcher = matcher,
        _planner = planner,
        super(const GuidanceState()) {
    on<GuidanceStarted>(_onStarted);
    on<GuidanceVoiceToggled>(_onVoiceToggled);
    on<GuidanceLandmarkConfirmed>(_onLandmarkConfirmed);
    on<GuidanceLostReported>(_onLostReported);
    on<_StepsTicked>(_onStepsTicked);
    on<_ReadsArrived>(_onReadsArrived);
    on<_ObstaclesArrived>(_onObstaclesArrived);
  }

  final DetectionService _detection;
  final TextRecognitionService _textRecognition;
  final StepService _steps;
  final SpeechService _speech;
  final HapticService _haptics;
  final LandmarkMatcher _matcher;
  final RoutePlanner _planner;
  final CalloutPolicy _policy = CalloutPolicy();

  StreamSubscription<List<DetectedObstacle>>? _obstacleSubscription;
  StreamSubscription<List<String>>? _readSubscription;
  StreamSubscription<int>? _stepSubscription;

  /// Progress prompts are once-per-leg. Without these the phone repeats
  /// "about halfway" on every step past the midpoint.
  bool _saidHalfway = false;
  bool _saidClose = false;

  /// Fraction of the expected count past which the user is assumed to have
  /// missed the landmark. Generous: a short stride, a detour round a cleaning
  /// trolley or a doubled-back corridor all inflate the count honestly, and
  /// an unnecessary recovery sweep interrupts someone who was doing fine.
  static const double _overshootRatio = 1.2;

  Future<void> _onStarted(
    GuidanceStarted event,
    Emitter<GuidanceState> emit,
  ) async {
    final session = event.session;
    if (session.plan.isEmpty) {
      emit(
        state.copyWith(
          status: GuidanceStatus.arrived,
          session: session,
          instruction: 'You are already at ${session.destinationName}.',
        ),
      );
      return;
    }

    final camera = await _detection.start();
    if (isClosed) return;
    if (camera) {
      _textRecognition.start();
      _readSubscription = _textRecognition.reads.listen((lines) {
        if (!isClosed) add(_ReadsArrived(lines));
      });
      _obstacleSubscription = _detection.obstacles.listen((obstacles) {
        if (!isClosed) add(_ObstaclesArrived(obstacles));
      });
    } else {
      AppLogger.warn('Guidance has no camera — landmarks confirmed by hand');
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
        status: GuidanceStatus.guiding,
        session: session,
        legIndex: 0,
        stepsThisLeg: 0,
        stepCounting: counting,
        signReading: camera,
      ),
    );
    _announceLeg(emit);
  }

  void _onStepsTicked(_StepsTicked event, Emitter<GuidanceState> emit) {
    if (state.status != GuidanceStatus.guiding) return;

    final expected = state.expectedSteps;
    emit(state.copyWith(stepsThisLeg: event.steps));

    // Nothing to measure against: an uncounted leg (stairs) or no counter at
    // all. The sign is the only thing that will advance this leg.
    if (expected <= 0) return;

    final ratio = event.steps / expected;
    if (ratio > _overshootRatio) {
      _enterRecovery(emit);
      return;
    }
    if (ratio >= 0.8 && !_saidClose) {
      _saidClose = true;
      _say(
        "You're close — sweep your phone to find the sign.",
        AudioUse.guidanceProgress,
      );
    } else if (ratio >= 0.5 && !_saidHalfway) {
      _saidHalfway = true;
      _say('About halfway.', AudioUse.guidanceProgress);
    }
  }

  void _onReadsArrived(_ReadsArrived event, Emitter<GuidanceState> emit) {
    final session = state.session;
    if (session == null || state.status == GuidanceStatus.arrived) return;

    for (final line in event.lines) {
      if (state.status == GuidanceStatus.recovering) {
        // Lost: any landmark in the building tells us something. Ambiguous
        // reads are refused by the matcher rather than guessed at.
        final found = _matcher.match(line, session.landmarks);
        if (found != null) {
          _relocalise(found, emit);
          return;
        }
        continue;
      }

      final leg = state.currentLeg;
      if (leg == null) return;
      final expected = session.landmarkOf(leg.toLandmarkId);
      if (expected != null && _matcher.matches(line, expected)) {
        _advance(emit);
        return;
      }
    }
  }

  void _onObstaclesArrived(
    _ObstaclesArrived event,
    Emitter<GuidanceState> emit,
  ) {
    final callout = _policy.evaluate(event.obstacles);
    if (callout == null) return;

    emit(state.copyWith(callout: callout));
    if (callout.urgent) unawaited(_haptics.alert());
    _say(
      callout.spoken,
      callout.urgent ? AudioUse.urgentSpeech : AudioUse.speech,
      interrupt: callout.urgent,
    );
  }

  void _onLandmarkConfirmed(
    GuidanceLandmarkConfirmed event,
    Emitter<GuidanceState> emit,
  ) {
    if (state.status == GuidanceStatus.arrived || state.session == null) return;
    _advance(emit);
  }

  void _onLostReported(
    GuidanceLostReported event,
    Emitter<GuidanceState> emit,
  ) {
    if (state.session == null) return;
    // Already sweeping and still lost: the phone has nothing better to offer
    // than the thing that actually works.
    if (state.status == GuidanceStatus.recovering) {
      _askForHelp(emit);
      return;
    }
    _enterRecovery(emit);
  }

  void _onVoiceToggled(
    GuidanceVoiceToggled event,
    Emitter<GuidanceState> emit,
  ) {
    final voiceOn = !state.voiceOn;
    emit(state.copyWith(voiceOn: voiceOn));
    if (!voiceOn) unawaited(_speech.stop());
  }

  /// Confirms the current leg's landmark and moves on, or finishes the route.
  void _advance(Emitter<GuidanceState> emit) {
    final session = state.session!;
    final leg = state.currentLeg;
    if (leg == null) return;

    final name = session.nameOf(leg.toLandmarkId);
    unawaited(_haptics.confirm());
    _resetLegCount();

    final next = state.legIndex + 1;
    if (next >= state.plan.legs.length) {
      final arrival = 'You have arrived at ${session.destinationName}.';
      emit(
        state.copyWith(
          status: GuidanceStatus.arrived,
          legIndex: next,
          stepsThisLeg: 0,
          lastLandmarkName: name,
          instruction: arrival,
        ),
      );
      _say(arrival, AudioUse.landmarkReached);
      return;
    }

    emit(
      state.copyWith(
        status: GuidanceStatus.guiding,
        legIndex: next,
        stepsThisLeg: 0,
        lastLandmarkName: name,
      ),
    );
    _announceLeg(emit, prefix: '$name.', use: AudioUse.landmarkReached);
  }

  void _enterRecovery(Emitter<GuidanceState> emit) {
    emit(state.copyWith(status: GuidanceStatus.recovering));
    _say(
      'Stop, and sweep your phone slowly left to right.',
      AudioUse.landmarkReached,
    );
  }

  /// Works out where the user actually is from a landmark they can see, and
  /// re-guides from there (spec §7 B5 rung 3).
  void _relocalise(Landmark found, Emitter<GuidanceState> emit) {
    final session = state.session!;
    final name = session.nameOf(found.id);
    final onRoute = state.plan.landmarkIds.indexOf(found.id);

    if (onRoute >= 0) {
      // Still on the route, just not where guidance thought. Walking past a
      // landmark is the common case and needs no re-planning: pick the walk up
      // from the leg that starts here.
      if (onRoute >= state.plan.legs.length) {
        final arrival = 'You have arrived at ${session.destinationName}.';
        emit(
          state.copyWith(
            status: GuidanceStatus.arrived,
            legIndex: onRoute,
            stepsThisLeg: 0,
            lastLandmarkName: name,
            instruction: arrival,
          ),
        );
        _say(arrival, AudioUse.landmarkReached);
        return;
      }
      _resetLegCount();
      emit(
        state.copyWith(
          status: GuidanceStatus.guiding,
          legIndex: onRoute,
          stepsThisLeg: 0,
          lastLandmarkName: name,
        ),
      );
      _announceLeg(
        emit,
        prefix: "You're at $name.",
        use: AudioUse.landmarkReached,
      );
      return;
    }

    // Off the route entirely. The building's graph usually knows a way on from
    // here, even though nobody recorded this particular walk.
    final graph = session.graph;
    final destination = session.destinationLandmarkId;
    if (graph != null && destination != null) {
      final replanned = _planner.plan(graph, from: found.id, to: destination);
      if (replanned != null && !replanned.isEmpty) {
        _resetLegCount();
        emit(
          state.copyWith(
            status: GuidanceStatus.guiding,
            session: session.copyWith(plan: replanned),
            legIndex: 0,
            stepsThisLeg: 0,
            lastLandmarkName: name,
          ),
        );
        _announceLeg(
          emit,
          prefix: "You're at $name. Re-routing.",
          use: AudioUse.landmarkReached,
        );
        return;
      }
    }

    _askForHelp(emit, at: name);
  }

  /// Rung 4. Not a failure state: it is the fallback that always works, and
  /// saying it plainly is more use than another sweep that will not.
  void _askForHelp(Emitter<GuidanceState> emit, {String? at}) {
    final session = state.session!;
    final where = at == null ? '' : "You're at $at. ";
    emit(
      state.copyWith(status: GuidanceStatus.recovering, askForHelp: true),
    );
    _say(
      "${where}Ask someone nearby: you're looking for "
      '${session.destinationName}.',
      AudioUse.landmarkReached,
    );
  }

  /// Says what to do next, optionally led by where the user has just been
  /// confirmed to be.
  ///
  /// **One utterance, never two.** The arbiter refuses an equal-priority
  /// claim rather than queueing it (see [AudioArbiter]), so speaking
  /// "Help desk." and the next instruction separately meant the instruction
  /// was dropped while the confirmation was still playing — the user heard
  /// where they were and nothing about where to go. Found on a device, not in
  /// a test: both calls "succeeded", one just never reached the speaker.
  void _announceLeg(
    Emitter<GuidanceState> emit, {
    String prefix = '',
    AudioUse use = AudioUse.guidanceProgress,
  }) {
    final sentence = _legSentence();
    if (sentence.isEmpty) return;
    emit(state.copyWith(instruction: sentence));
    _say(prefix.isEmpty ? sentence : '$prefix $sentence', use);
  }

  /// What to say at the start of a leg.
  ///
  /// A step count is only promised when there is a counter that can check it
  /// and a leg it can measure — "about forty steps" on a staircase, or on a
  /// phone with no pedometer, is a number the app cannot stand behind.
  String _legSentence() {
    final session = state.session;
    final leg = state.currentLeg;
    if (session == null || leg == null) return '';

    final name = session.nameOf(leg.toLandmarkId);
    final recorded = leg.instruction;
    final base = recorded ?? 'Continue to $name';
    final expected = state.expectedSteps;
    if (expected > 0) return '$base, about $expected steps.';
    // Without a count the user needs something to look for. Generated wording
    // already names the landmark, so appending "look for" to it just says the
    // name twice — which is what a traced-plan route, whose edges carry no
    // recorded phrasing, would otherwise do on every single leg.
    return recorded == null ? '$base.' : '$base. Look for $name.';
  }

  void _resetLegCount() {
    _steps.reset();
    _saidHalfway = false;
    _saidClose = false;
  }

  void _say(String text, AudioUse use, {bool interrupt = false}) {
    if (!state.voiceOn) return;
    unawaited(_speech.speak(text, interrupt: interrupt, use: use));
  }

  @override
  Future<void> close() async {
    await _obstacleSubscription?.cancel();
    await _readSubscription?.cancel();
    await _stepSubscription?.cancel();
    await _detection.stop();
    await _textRecognition.stop();
    await _steps.stop();
    await _speech.stop();
    _policy.reset();
    return super.close();
  }
}
