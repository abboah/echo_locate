part of 'ar_guidance_cubit.dart';

/// What the AR layer of the guidance screen is showing.
///
/// Everything here is decoration over a route that works without it, so every
/// field has a sane value for "no AR at all" — which is the state on most of
/// the phones this app is for.
final class ArGuidanceState extends Equatable {
  const ArGuidanceState({
    this.availability = ArCoreAvailability.unknown,
    this.running = false,
    this.cameraVisible = true,
    this.textureId,
    this.tracking = CaptureTrackingLike.stopped,
    this.issue = ArGuidanceIssue.none,
    this.hasLeg = false,
    this.headingReady = false,
    this.anchoredFromCamera = false,
    this.distanceKnown = true,
    this.remainingM = 0,
    this.overshootM = 0,
    this.bearingDeg = 0,
    this.registered = false,
    this.expectsRoute = false,
    this.hasRoute = false,
    this.offRouteM = 0,
    this.error,
  });

  final ArCoreAvailability availability;
  final bool running;

  /// Whether the camera and its arrow are on screen, as opposed to the plain
  /// high-contrast view. The session runs in both.
  final bool cameraVisible;

  final int? textureId;
  final CaptureTrackingLike tracking;
  final ArGuidanceIssue issue;

  /// Whether a leg is anchored and an arrow is being drawn for it.
  final bool hasLeg;

  final bool headingReady;
  final bool anchoredFromCamera;

  /// False on a route whose leg lengths are not really metres, in which case
  /// the countdown is hidden rather than made up.
  final bool distanceKnown;

  final double remainingM;

  /// How far past the end of the leg the walker has walked.
  final double overshootM;

  final double bearingDeg;

  /// Whether the floor plan has been located in the room.
  ///
  /// The dividing line between the two things this screen can be doing. False,
  /// and the arrow is dead reckoning: it knows the walker's route as a chain
  /// of turns and lengths but not where any of it *is*, so it can only say
  /// "keep going the way you set off". True, and the whole route has been laid
  /// into ARCore's world, and the arrow is pointing at the actual next corner.
  ///
  /// It goes true a few steps into a walk, because solving for it needs a
  /// measured direction of travel — see `ArGuidanceCubit._tryRegister`.
  final bool registered;

  /// Whether this walk has geometry to register at all.
  ///
  /// The difference between "the arrow is about to start following the plan"
  /// and "it never will on this route" — a distinction the walker cannot make
  /// by looking at an arrow, and which decides whether waiting is worth
  /// anything. False for a route stitched from recorded walks, and for a
  /// traced plan whose scale nobody has set.
  final bool expectsRoute;

  /// Whether native is drawing that registered route, as opposed to a leg.
  ///
  /// Distinct from [registered] only in the moment between Dart solving the
  /// transform and native servicing the call on its next frame.
  final bool hasRoute;

  /// How far the walker is standing from the registered line, in metres.
  ///
  /// The one number that says whether the registration is any good. See
  /// [ArGuidanceFrame.offRouteM].
  final double offRouteM;

  /// Whether the route on screen should be believed.
  ///
  /// A walker who has drifted this far from a corridor the app registered is
  /// either lost or being lied to, and the screen cannot tell which — so it
  /// stops claiming to know and says so, rather than steering with confidence
  /// it has not earned.
  bool get registrationSuspect => hasRoute && offRouteM > _lostTheLineM;

  static const double _lostTheLineM = 5;

  final String? error;

  /// How far past a landmark counts as having missed it.
  ///
  /// Generous on purpose. Leg lengths come from whoever recorded the route, so
  /// being a couple of metres over is normal and saying so every time would
  /// train the walker to ignore the line that matters.
  static const double overshootThresholdM = 4;

  /// Whether the walker has gone far enough past the landmark to be told.
  bool get hasOvershot =>
      hasLeg && distanceKnown && isTracking && overshootM >= overshootThresholdM;

  bool get isSupported => availability == ArCoreAvailability.supported;

  bool get isTracking => tracking == CaptureTrackingLike.tracking;

  /// Whether the phone is pointing near enough along the route to be walking
  /// it, rather than turned away down some other corridor.
  bool get facingRoute => bearingDeg.abs() < 28;

  /// Which way the route lies when it is not where the phone is pointing. Null
  /// while it is straight ahead, or while there is nothing to point at.
  ///
  /// The arrow itself never needs this — it is drawn natively and swings to
  /// whatever bearing it is given, so it is on screen at every angle. This is
  /// for the line of text under the instruction, which is the only version of
  /// it a screen reader ever hears.
  ArTurnHint? get turnHint {
    if (!hasLeg || !isTracking || facingRoute) return null;
    if (bearingDeg.abs() > 140) return ArTurnHint.around;
    return bearingDeg > 0 ? ArTurnHint.right : ArTurnHint.left;
  }

  /// The line under the instruction — what the AR layer wants to say, or null
  /// when it has nothing to add.
  ///
  /// Ordered by what blocks the walker: no direction at all beats a lost
  /// position, which beats a distance.
  String? get hint {
    if (!running) return null;
    if (anchoredFromCamera && !headingReady) {
      // The one case the arrow can be confidently wrong: anchored off the
      // phone's bearing because nobody had walked yet.
      return 'Walk a few steps so the arrow can line up.';
    }
    if (!isTracking) {
      return issue == ArGuidanceIssue.none
          ? 'Finding your place — keep walking.'
          : issue.advice;
    }
    if (expectsRoute && !registered) {
      // There is a plan to follow and the arrow is not following it yet: the
      // transform needs a measured direction of travel, and standing still
      // produces none. Said explicitly because the two states look identical —
      // an arrow pointing somewhere — and only one of them is worth waiting
      // out.
      return 'Walk a few steps so the arrow can line up with the plan.';
    }
    if (registrationSuspect) {
      // The route says one thing and the building says another. Which of them
      // is wrong cannot be known from here, so the screen stops asserting and
      // hands the walker the thing that is true either way: the sign on the
      // door is what confirms where they are.
      return 'This may not be the right corridor — look for a sign.';
    }
    if (hasOvershot) {
      // Said plainly rather than urgently: the leg length is an estimate, so
      // this is "check", not "you are lost". The route itself is untouched —
      // confirming the landmark still works from wherever they are standing.
      return 'You may have passed it — look around for the sign.';
    }
    // Where the way is, rather than "turn left to see the arrows": the arrow
    // is already visible and already pointing there, so an instruction to go
    // looking for it would be describing a screen that no longer exists.
    return switch (turnHint) {
      ArTurnHint.left => 'The way is to your left.',
      ArTurnHint.right => 'The way is to your right.',
      ArTurnHint.around => 'The way is behind you.',
      null => null,
    };
  }

  /// Distance left on this leg, when it is a distance worth quoting.
  String? get remainingLabel {
    if (!hasLeg || !distanceKnown || !isTracking) return null;
    // "Almost there" next to "you may have passed it" is the screen arguing
    // with itself. Past the end, the hint is the honest half.
    if (hasOvershot) return null;
    if (remainingM < 1.5) return 'Almost there';
    return '${remainingM.round()} m';
  }

  /// The same countdown as a screen reader should say it.
  ///
  /// "7 m" is read out as "seven m", which is not a word. Anything under a
  /// metre and a half is already phrased, and the shortest number this can
  /// quote is two, so the plural is always right.
  String? get remainingSpoken {
    final label = remainingLabel;
    if (label == null || label == 'Almost there') return label;
    return '${remainingM.round()} metres to go';
  }

  ArGuidanceState copyWith({
    ArCoreAvailability? availability,
    bool? running,
    bool? cameraVisible,
    int? textureId,
    bool clearTexture = false,
    CaptureTrackingLike? tracking,
    ArGuidanceIssue? issue,
    bool? hasLeg,
    bool? headingReady,
    bool? anchoredFromCamera,
    bool? distanceKnown,
    double? remainingM,
    double? overshootM,
    double? bearingDeg,
    bool? registered,
    bool? expectsRoute,
    bool? hasRoute,
    double? offRouteM,
    String? error,
    bool clearError = false,
  }) => ArGuidanceState(
    availability: availability ?? this.availability,
    running: running ?? this.running,
    cameraVisible: cameraVisible ?? this.cameraVisible,
    // Cleared explicitly, never by passing null: a texture id that outlives its
    // session renders a `Texture` widget over an id the platform has released,
    // which is a blank rectangle with no crash and nothing in the log.
    textureId: clearTexture ? null : (textureId ?? this.textureId),
    tracking: tracking ?? this.tracking,
    issue: issue ?? this.issue,
    hasLeg: hasLeg ?? this.hasLeg,
    headingReady: headingReady ?? this.headingReady,
    anchoredFromCamera: anchoredFromCamera ?? this.anchoredFromCamera,
    distanceKnown: distanceKnown ?? this.distanceKnown,
    remainingM: remainingM ?? this.remainingM,
    overshootM: overshootM ?? this.overshootM,
    bearingDeg: bearingDeg ?? this.bearingDeg,
    registered: registered ?? this.registered,
    expectsRoute: expectsRoute ?? this.expectsRoute,
    hasRoute: hasRoute ?? this.hasRoute,
    offRouteM: offRouteM ?? this.offRouteM,
    // A failure to start that has since succeeded is not still true. Left in
    // place it would sit on the screen for the rest of the walk.
    error: clearError ? null : (error ?? this.error),
  );

  @override
  List<Object?> get props => [
    availability,
    running,
    cameraVisible,
    textureId,
    tracking,
    issue,
    hasLeg,
    headingReady,
    anchoredFromCamera,
    distanceKnown,
    remainingM,
    overshootM,
    bearingDeg,
    registered,
    expectsRoute,
    hasRoute,
    offRouteM,
    error,
  ];
}

/// Which way the route lies when it is not straight ahead.
enum ArTurnHint { left, right, around }
