/// Which of the two ML Kit analysers a given camera frame goes to.
///
/// Both cannot run on every frame: on the budget hardware this app targets
/// that halves the rate of each, and the feed is already paced one frame at a
/// time by whichever analyser is slower. So the frames are handed out, and
/// this is the thing that hands them out.
enum Analyser {
  /// Obstacle detection — the thing that stops a blind walker hitting a
  /// trolley. Never allowed to reach zero frames.
  objects,

  /// Sign reading. The app's positioning system: a door plate read at the end
  /// of a leg is what advances the walk without asking the walker anything.
  text,
}

/// How the camera frames are divided between obstacle detection and sign
/// reading.
///
/// ## Why this is not a fixed alternation
///
/// It used to be `_frameIndex.isOdd` — a flat fifty-fifty, whatever the walk
/// was doing. That is the right split for most of a corridor and the wrong one
/// at the end of it. A leg advances when the sign at its end is read
/// (`GuidanceBloc._onSignsRead`); if it is not read, the walker is asked to
/// confirm the landmark by hand — which is a question somebody who does not
/// know the building cannot answer. Every missed read is a manual
/// confirmation, and the last few metres are the only place the read can
/// happen at all.
///
/// So signage gets two frames in three once the walker is inside
/// [approachM] of the landmark, and the split goes back to even afterwards.
///
/// ## Why obstacles are not switched off instead
///
/// They are what the accessibility case rests on, so the arriving split is
/// two-in-three rather than all: obstacle detection keeps a frame in every
/// cycle, everywhere, always. At the feed's usual rate that is the difference
/// between a callout roughly twice a second and one roughly every two thirds
/// of a second — and the walker is slowing to look for a sign at that point,
/// which is the moment they are least likely to walk into something at speed.
class AnalyserSchedule {
  const AnalyserSchedule._();

  /// How near the end of a leg counts as arriving.
  ///
  /// **Must match `GuidanceBloc._approachM`.** That is where the spoken cue
  /// changes from counting down to naming what to look for, so it is also the
  /// point from which the sign is the thing worth spending frames on.
  static const double approachM = 4;

  /// Frames per cycle while arriving, of which one goes to obstacles.
  static const int _arrivingCycle = 3;

  /// Which analyser frame [index] belongs to.
  ///
  /// [remainingM] is how far the walker has left on the current leg, or null
  /// when nothing is measuring it — no AR session and no step count, which is
  /// the case this app is built to survive. A null is treated as mid-corridor:
  /// with no idea how close the landmark is there is no reason to favour
  /// either analyser, and starving obstacle detection on a guess is the one
  /// mistake here with a physical consequence.
  static Analyser analyserFor({required int index, double? remainingM}) {
    final arriving = remainingM != null && remainingM <= approachM;
    if (!arriving) {
      return index.isOdd ? Analyser.text : Analyser.objects;
    }
    return index % _arrivingCycle == 0 ? Analyser.objects : Analyser.text;
  }
}
