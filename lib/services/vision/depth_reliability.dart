import 'depth_frame.dart';

/// Why camera depth cannot be trusted for this frame.
///
/// [DepthDoubt.none] means it can. Everything else is a reason to ask the
/// acoustic fallback instead — the situations the project documentation names
/// as "low light or featureless surfaces", expressed as the signals ARCore
/// actually gives us.
enum DepthDoubt {
  /// Depth is usable.
  none,

  /// ARCore has lost the pose. Depth values may still arrive, but there is no
  /// reliable place to put them.
  notTracking,

  /// Tracking, but no depth yet. ARCore derives depth from motion parallax,
  /// so this is normal for the first frames and persistent in a scene with
  /// nothing to parallax against.
  noDepth,

  /// Depth returned, but for too little of the frame. This is what a bare
  /// wall, a window, or a dim corridor looks like: the frame arrives, and
  /// almost every cell comes back empty.
  sparseCoverage,

  /// Depth returned with reasonable coverage, but not for the centre — the
  /// one direction "how far is the thing in front of me" is asking about.
  noCenterDepth,
}

/// Decides when camera depth should defer to sound.
///
/// Deliberately a separate, pure predicate rather than a condition written
/// inline wherever a frame is handled. It is the trigger for the whole
/// acoustic fallback, it is the thing an evaluation has to report a threshold
/// for, and if it lived in a widget it would end up duplicated in each screen
/// that scans — three copies that drift apart and cannot be tested.
class DepthReliability {
  const DepthReliability({this.minimumCoverage = 0.25});

  /// Least fraction of grid cells that must carry a depth before the frame is
  /// believed.
  ///
  /// A starting point, not a measured constant — hence a parameter. The floor
  /// is what a frame aimed at a plain painted wall or a window returns
  /// (`validSamples` near zero, per [DepthFrame.validSamples]); the ceiling is
  /// that a normally furnished room in good light fills most of the grid.
  /// M10's evaluation should re-fit this against frames captured in the rooms
  /// actually tested, in the same way the room classifier's thresholds are.
  final double minimumCoverage;

  /// Assesses [frame]. A null frame — none has arrived yet — counts as
  /// [DepthDoubt.noDepth] rather than as usable depth: the fallback should
  /// fire while the camera is still converging, not wait for it.
  DepthDoubt assess(DepthFrame? frame) {
    if (frame == null) return DepthDoubt.noDepth;
    if (frame.trackingState != DepthTrackingState.tracking) {
      return DepthDoubt.notTracking;
    }
    if (!frame.hasDepth) return DepthDoubt.noDepth;

    final cells = frame.gridColumns * frame.gridRows;
    if (cells <= 0) return DepthDoubt.noDepth;
    if (frame.validSamples / cells < minimumCoverage) {
      return DepthDoubt.sparseCoverage;
    }

    // Coverage can be fine while the centre specifically is empty — a doorway
    // straight ahead with walls either side reads exactly like this, and it
    // is the case a navigating user most needs answered.
    if (frame.centerMeters == null) return DepthDoubt.noCenterDepth;

    return DepthDoubt.none;
  }

  /// Whether [frame] warrants an acoustic range.
  bool shouldFallBack(DepthFrame? frame) => assess(frame) != DepthDoubt.none;
}
