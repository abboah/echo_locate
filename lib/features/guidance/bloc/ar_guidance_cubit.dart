import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../../core/utils/logger.dart';
import '../../../services/mapping/room_plan_bridge.dart';
import '../../../services/mapping/route_registration.dart';
import '../../../services/vision/ar_guidance_service.dart';
import '../../../services/vision/depth_frame.dart' show ArCoreAvailability;
import 'guidance_bloc.dart';

part 'ar_guidance_state.dart';

/// The AR layer over a guidance session: arrows on the floor, one leg at a time.
///
/// ## Why this is a separate cubit rather than part of [GuidanceBloc]
///
/// [GuidanceBloc] is the route. It works with no camera, no ARCore and no
/// screen, which is the mode a blind user walks in and the mode this app's
/// typical uncertified phone is stuck in. Folding an ARCore session into it
/// would make the thing that always works depend on the thing that usually
/// cannot, and every test of the route would have to mock a renderer.
///
/// So this cubit *listens* to that bloc and mirrors it into the world: when the
/// leg changes, the arrow is re-anchored; when the walk ends or the walker is
/// lost, it is cleared. If this cubit never starts, the route is unaffected.
///
/// ## The one thing that flows back
///
/// ARCore measures how far down the corridor the walker has come, and it
/// measures it better than counting footfalls against an estimated stride
/// length does. That number — and only that number — is handed to the bloc, as
/// [GuidanceDistanceReported], so that the spoken checkpoints and the drawn
/// ones are the same checkpoints.
///
/// It is a *measurement*, never a decision: it cannot advance a leg, end a
/// route or move the walker onto another one. Landmarks do all of that, and a
/// distance that disagrees with a sign is the distance that is wrong. Guidance
/// treats the event as optional and falls back to the step counter the moment
/// it stops arriving, which is what keeps the route working on the phones that
/// have no ARCore at all.
///
/// ## What "anchoring" means here, and why it is a single call
///
/// Native takes the direction the walker was **moving**, turns it by the leg's
/// `turnDeg`, and fixes that line in world coordinates. That happens once per
/// leg, at the moment a landmark is confirmed — which is exactly when the
/// walker is standing at a known point having just walked a known direction.
/// Between confirmations nothing is recomputed, so the arrow points into the
/// room instead of chasing the phone. The checkpoints the walker is actually
/// sent to are positions along that one line.
class ArGuidanceCubit extends Cubit<ArGuidanceState> {
  ArGuidanceCubit(this._ar, this._guidance) : super(const ArGuidanceState()) {
    _guidanceSubscription = _guidance.stream.listen(_onGuidance);
  }

  final ArGuidanceService _ar;
  final GuidanceBloc _guidance;

  StreamSubscription<GuidanceState>? _guidanceSubscription;
  StreamSubscription<ArGuidanceFrame>? _states;

  /// The leg the arrows are currently drawn for, so an unrelated state change
  /// upstream — voice toggled, an obstacle called out, a step counted — does
  /// not re-anchor a leg that is already anchored and being walked.
  int? _anchoredLeg;

  /// The transform from the plan's frame into ARCore's world, once solved.
  ///
  /// Null until the walker has taken enough steps for a direction of travel to
  /// exist — see [_tryRegister]. Everything the registered route does depends
  /// on this one value being right, and nothing downstream can tell whether it
  /// is; [ArGuidanceState.offRouteM] is the only evidence, and it arrives
  /// after the walker has already acted on the arrows.
  Registration? _registration;

  /// The route in the plan's frame, metres, kept so it can be re-transformed
  /// when the registration is re-solved.
  RoutePath? _path;

  List<Offset> get _planPath => _path?.pointsM ?? const [];

  /// Where ARCore had the phone when the walk began.
  ///
  /// **The anchor, and it has to be this rather than where they are standing
  /// when the registration is finally solved.** Solving needs a direction of
  /// travel, and a direction of travel needs a couple of metres of walking —
  /// so by the time the transform can be computed the walker is already some
  /// way down their first corridor. Pinning the start of the route to where
  /// they are *then* slides the whole building forward by however far they
  /// walked while the phone was working it out, and every ring after it lands
  /// that much too far along.
  ///
  /// Taken from the first tracked frame instead, which is where they were when
  /// they picked the room they were standing in.
  WorldPoint? _startWorld;

  /// Whether a registration has been attempted and refused for good.
  ///
  /// Set when the session carries no geometry — a recorded-walk route, or a
  /// traced plan with no scale. There is nothing to wait for in that case and
  /// the leg arrows carry the walk as they always did.
  bool _cannotRegister = false;

  /// True between the first await in [start] and the session being up.
  ///
  /// Bringing up ARCore takes a moment, and both ends of that moment are
  /// reachable: the page boots and the app is backgrounded, or a resume lands
  /// while the boot is still running. Without this, the second caller sees
  /// `running == false`, starts a *second* session, and the two fight over the
  /// camera.
  bool _starting = false;

  /// Set when [stop] was called while [start] was still in flight, so the
  /// session is torn down as soon as it exists rather than left holding the
  /// camera in the background.
  bool _stopRequested = false;

  /// The viewport last reported, and when, so an unchanged one is not sent
  /// again on every rebuild.
  (int, int)? _viewport;
  DateTime? _viewportAt;

  /// Whether this phone can run the AR view at all.
  ///
  /// Checked before anything is started, because on most of the hardware this
  /// app targets the answer is no, and the honest response is to leave the
  /// guidance screen exactly as it was rather than to show a broken camera.
  Future<bool> checkAvailability() async {
    final availability = await _ar.checkAvailability();
    if (isClosed) return false;
    emit(state.copyWith(availability: availability));
    return availability == ArCoreAvailability.supported;
  }

  /// Brings up the session behind the guidance screen.
  ///
  /// **Start this before [GuidanceBloc] starts detection.** ARCore takes the
  /// camera exclusively, so whichever of the two opens it first wins: with the
  /// session already streaming, `DetectionService` attaches to its frames and
  /// sign reading carries on; the other order leaves the camera plugin holding
  /// the camera and ARCore unable to start at all.
  Future<void> start({
    required int viewWidth,
    required int viewHeight,
  }) async {
    if (state.running || _starting) return;
    _starting = true;
    _stopRequested = false;

    try {
      final failure = await _ar.start(
        viewWidth: viewWidth,
        viewHeight: viewHeight,
      );
      if (isClosed) return;
      if (failure != null) {
        // A session that was deliberately closed on its way up did not fail —
        // putting "the AR view was closed" on the screen would be the app
        // reporting its own housekeeping as a problem.
        if (!_stopRequested) {
          AppLogger.warn('AR guidance unavailable: $failure');
          emit(state.copyWith(error: failure));
        }
        return;
      }

      // The frame feed is the whole point of running ARCore rather than the
      // camera plugin here: it is what keeps obstacle callouts and sign reading
      // alive while the AR view is up.
      await _ar.setAnalysis(enabled: true);
      if (isClosed) return;

      _viewport = (viewWidth, viewHeight);
      _viewportAt = DateTime.now();
      _states = _ar.states.listen(_onArFrame);

      emit(
        state.copyWith(
          running: true,
          textureId: _ar.textureId,
          clearError: true,
        ),
      );
      // A leg may already be under way — the guidance bloc starts before this
      // does — so anchor whatever is current rather than waiting for the next
      // landmark, which could be a corridor away.
      _anchorFor(_guidance.state);
    } finally {
      _starting = false;
    }

    // The screen went away while ARCore was coming up. Nothing has drawn a
    // frame yet, and the camera must not stay held in the background.
    if (_stopRequested && !isClosed) await stop();
  }

  /// One state push from the session.
  ///
  /// Read-only, deliberately. Native reports what the arrows are doing —
  /// including recovering their own anchor after ARCore relocalises, which it
  /// does without asking, because it is the side that knows how much of the leg
  /// has been walked and therefore that the turn has already been made. Legs
  /// are issued here on landmarks and nowhere else; nothing on this stream
  /// should ever re-anchor one.
  void _onArFrame(ArGuidanceFrame frame) {
    if (isClosed) return;

    // The session stopped without being asked — the camera went to another app,
    // or a call came in. Let the texture go: it points at nothing now, and a
    // `Texture` over a released id draws the last frame forever, which looks
    // exactly like a working camera that has stopped moving.
    if (frame.sessionEnded) {
      AppLogger.warn('AR session ended on its own — releasing the view');
      unawaited(stop());
      return;
    }

    emit(
      state.copyWith(
        tracking: frame.tracking,
        issue: frame.issue,
        hasLeg: frame.hasLeg,
        headingReady: frame.headingReady,
        anchoredFromCamera: frame.anchoredFromCamera,
        remainingM: frame.remainingM,
        overshootM: frame.overshootM,
        bearingDeg: frame.bearingDeg,
        hasRoute: frame.hasRoute,
        offRouteM: frame.offRouteM,
      ),
    );

    // The moment the walk becomes navigable rather than merely paced. Tried on
    // every frame until it takes, because what it is waiting for — a couple of
    // metres of walking — arrives whenever the walker chooses.
    _tryRegister(frame);

    // The one thing that flows back — see the note on this class. Only while a
    // leg is anchored and tracking is good, because a paused session reports
    // the last distance it knew and guidance would hear a walker standing
    // still as a walker who has stopped where they were told to.
    //
    // Sent whatever the route's units are. **These metres are always real** —
    // ARCore measures the corridor, not the plan — and on a route whose own
    // lengths are fractions of a traced image they are the only real distance
    // in the system: what paces the walk before the scale is known, and what
    // the scale is then learned from.
    if (frame.hasLeg && frame.tracking == CaptureTrackingLike.tracking) {
      _advancePastFinishedLegs(frame);
      _guidance.add(GuidanceDistanceReported(_legDistanceFrom(frame)));
    }
  }

  /// Tells the session what it is drawing into.
  ///
  /// Called from a layout callback, which fires on every rebuild — and the
  /// arrows rebuild this screen several times a second. Repeating an unchanged
  /// viewport would put a platform round trip on each of those for nothing.
  ///
  /// Throttled rather than deduplicated outright, because the size is not the
  /// whole story: a phone turned end over end keeps exactly the same width and
  /// height, and the *display rotation* — which only native can read, and which
  /// sets both the camera's orientation and the one ML Kit is told to expect —
  /// changes underneath it. Native compares all three and ignores a repeat, so
  /// the cost of asking once a second is nothing and the cost of never asking
  /// is a sideways picture and OCR that reads no text at all.
  Future<void> setViewport({
    required int viewWidth,
    required int viewHeight,
  }) async {
    final now = DateTime.now();
    final unchanged = _viewport == (viewWidth, viewHeight);
    final checkedAt = _viewportAt;
    if (unchanged &&
        checkedAt != null &&
        now.difference(checkedAt) < _viewportRecheck) {
      return;
    }
    _viewport = (viewWidth, viewHeight);
    _viewportAt = now;
    await _ar.setViewport(viewWidth: viewWidth, viewHeight: viewHeight);
  }

  /// How often an unchanged viewport is offered to native anyway, so a rotation
  /// it alone can see is picked up.
  static const Duration _viewportRecheck = Duration(seconds: 1);

  /// Switches between the camera view and the plain high-contrast one.
  ///
  /// The session keeps running either way: it is still feeding ML Kit, and a
  /// walker who flips to the plain view to read the instruction should not have
  /// to wait for tracking to come back when they flip return. Only the picture
  /// changes.
  void setCameraVisible({required bool visible}) =>
      emit(state.copyWith(cameraVisible: visible));

  /// Releases the camera when the screen goes away or the app backgrounds.
  Future<void> stop() async {
    if (_starting) {
      // Say so now — the service carries the request across the start it is
      // waiting on — and again when it lands, to settle the state. Returning
      // here instead would leave ARCore holding the camera through a
      // backgrounded app.
      _stopRequested = true;
      await _ar.stop();
      return;
    }
    if (!state.running) return;
    await _states?.cancel();
    _states = null;
    _anchoredLeg = null;
    _viewport = null;
    _viewportAt = null;
    await _ar.stop();
    if (isClosed) return;
    emit(
      state.copyWith(
        running: false,
        clearTexture: true,
        hasLeg: false,
        tracking: CaptureTrackingLike.stopped,
        issue: ArGuidanceIssue.none,
        anchoredFromCamera: false,
        remainingM: 0,
        overshootM: 0,
        bearingDeg: 0,
      ),
    );
  }

  /// Solves the plan-to-world transform, and lays the route into the room.
  ///
  /// ## What it is waiting for
  ///
  /// One correspondence and one direction (see `route_registration.dart`). The
  /// correspondence is free: the walker picked the room they are standing in,
  /// so the start of the route is where they are. The direction is not — it
  /// needs a couple of metres of walking before ARCore can say which way they
  /// are going, and until then there is nothing to rotate the plan by.
  ///
  /// So this does nothing at all for the first few steps of a route, and the
  /// screen says as much. That is a real cost and it buys the thing the whole
  /// change exists for: after those steps the arrow is pointing at the actual
  /// destination rather than down a line anchored to however the phone
  /// happened to be held.
  ///
  /// ## Why it keeps trying
  ///
  /// Registering once and trusting it forever would inherit exactly the flaw
  /// it replaces. ARCore's world drifts, and a rotation solved from two metres
  /// of walking is worth about as much as two metres of walking. So while the
  /// walker is close to the line the registration stands, and when they are
  /// persistently far from it the solve is repeated against fresh motion —
  /// which is the same evidence, taken later, with more of the corridor behind
  /// it.
  void _tryRegister(ArGuidanceFrame frame) {
    if (_cannotRegister || _planPath.length < 2) return;

    // Where they set off from, remembered before anything can be solved. See
    // the note on [_startWorld] — this is the frame that matters, and it has
    // usually gone by the time the rest of this can run.
    if (_startWorld == null &&
        frame.isTracking &&
        frame.cameraX != null &&
        frame.cameraZ != null) {
      _startWorld = WorldPoint(frame.cameraX!, frame.cameraZ!);
    }

    if (!frame.canRegister) return;

    // Already registered and the walker is following the line: nothing to fix,
    // and re-solving would move the route under somebody who is doing fine.
    if (_registration != null && frame.offRouteM <= _registrationHoldsM) {
      _offRouteSince = null;
      return;
    }

    // Off the line, but give them a moment. A walker stepping round somebody
    // coming the other way is off the line for two seconds and back on it,
    // and re-registering against those steps would take their swerve for the
    // corridor's direction.
    if (_registration != null) {
      final since = _offRouteSince ??= DateTime.now();
      if (DateTime.now().difference(since) < _offRouteSettles) return;
    }

    final heading = frame.travelHeadingDeg! * math.pi / 180;
    final here = WorldPoint(frame.cameraX!, frame.cameraZ!);
    final path = _path!;

    // The correspondence, and which of two it is.
    //
    // **First registration.** The walker was at the start of the route when
    // they set off, and [_startWorld] is where ARCore had them then. The
    // direction is the one the route leaves in.
    //
    // **Re-registration.** They are mid-walk and the old transform is what
    // went wrong, so there is no setting-off moment to appeal to. What is
    // known instead is how far along they have come — which native measured
    // against the line, so it survives the rotation being wrong — and where
    // they are now. Anchoring the *start* here instead would slide the whole
    // route back under their feet and send them to walk it again.
    final WorldPoint worldAt;
    final Offset planAt;
    final Offset planDirection;
    if (_registration == null) {
      worldAt = _startWorld ?? here;
      planAt = path.pointsM.first;
      planDirection = _departureDirection(_planPath);
    } else {
      worldAt = here;
      planAt = path.pointAtM(frame.walkedM);
      planDirection = path.directionAtM(frame.walkedM);
    }

    final solved = Registration.solve(
      planAt: planAt,
      planDirection: planDirection,
      worldAt: worldAt,
      worldHeadingRad: heading,
      confidence: RegistrationConfidence.measured,
    );
    if (solved == null) {
      // A path with no direction in it cannot be registered, ever, and trying
      // again next frame would burn the solve on every frame of the walk.
      AppLogger.warn('Route has no departure direction — not registering');
      _cannotRegister = true;
      return;
    }

    _registration = solved;
    _offRouteSince = null;
    AppLogger.info('REGISTERED $solved from ${_planPath.length} points');

    final world = <double>[];
    for (final point in _planPath) {
      final w = solved.worldFromPlan(point);
      world..add(w.x)..add(w.z);
    }
    unawaited(_ar.setRoute(world));
    emit(state.copyWith(registered: true, distanceKnown: true));
  }

  /// Moves guidance on when the walker has measurably walked a leg.
  ///
  /// ## Why this exists, given that landmarks are supposed to do it
  ///
  /// They still do, and they are still better: a sign read off a door is
  /// evidence about *this building*, and a position is only ever evidence
  /// about ARCore's opinion of it. Nothing here changes what a confirmed
  /// landmark does.
  ///
  /// But a registered route measures the walk against the whole path, so the
  /// clock does not reset at a landmark the way a dead-reckoned leg's did. A
  /// walker who reaches the end of their first corridor and finds no readable
  /// sign — the ordinary case in most buildings — would carry on down the
  /// second one with guidance still counting the first, sail past every
  /// checkpoint cue at once, and then be stopped for a recovery sweep for the
  /// crime of having arrived. The alternative to advancing here is not
  /// "advance only on landmarks"; it is a walk that breaks at the first
  /// corner.
  ///
  /// ## What makes it safe enough to do
  ///
  /// Only against a line the walker is demonstrably following. If the
  /// registration is suspect — they are metres off the corridor it claims they
  /// are in — then position is exactly the evidence that cannot be trusted,
  /// and this stands down and leaves it to the sign.
  void _advancePastFinishedLegs(ArGuidanceFrame frame) {
    final path = _path;
    if (path == null || !frame.hasRoute) return;
    if (state.registrationSuspect) return;

    final index = _guidance.state.legIndex;
    if (index >= path.legEndsM.length) return;
    if (frame.walkedM < path.legEndsM[index] - _arrivedWithinM) return;
    if (_advancedLeg == index) return;

    _advancedLeg = index;
    AppLogger.info(
      'ADVANCE by position: leg $index ends at '
      '${path.legEndsM[index].toStringAsFixed(1)}m, walked '
      '${frame.walkedM.toStringAsFixed(1)}m',
    );
    _guidance.add(const GuidanceLandmarkConfirmed());
  }

  /// The leg most recently advanced past, so one boundary fires once.
  int? _advancedLeg;

  /// How near the end of a leg counts as having reached it.
  ///
  /// A door is a metre wide and the plan's idea of where it is was traced off
  /// a photograph, so insisting on the exact figure would leave the walker
  /// standing in the doorway being told to keep going.
  static const double _arrivedWithinM = 1.5;

  /// Distance into the *current leg*, whichever way the walk is being measured.
  ///
  /// The two descriptions of the same walk measure from different places. A
  /// dead-reckoned leg is anchored where the leg began, so its number already
  /// is what guidance wants. A registered route is measured from the start of
  /// the whole path, because that is the only origin native has — so the leg's
  /// share has to be taken out of it here.
  ///
  /// Getting this wrong is not subtle: guidance would hear a walker four
  /// metres into their second corridor as being forty metres into their first,
  /// sail past every checkpoint cue at once and then call an overshoot.
  double _legDistanceFrom(ArGuidanceFrame frame) {
    final path = _path;
    if (!frame.hasRoute || path == null) return frame.walkedM;

    // Which leg, taken from the position rather than from the bloc's current
    // index. The advance this frame may have triggered is still queued behind
    // this event, so the bloc still believes it is on the previous leg — and
    // subtracting that leg's start would report the walker as having walked
    // the whole path into a corridor they have just left.
    //
    // The bloc's own index wins where it is *ahead*, which is a landmark the
    // camera read before the walker got to where the plan puts it. That is
    // better evidence than a position, and it is the one direction the two can
    // legitimately disagree in.
    var index = _legIndexAtM(path, frame.walkedM);
    final claimed = _guidance.state.legIndex;
    if (claimed > index) index = claimed;

    if (index >= path.legEndsM.length) return frame.walkedM;
    return (frame.walkedM - path.startOfLeg(index)).clamp(0.0, double.infinity);
  }

  /// Which leg of the route a distance along the path falls in.
  static int _legIndexAtM(RoutePath path, double alongM) {
    for (var i = 0; i < path.legEndsM.length; i++) {
      if (alongM < path.legEndsM[i] - _arrivedWithinM) return i;
    }
    return path.legEndsM.length - 1;
  }

  /// The direction the route leaves its start in.
  ///
  /// Measured over the first [_departureM] of the path rather than between its
  /// first two vertices: those are typically a step apart inside the room the
  /// walker is leaving, and a rotation solved from a one-metre baseline
  /// carries the noise in that metre across the whole building. Falls back to
  /// the whole path when it is shorter than that.
  static Offset _departureDirection(List<Offset> path) {
    final start = path.first;
    var travelled = 0.0;
    for (var i = 1; i < path.length; i++) {
      travelled += (path[i] - path[i - 1]).distance;
      if (travelled >= _departureM) return path[i] - start;
    }
    return path.last - start;
  }

  /// How much of the route's start the departure direction is measured over.
  static const double _departureM = 3;

  /// How far off the line the walker may be before the registration is
  /// re-solved. Wider than a corridor is deliberate: this is the threshold for
  /// deciding the *app* is wrong, not the walker.
  static const double _registrationHoldsM = 2.5;

  /// How long they have to stay off the line before that is believed.
  static const Duration _offRouteSettles = Duration(seconds: 4);

  DateTime? _offRouteSince;

  void _onGuidance(GuidanceState guidance) {
    if (!state.running) return;
    _anchorFor(guidance);
  }

  /// Decides what the arrows should be showing for [guidance], and says so once.
  void _anchorFor(GuidanceState guidance) {
    final leg = guidance.currentLeg;

    // The geometry, taken the first time a session appears. It belongs to the
    // walk rather than to the leg, so it is read once and not re-read: legs
    // change several times a walk and the path does not change at all.
    final session = guidance.session;
    if (session != null && _path == null && !_cannotRegister) {
      final path = session.routePath;
      if (path == null || path.pointsM.length < 2) {
        // No geometry behind this walk — a recorded-walk route, or a traced
        // plan nobody measured. The leg arrows are the only thing those have,
        // and they are what this screen did before any of this existed.
        _cannotRegister = true;
        AppLogger.info('No route geometry — AR falls back to leg arrows');
      } else {
        _path = path;
        emit(state.copyWith(expectsRoute: true));
        AppLogger.info(
          'Route geometry: ${path.pointsM.length} points, '
          '${path.totalM.toStringAsFixed(1)}m, '
          '${path.legEndsM.length} legs',
        );
      }
    }

    // Arrived, or lost. Recovery is the important one: a sweep to find a sign
    // is exactly when the last leg's direction is least trustworthy, and arrows
    // left on screen tell somebody to keep walking a route they have left.
    if (leg == null ||
        guidance.status != GuidanceStatus.guiding ||
        guidance.session == null) {
      if (_anchoredLeg != null || state.registered) {
        _anchoredLeg = null;
        _registration = null;
        unawaited(_ar.clearLeg());
        unawaited(_ar.clearRoute());
        // Said here rather than waited for on the next heartbeat: half a second
        // of "3 m" under an arrow that has already gone is half a second of the
        // screen contradicting itself.
        emit(
          state.copyWith(
            hasLeg: false,
            hasRoute: false,
            registered: false,
            remainingM: 0,
            overshootM: 0,
          ),
        );
      }
      return;
    }

    // A registered route already covers every leg of the walk — it is the
    // whole path, not the current corridor — so a leg change needs nothing
    // drawn for it. Anchoring one anyway would put a dead-reckoned line back
    // over a measured one at every landmark.
    if (state.registered) {
      _anchoredLeg = guidance.legIndex;
      return;
    }

    if (_anchoredLeg == guidance.legIndex) return;
    _anchoredLeg = guidance.legIndex;

    // A route planned over a photo-traced plan has distances in the fractions
    // of an image nobody measured, so its "metres" are not metres. The
    // *direction* still is — a turn of ninety degrees is ninety degrees at any
    // scale — so such a leg is laid along a nominal length and the screen is
    // told not to quote a countdown it cannot stand behind.
    //
    // Until guidance has learned the scale from a leg already walked, that is.
    // From then on the length is as real as a recorded one, and the ring lands
    // where the landmark actually is rather than ten metres along.
    final metric = guidance.session!.metric;
    final learned = guidance.learnedScale;
    final metres = metric
        ? leg.distanceM
        : (learned == null ? nominalLegMetres : leg.distanceM * learned);
    unawaited(_ar.setLeg(turnDeg: leg.turnDeg, distanceM: metres));
    emit(state.copyWith(distanceKnown: metric || learned != null));
  }

  /// Length used for a leg whose distance is not in metres.
  ///
  /// A corridor's worth: long enough that the arrows lead somewhere, short
  /// enough that the destination beacon does not land through a wall in a small
  /// building.
  static const double nominalLegMetres = 10;

  @override
  Future<void> close() async {
    await _guidanceSubscription?.cancel();
    await _states?.cancel();
    _states = null;
    // Unconditional, and not routed through [stop]: a session started but not
    // yet finished starting still has to be closed, and by here there is no
    // state left to emit into.
    _stopRequested = true;
    await _ar.stop();
    return super.close();
  }
}
