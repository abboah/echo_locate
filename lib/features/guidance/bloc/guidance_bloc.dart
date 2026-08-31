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
/// Two senses, each covering the other's blind spot: the clock says how far
/// along a leg the user is, and reading the sign at the end of it says they
/// have arrived. Dead reckoning alone drifts without bound; sign reading alone
/// cannot say how far to walk. **An OCR match advances the leg whatever the
/// clock says**, which is what stops distance error accumulating over a route —
/// every landmark returns it to zero.
///
/// One exception, and only one: a sign read while the clock says the walker is
/// still most of a corridor away is treated as *seeing* the landmark rather
/// than reaching it — a directory board is legible from the far end of a hall,
/// and advancing there would anchor the next leg, and its turn, metres short of
/// where they belong. It is announced, the countdown carries on, and the read
/// becomes an arrival as soon as either the distance agrees or the walker stops
/// getting closer while the sign stays in view. With no clock running at all —
/// no pedometer, no ARCore, which is most of the phones this is for — there is
/// nothing to disagree with and the read advances the leg as it always did.
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
    Duration arrivalNudgeAfter = const Duration(seconds: 12),
  }) : _arrivalNudgeAfter = arrivalNudgeAfter,
       _detection = detection,
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
    on<GuidanceDistanceReported>(_onDistanceReported);
    on<_StepsTicked>(_onStepsTicked);
    on<_ArrivalNudged>(_onArrivalNudged);
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

  /// How long a walker may stand at an unconfirmed landmark before being
  /// prompted again. Injectable so a test does not have to wait it out.
  final Duration _arrivalNudgeAfter;
  final CalloutPolicy _policy = CalloutPolicy();

  StreamSubscription<List<DetectedObstacle>>? _obstacleSubscription;
  StreamSubscription<List<String>>? _readSubscription;
  StreamSubscription<int>? _stepSubscription;

  /// The approach cue, the arrival prompt and the sighting are each once per
  /// leg. Without these the phone repeats them on every step or every frame
  /// past their thresholds.
  bool _saidClose = false;
  bool _saidArrived = false;
  bool _saidSighted = false;

  /// Set while waiting to nudge a walker who has arrived and confirmed
  /// nothing. Cancelled by the leg ending, however it ends.
  Timer? _arrivalNudge;

  /// How far from the end of a leg a read of its sign is a sighting rather
  /// than an arrival. Two checkpoints.
  static const double _sightingM = 6;

  /// When the sign first came into view on this leg, and how far along the leg
  /// the walker was then. Together they say whether they are still walking
  /// toward it or have stopped at it.
  DateTime? _sightedAt;
  double _sightedAtM = 0;

  /// How long a sign may stay in view without the walker getting closer to it
  /// before they are taken to be standing at it.
  static const Duration _sightingSettles = Duration(seconds: 3);

  /// Progress in that time small enough to count as standing still.
  static const double _sightingStillM = 1;

  /// How many progress cues have been spoken on this leg, which is also which
  /// checkpoint the walk has been talked up to.
  int _cuesSpoken = 0;

  /// When ARCore last reported a distance, or null if it never has.
  ///
  /// Both clocks are allowed to run — the step counter does not stop because
  /// the AR view is up — but only one may speak, or every checkpoint is
  /// announced twice a few paces apart. ARCore wins while it is reporting,
  /// because it measures the corridor rather than estimating it from a stride
  /// length that was itself estimated from the user's height.
  DateTime? _arReportedAt;

  /// How long after ARCore goes quiet the step counter takes the leg back.
  ///
  /// Short: this is the gap between AR state pushes (about a tenth of a
  /// second) plus room for a stall. Any longer and a walker whose AR session
  /// dies mid-corridor walks the rest of it in silence.
  static const Duration _arClockLifetime = Duration(seconds: 2);

  /// Metres between checkpoints along a leg.
  ///
  /// **Must match `ArGuidanceHandler.CHECKPOINT_M`.** The native side draws the
  /// ring on the next one of these and this side speaks at them, and the whole
  /// point of the pair is that a walker sees and hears the same walk.
  static const double checkpointM = 3;

  /// Checkpoints between spoken cues.
  ///
  /// Not every checkpoint. Three metres is about four paces, and a phone that
  /// says something every four paces down a thirty-metre corridor is a phone
  /// people turn off — which costs them the obstacle callouts too. Every second
  /// checkpoint is a sentence every eight seconds or so of walking, and the
  /// arrow carries the ones in between.
  static const int _cueEveryCheckpoints = 2;

  /// Metres left at which the leg stops counting down and starts arriving.
  ///
  /// Far enough out that the walker has time to start looking before they are
  /// standing at the thing, and far enough from the arrival prompt below that
  /// the two are not one on top of the other — the arbiter drops an
  /// equal-priority claim rather than queueing it, so two cues a second apart
  /// is one cue and a silence.
  static const double _approachM = 4;

  /// A leg with no room for both cues gets the arrival one only.
  static const double _roomForBothCuesM = 6;

  /// Fraction of the expected distance past which the user is assumed to have
  /// missed the landmark. Generous: a short stride, a detour round a cleaning
  /// trolley or a doubled-back corridor all inflate it honestly, and an
  /// unnecessary recovery sweep interrupts someone who was doing fine.
  static const double _overshootRatio = 1.2;

  /// Absolute margin past a leg before overshoot is called, whatever the ratio
  /// says.
  ///
  /// A ratio alone is wrong on a short leg: 1.2× of a three-metre hop to a
  /// doorway is sixty centimetres, so half a step past it would declare the
  /// walker lost and stop them for a recovery sweep. Whichever of the two is
  /// more forgiving wins, so this only ever loosens the rule.
  static const double _overshootMarginM = 2;

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
        walkedM: 0,
        stepCounting: counting,
        signReading: camera,
      ),
    );
    _announceLeg(emit);
  }

  void _onStepsTicked(_StepsTicked event, Emitter<GuidanceState> emit) {
    if (state.status != GuidanceStatus.guiding) return;

    final session = state.session;
    emit(state.copyWith(stepsThisLeg: event.steps));

    // Nothing to measure at all: no counter, or a leg up a staircase, which a
    // pedometer does not measure. The sign is the only thing that will advance
    // those.
    //
    // Note this asks whether the leg is *walkable*, not whether its length is
    // known: footfalls times a stride is real metres either way, and on a
    // route whose lengths are not metres those metres are the only reason the
    // walk can be paced at all.
    if (session == null || !state.stepCounting || !state.legWalkable) return;
    if (_arClockIsLive) return;

    _walked(emit, session.stride.distanceFor(event.steps));
  }

  /// ARCore's word for how far along the leg the walker is.
  ///
  /// Accepted even on a leg the step counter cannot measure — a phone with a
  /// dead pedometer still gets a paced walk out of this — and even on a route
  /// whose own lengths are not metres, where these metres are real and are
  /// what eventually gives that route its scale.
  void _onDistanceReported(
    GuidanceDistanceReported event,
    Emitter<GuidanceState> emit,
  ) {
    if (state.status != GuidanceStatus.guiding) return;
    if (!state.legWalkable) return;
    _arReportedAt = DateTime.now();
    _walked(emit, event.metres);
  }

  bool get _arClockIsLive {
    final at = _arReportedAt;
    return at != null && DateTime.now().difference(at) < _arClockLifetime;
  }

  /// The walk's clock: [metres] into the current leg, from whichever source is
  /// reading it, and everything that follows from that.
  ///
  /// **The leg is handed out a checkpoint at a time.** A corridor announced
  /// once at the top and then walked in silence gives a blind user nothing to
  /// check themselves against for twenty metres; by the time the phone speaks
  /// again they have either arrived or been lost for a while. So the leg is
  /// spoken as a countdown at [checkpointM] intervals, which is also the grid
  /// the arrow's ring hops along, and the last thing said before the landmark
  /// is what to look for rather than another number.
  ///
  /// Distances only ever go forward here. A clock that could run backwards —
  /// and ARCore's does, briefly, when it relocalises — would re-speak cues the
  /// walker has already heard and acted on.
  void _walked(Emitter<GuidanceState> emit, double metres) {
    if (metres <= state.walkedM) return;
    emit(state.copyWith(walkedM: metres));

    final total = state.legMetres;
    if (total <= 0) {
      _paceWithoutADistance(emit, metres);
      return;
    }

    // Far enough past the landmark that they cannot have simply overshot it by
    // a stride. Generous, because leg lengths come from whoever recorded the
    // route and an unnecessary recovery sweep interrupts somebody who was
    // doing fine.
    //
    // Skipped entirely when the length is an estimate. Being talked to on the
    // strength of a guess is fine; being stopped and told to sweep for a sign
    // on the strength of one is not, and the guess here is only ever as good
    // as the leg it was learned from.
    final ratioLimit = total * _overshootRatio;
    final marginLimit = total + _overshootMarginM;
    if (!state.legMetresEstimated &&
        metres > (ratioLimit > marginLimit ? ratioLimit : marginLimit)) {
      _enterRecovery(emit);
      return;
    }

    final remaining = total - metres;

    // Told to the camera, which spends its frames differently once the walker
    // is close: the sign at the end of this leg is what advances the walk
    // without asking them to confirm anything, and the last few metres are the
    // only place it can be read. See `AnalyserSchedule`.
    _detection.legRemainingM = remaining;

    // **The moment of arrival, which nothing else covers.** Distance says they
    // are there; no sign has been read, or the leg would have advanced. The
    // walker is standing at a door the phone cannot see, and until this was
    // here they stood there in silence — the last thing said was the approach
    // cue several metres back, and the next would have been a recovery sweep
    // several metres further on. Neither is any use to somebody who has in
    // fact arrived and only needs telling to look.
    if (remaining <= 0) {
      if (_saidArrived) return;
      _saidArrived = true;
      _say(_arrivalSentence(), AudioUse.guidanceProgress);
      // **And then keep asking.** The nudge is on a timer rather than on more
      // distance because the walker who most needs it is standing still: they
      // have arrived, stopped, and are looking for a sign that may not be
      // readable. Distance stops advancing at exactly the moment the prompting
      // has to carry on.
      _arrivalNudge?.cancel();
      _arrivalNudge = Timer(_arrivalNudgeAfter, () {
        if (!isClosed) add(const _ArrivalNudged());
      });
      return;
    }

    if (remaining <= _approachM) {
      // A leg too short to hold both cues gets the arrival one, which is the
      // one that names what to do about being there.
      if (_saidClose || total <= _roomForBothCuesM) return;
      _saidClose = true;
      _say(_approachSentence(), AudioUse.guidanceProgress);
      return;
    }

    final due = metres ~/ (checkpointM * _cueEveryCheckpoints);
    if (due <= _cuesSpoken) return;
    _cuesSpoken = due;
    _say('${remaining.round()} metres to go.', AudioUse.guidanceProgress);
  }

  /// Nobody has confirmed the landmark and the walker has stopped moving.
  ///
  /// Deliberately **not** an auto-advance. The whole route rests on a landmark
  /// being the only thing that moves it on: guess once here and the error rides
  /// into every leg after it, which is the failure landmark confirmation exists
  /// to prevent. So this asks again, and names the way to answer that does not
  /// involve finding a button on a screen you cannot see.
  void _onArrivalNudged(_ArrivalNudged event, Emitter<GuidanceState> emit) {
    if (state.status != GuidanceStatus.guiding) return;
    final session = state.session;
    final leg = state.currentLeg;
    if (session == null || leg == null) return;

    final name = session.nameOf(leg.toLandmarkId);
    _say(
      'Still looking for $name. Double-tap anywhere when you find it.',
      AudioUse.guidanceProgress,
    );
  }

  /// Whether the walker is still far enough from the end of the leg that a
  /// read of its sign is a sighting rather than an arrival.
  ///
  /// **Requires a clock that has actually moved.** With no pedometer and no
  /// ARCore — the mode most of the phones this app targets are stuck in —
  /// nothing ever measures a metre, and a rule that read that as "they cannot
  /// be there yet" would refuse every landmark on the route and strand the
  /// walker at the first one. No distance evidence means the read is the only
  /// evidence, which is the case this whole app is built to run on.
  bool get _sightedEarly {
    final total = state.legMetres;
    if (total <= 0 || state.walkedM <= 0) return false;
    if (_sightingHasSettled) return false;
    return total - state.walkedM > _sightingM;
  }

  /// Whether a sighting has stopped being an approach.
  ///
  /// The escape hatch, and the reason refusing to advance on a distant read is
  /// safe. A walker who really is standing at the sign — because the leg was
  /// recorded long, or their stride is nothing like the estimate — keeps it in
  /// frame and stops moving. Reads keep arriving; the clock does not. That is
  /// arrival, whatever the distance says, and without this they would stand
  /// there being told the landmark is ahead of them.
  bool get _sightingHasSettled {
    final at = _sightedAt;
    if (at == null) return false;
    if (DateTime.now().difference(at) < _sightingSettles) return false;
    return state.walkedM - _sightedAtM < _sightingStillM;
  }

  /// Says the landmark is in view, once, and keeps the countdown running.
  ///
  /// Worth saying at all because it is the first hard confirmation on the leg
  /// that the walker is in the right corridor — everything before it was dead
  /// reckoning. Worth saying only once because the sign stays in frame, and
  /// OCR reads it again on every frame it is in.
  void _announceSighting(Emitter<GuidanceState> emit, String name) {
    _sightedAt ??= DateTime.now();
    if (_saidSighted) return;
    _saidSighted = true;
    _sightedAtM = state.walkedM;
    _say('$name is ahead.', AudioUse.guidanceProgress);
  }

  /// Keeps the walk paced when the leg's length is not known in any unit.
  ///
  /// The first leg of a traced-plan route, before the scale has been learned.
  /// There is no countdown to give and no arrival to predict — but there is
  /// still a walker in a corridor who last heard something twenty metres ago,
  /// and for somebody eyes-free the difference between "the app is with me"
  /// and "the app has died" is worth a short sentence on the same cadence the
  /// numbers would have used.
  ///
  /// It says nothing it cannot stand behind: no distance, no "almost there".
  void _paceWithoutADistance(Emitter<GuidanceState> emit, double metres) {
    final due = metres ~/ (checkpointM * _cueEveryCheckpoints);
    if (due <= _cuesSpoken) return;
    _cuesSpoken = due;
    _say('Keep going.', AudioUse.guidanceProgress);
  }

  /// Works out how long a plan unit is, from a leg that has just been walked.
  ///
  /// **This is what turns a traced plan into a route that can be spoken.** The
  /// units of such a plan are arbitrary but consistent, so one leg measured by
  /// ARCore gives every other leg its length. Averaged rather than replaced,
  /// because a single leg walked round a cleaning trolley is long and one cut
  /// diagonally is short, and neither should own the whole route.
  ///
  /// Refused for a leg too short to divide accurately, and for one whose plan
  /// length is zero — a scale from those is a number with an arbitrary
  /// quantity of nonsense in it, applied to every corridor afterwards.
  void _learnScale(Emitter<GuidanceState> emit) {
    final session = state.session;
    final leg = state.currentLeg;
    if (session == null || leg == null || session.metric) return;
    if (state.walkedM < _scaleNeedsM || leg.distanceM <= 0) return;

    final measured = state.walkedM / leg.distanceM;
    final known = state.learnedScale;
    final scale = known == null ? measured : (known + measured) / 2;
    AppLogger.info(
      'SCALE ${scale.toStringAsFixed(1)} m/unit from '
      '${state.walkedM.toStringAsFixed(1)}m over ${leg.distanceM} units',
    );
    emit(state.copyWith(learnedScale: scale));
  }

  /// A leg shorter than this is not worth deriving a whole route's scale from.
  static const double _scaleNeedsM = 5;

  /// The last thing said before the landmark.
  ///
  /// A number is no use here — "one metre to go" is not something anybody can
  /// act on — so this is the handover to whatever will actually confirm the
  /// landmark, which on a phone with a working camera is a sweep for the sign
  /// and on one without is the user's own eyes and hands.
  String _approachSentence() {
    final session = state.session;
    final leg = state.currentLeg;
    if (session == null || leg == null) return 'Almost there.';
    final name = session.nameOf(leg.toLandmarkId);
    final side = _sideOfLandmark();

    // A side to sweep toward is the most useful half-second of this sentence
    // for somebody who cannot see, so it goes first and the name goes with it.
    if (side != null) {
      final look = state.signReading
          ? 'Sweep your phone to find the sign.'
          : 'Look for it.';
      return 'Almost there — $name should be on your $side. $look';
    }

    // No side to offer, but the route may still turn here, and knowing that is
    // worth as much: it is the difference between arriving and arriving ready.
    final turn = _turnAtLandmark();
    final next = turn == null ? '' : ', then you turn $turn';
    return state.signReading
        ? 'Almost there — sweep your phone to find $name$next.'
        : 'Almost there — look for $name$next.';
  }

  /// Which side the landmark is on, inferred from the turn made at it.
  ///
  /// **Only for landmarks that are themselves a way through.** A door or an
  /// entrance the route turns into is on the side it turns toward, and that is
  /// solid enough to say out loud. A junction or a corridor sign is not: the
  /// turn there describes where the route goes next, and telling a blind user a
  /// sign is on their right when the corridor merely bends right sends them
  /// sweeping a blank wall — which costs trust in every other cue the app
  /// gives them. Those get [_turnAtLandmark] instead, which claims only what
  /// the route actually records.
  String? _sideOfLandmark() {
    final session = state.session;
    final leg = state.currentLeg;
    if (session == null || leg == null) return null;
    final kind = session.landmarkOf(leg.toLandmarkId)?.kind;
    if (kind != LandmarkKind.door && kind != LandmarkKind.entrance) return null;
    return _turnAtLandmark();
  }

  /// Which way the route turns at the end of this leg, when it turns enough to
  /// be worth saying. Null on a leg the route carries straight on from.
  String? _turnAtLandmark() {
    final next = state.legIndex + 1;
    if (next >= state.plan.legs.length) return null;
    final turn = state.plan.legs[next].turnDeg;
    if (turn.abs() < _worthSayingDeg) return null;
    return turn > 0 ? 'right' : 'left';
  }

  /// A turn smaller than this is a corridor that is not quite straight, not a
  /// direction worth putting in somebody's ear.
  static const int _worthSayingDeg = 45;

  /// What the phone says when the distance runs out and nothing has confirmed
  /// the landmark.
  ///
  /// Phrased as *should be*, deliberately. The phone does not know the walker
  /// is at the door — it knows they have walked the length somebody recorded
  /// for this leg, which is a different and weaker claim, and a leg recorded
  /// long or short makes it wrong by a few metres either way. Saying "you have
  /// arrived" here would be the app asserting something it cannot see; saying
  /// nothing, which is what it did before, leaves them standing at a door with
  /// no idea the phone thinks they are there.
  String _arrivalSentence() {
    final session = state.session;
    final leg = state.currentLeg;
    if (session == null || leg == null) return 'You should be there now.';
    final name = session.nameOf(leg.toLandmarkId);
    return state.signReading
        ? '$name should be right here — sweep your phone to find the sign.'
        : '$name should be right here. Tap to confirm when you find it.';
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
        // **Seeing a sign is not standing at it.** A directory board or a big
        // door plate is legible from the far end of a corridor, and advancing
        // the leg on that read puts the walker at the landmark in the app's
        // reckoning while they are still fifteen metres short of it — which
        // then anchors the next leg, and its turn, from the wrong place.
        //
        // Only when the clock disagrees by that much, though. With no
        // trustworthy distance there is nothing to disagree with, and the read
        // is the best evidence there is: that is the case this whole app is
        // built to run on.
        if (_sightedEarly) {
          _announceSighting(emit, session.nameOf(leg.toLandmarkId));
          return;
        }
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
    // Logged *before* the reset, while the numbers that decided it still
    // exist. The gap between where the clock thought the walker was and where
    // the landmark actually is is the whole accuracy question for this app,
    // and this line is the only place it is ever written down.
    AppLogger.info(
      'ADVANCE leg ${state.legIndex} -> $name at '
      '${state.walkedM.toStringAsFixed(1)}m of '
      '${state.legMetres.toStringAsFixed(1)}m',
    );
    // Before the reset, while [walkedM] still holds what this leg measured.
    _learnScale(emit);
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
          walkedM: 0,
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
        walkedM: 0,
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
            walkedM: 0,
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
          walkedM: 0,
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
            walkedM: 0,
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
    emit(state.copyWith(status: GuidanceStatus.recovering, askForHelp: true));
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
    // Stripped, because every branch below adds its own punctuation and a
    // recorded instruction may or may not already carry some. A contributor
    // types a clause — "past the lifts" — but a traced plan's edges are
    // generated as whole sentences, so the phone said "Continue to the door..
    // Look for Main corridor."
    final base = _unpunctuated(recorded ?? 'Continue to $name');
    final expected = state.expectedSteps;
    if (expected > 0) return '$base, about $expected steps.';
    // Without a count the user needs something to look for. Generated wording
    // already names the landmark, so appending "look for" to it just says the
    // name twice — which is what a traced-plan route, whose edges carry no
    // recorded phrasing, would otherwise do on every single leg.
    return recorded == null ? '$base.' : '$base. Look for $name.';
  }

  /// [sentence] without whatever punctuation it already ends in.
  ///
  /// Visible for testing: the doubled full stop it prevents is the kind of
  /// thing that reads as sloppy on screen and sounds like a stutter aloud,
  /// which matters more here than most places.
  static String unpunctuated(String sentence) => _unpunctuated(sentence);

  static String _unpunctuated(String sentence) {
    var end = sentence.length;
    while (end > 0 && '.,;: '.contains(sentence[end - 1])) {
      end--;
    }
    return end == 0 ? sentence : sentence.substring(0, end);
  }

  /// Puts the walk's clock back to the start of a leg.
  ///
  /// Called wherever the leg changes — confirmed, re-planned, relocalised onto
  /// — because every one of those means the distance walked so far is now
  /// distance walked on a leg that is over. Missing one leaves the next leg
  /// starting halfway through its own countdown.
  void _resetLegCount() {
    _steps.reset();
    _saidClose = false;
    _saidArrived = false;
    _saidSighted = false;
    _sightedAt = null;
    _sightedAtM = 0;
    _cuesSpoken = 0;
    _arReportedAt = null;
    // Carried into the next leg it would keep the camera reading signs as
    // though the walker were still arriving somewhere, at the start of a
    // corridor where there is nothing yet to read.
    _detection.legRemainingM = null;
    // Left running, it would prompt for a landmark the walker confirmed a
    // corridor ago, naming a place they have already left.
    _arrivalNudge?.cancel();
    _arrivalNudge = null;
  }

  void _say(String text, AudioUse use, {bool interrupt = false}) {
    if (!state.voiceOn) return;
    // Stamped with where on the leg it was said, because that is the pair a
    // walk has to be read back as: what the phone said and where the walker
    // was when it said it. On a real walk nobody can hold both in their head,
    // and afterwards there is nothing to check a complaint against.
    AppLogger.info(
      'SAY leg ${state.legIndex} '
      '${state.walkedM.toStringAsFixed(1)}/${state.legMetres.toStringAsFixed(1)}m '
      '[${use.name}] $text',
    );
    unawaited(_speech.speak(text, interrupt: interrupt, use: use));
  }

  @override
  Future<void> close() async {
    _arrivalNudge?.cancel();
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
