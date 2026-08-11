part of 'guidance_bloc.dart';

/// preparing → guiding ⇄ recovering → arrived.
enum GuidanceStatus {
  /// Bringing up camera, sign reading and step counting.
  preparing,

  /// Walking a leg.
  guiding,

  /// Lost: sweeping for any landmark in the building rather than the expected
  /// one. Guidance still speaks obstacles.
  recovering,

  /// Destination reached.
  arrived,
}

final class GuidanceState extends Equatable {
  const GuidanceState({
    this.status = GuidanceStatus.preparing,
    this.session,
    this.legIndex = 0,
    this.stepsThisLeg = 0,
    this.stepCounting = false,
    this.signReading = false,
    this.instruction = '',
    this.lastLandmarkName,
    this.callout,
    this.askForHelp = false,
    this.voiceOn = true,
  });

  final GuidanceStatus status;
  final GuidanceSession? session;

  /// Which leg of [plan] is being walked.
  final int legIndex;

  /// Steps since the last confirmed landmark. Zero when [stepCounting] is
  /// false — never a guess.
  final int stepsThisLeg;

  /// Rung 1 of the fallback ladder: the hardware counter is working.
  final bool stepCounting;

  /// Whether the camera is up and OCR is running. False on a phone with no
  /// camera permission, where landmarks are confirmed by hand instead.
  final bool signReading;

  /// What the user was last told to do. Shown on screen for a sighted helper.
  final String instruction;

  /// The last landmark confirmed, for the "you are here" line.
  final String? lastLandmarkName;

  /// Most recent obstacle callout, or null when the way is clear.
  final AssistCallout? callout;

  /// Rung 4: the phone has run out of ways to locate the user and has said so.
  final bool askForHelp;

  final bool voiceOn;

  PlannedRoute get plan => session?.plan ?? const PlannedRoute(legs: []);

  PlannedLeg? get currentLeg =>
      legIndex < plan.legs.length ? plan.legs[legIndex] : null;

  /// Whether the current leg can be measured in steps at all.
  ///
  /// A pedometer counts footfalls on the flat; it does not measure climbing,
  /// so a leg ending at stairs or a lift is guided by its sign alone. Counting
  /// one anyway would announce a landmark the user has not reached and then
  /// declare them lost for taking too long over a staircase.
  bool get countsThisLeg {
    final leg = currentLeg;
    if (!stepCounting || leg == null) return false;
    // A route over a plan nobody measured has lengths in arbitrary units. They
    // route correctly — A* only compares them with each other — but converting
    // one into "about twenty steps" would put a confidently wrong number in a
    // blind user's ear. Landmark confirmation carries the leg instead.
    if (!(session?.metric ?? true)) return false;
    final destination = session?.landmarkOf(leg.toLandmarkId);
    return !(destination?.kind.breaksStepCounting ?? false);
  }

  /// How many steps this user should need for the current leg. Zero when the
  /// leg cannot be counted (no counter, or stairs).
  int get expectedSteps {
    final leg = currentLeg;
    final session = this.session;
    if (leg == null || session == null || !countsThisLeg) return 0;
    return session.stride.stepsFor(leg.distanceM);
  }

  /// 0–1 along the current leg, clamped. 0 when there is nothing to count.
  double get legProgress {
    final expected = expectedSteps;
    if (expected <= 0) return 0;
    final ratio = stepsThisLeg / expected;
    return ratio > 1 ? 1 : ratio;
  }

  /// Legs completed out of the whole route — the progress bar on screen.
  double get routeProgress =>
      plan.legs.isEmpty ? 0 : legIndex / plan.legs.length;

  GuidanceState copyWith({
    GuidanceStatus? status,
    GuidanceSession? session,
    int? legIndex,
    int? stepsThisLeg,
    bool? stepCounting,
    bool? signReading,
    String? instruction,
    String? lastLandmarkName,
    AssistCallout? callout,
    bool? askForHelp,
    bool? voiceOn,
  }) =>
      GuidanceState(
        status: status ?? this.status,
        session: session ?? this.session,
        legIndex: legIndex ?? this.legIndex,
        stepsThisLeg: stepsThisLeg ?? this.stepsThisLeg,
        stepCounting: stepCounting ?? this.stepCounting,
        signReading: signReading ?? this.signReading,
        instruction: instruction ?? this.instruction,
        lastLandmarkName: lastLandmarkName ?? this.lastLandmarkName,
        callout: callout ?? this.callout,
        askForHelp: askForHelp ?? this.askForHelp,
        voiceOn: voiceOn ?? this.voiceOn,
      );

  @override
  List<Object?> get props => [
        status,
        session,
        legIndex,
        stepsThisLeg,
        stepCounting,
        signReading,
        instruction,
        lastLandmarkName,
        callout,
        askForHelp,
        voiceOn,
      ];
}
