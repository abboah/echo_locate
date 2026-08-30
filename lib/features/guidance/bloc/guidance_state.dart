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
    this.walkedM = 0,
    this.learnedScale,
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

  /// Metres per plan unit, learned from legs already walked.
  ///
  /// Only ever set on a route whose own lengths are not metres. A traced plan's
  /// units are arbitrary but *consistent* — a leg twice as long on the plan is
  /// twice as long in the building — so one leg walked with ARCore measuring it
  /// gives the scale for all the rest. The route starts out unable to say
  /// anything about distance and teaches itself partway down the first
  /// corridor.
  final double? learnedScale;

  /// Metres walked on this leg, from whichever clock is running: ARCore's
  /// odometry when the AR view is up, the step count converted by the user's
  /// stride otherwise. Zero when nothing can measure this leg.
  ///
  /// This is what paces the walk. The leg is spoken and drawn in checkpoints
  /// off this one number, so what the walker hears and what they see cannot
  /// drift apart — which they would if each had its own idea of how far along
  /// the corridor they were.
  final double walkedM;

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

  /// Whether this leg is a distance walked along a floor at all.
  ///
  /// False into stairs and lifts: climbing is not something a pedometer or a
  /// countdown measures, and a leg that ends at the top of a staircase is
  /// guided by the sign there.
  bool get legWalkable {
    final leg = currentLeg;
    final session = this.session;
    if (leg == null || session == null) return false;
    return !(session.landmarkOf(leg.toLandmarkId)?.kind.breaksStepCounting ??
        false);
  }

  /// Whether this leg's *length* is known in metres.
  ///
  /// A route planned over a photo-traced plan has lengths in fractions of an
  /// image nobody measured. They route correctly — A* only compares them with
  /// each other — but "six metres to go" from one would be a confidently wrong
  /// number in a blind user's ear. Such a route becomes measurable partway
  /// through, once [learnedScale] has been worked out from a leg already
  /// walked, and not before.
  bool get legMeasurable => legWalkable && legMetres > 0;

  /// How long the current leg is in real metres. Zero when nothing knows.
  double get legMetres {
    final leg = currentLeg;
    final session = this.session;
    if (leg == null || session == null || !legWalkable) return 0;
    if (session.metric) return leg.distanceM;
    final scale = learnedScale;
    return scale == null ? 0 : leg.distanceM * scale;
  }

  /// Whether this leg's length is an estimate rather than something recorded.
  ///
  /// Everything spoken is allowed to rest on an estimate; **nothing that
  /// interrupts the walker is.** An estimated length is wrong by however wrong
  /// the first leg's measurement was, and a recovery sweep triggered by that
  /// stops somebody who was walking along perfectly well.
  bool get legMetresEstimated =>
      legMetres > 0 && !(session?.metric ?? true);

  /// Whether the current leg can be measured in steps at all.
  ///
  /// A pedometer counts footfalls on the flat; it does not measure climbing,
  /// so a leg ending at stairs or a lift is guided by its sign alone. Counting
  /// one anyway would announce a landmark the user has not reached and then
  /// declare them lost for taking too long over a staircase.
  bool get countsThisLeg => stepCounting && legMeasurable;

  /// How many steps this user should need for the current leg. Zero when the
  /// leg cannot be counted (no counter, or stairs).
  int get expectedSteps {
    final leg = currentLeg;
    final session = this.session;
    if (leg == null || session == null || !countsThisLeg) return 0;
    // [legMetres], not the leg's own number: on a route whose lengths are not
    // metres that number is a fraction of an image, and running it through a
    // stride length would announce "about one step" for a corridor.
    return session.stride.stepsFor(legMetres);
  }

  /// 0–1 along the current leg, clamped. 0 when there is nothing to measure.
  double get legProgress {
    // [walkedM] covers both clocks — it is where the step count has been put
    // once converted, as well as where ARCore's odometry lands — so this reads
    // the same whichever of them is running.
    final total = legMetres;
    if (total > 0 && walkedM > 0) {
      final metres = walkedM / total;
      return metres > 1 ? 1 : metres;
    }
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
    double? walkedM,
    double? learnedScale,
    bool? stepCounting,
    bool? signReading,
    String? instruction,
    String? lastLandmarkName,
    AssistCallout? callout,
    bool? askForHelp,
    bool? voiceOn,
  }) => GuidanceState(
    status: status ?? this.status,
    session: session ?? this.session,
    legIndex: legIndex ?? this.legIndex,
    stepsThisLeg: stepsThisLeg ?? this.stepsThisLeg,
    walkedM: walkedM ?? this.walkedM,
    learnedScale: learnedScale ?? this.learnedScale,
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
    walkedM,
    learnedScale,
    stepCounting,
    signReading,
    instruction,
    lastLandmarkName,
    callout,
    askForHelp,
    voiceOn,
  ];
}
