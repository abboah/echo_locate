import 'dart:typed_data';

/// One camera frame, ready for ML Kit, from somewhere other than the camera
/// plugin.
///
/// **Why this type exists.** ARCore holds the camera exclusively. On a screen
/// running an AR session, `CameraController` cannot be opened at all — so
/// obstacle detection and sign reading, which are the two things that make
/// guidance work for a blind user, would simply stop the moment the AR view
/// came up. Native pulls the CPU image off the ARCore session instead and sends
/// it here, and [DetectionService] feeds it to exactly the same analysers.
///
/// The bytes are NV21, which is what the camera plugin already hands over on
/// Android, so nothing downstream can tell the two sources apart.
class AnalysisFrame {
  const AnalysisFrame({
    required this.bytes,
    required this.width,
    required this.height,
    required this.rotationDegrees,
  });

  /// NV21: a full-resolution luminance plane, then interleaved V and U.
  final Uint8List bytes;

  final int width;
  final int height;

  /// Clockwise degrees to rotate the image to make it upright: 0, 90, 180, 270.
  ///
  /// Computed natively from the sensor's mounting and the current display
  /// rotation, because those are two things only the platform knows and getting
  /// them wrong means OCR reading a door plate sideways — which fails silently,
  /// as no text at all.
  final int rotationDegrees;

  /// The frame's size once [rotationDegrees] has been applied, which is the
  /// space ML Kit reports bounding boxes in.
  bool get isSideways => rotationDegrees == 90 || rotationDegrees == 270;

  int get uprightWidth => isSideways ? height : width;

  int get uprightHeight => isSideways ? width : height;
}

/// Something that can supply camera frames without owning the camera plugin.
///
/// Implemented by the AR guidance session. [DetectionService] takes one
/// optionally and prefers it over opening its own camera whenever it is
/// streaming — which is the whole handover, in one condition.
abstract class AnalysisFrameSource {
  /// Whether frames are actually flowing right now. False when no AR session
  /// is up, which is the normal case on the uncertified hardware most of this
  /// app's users carry.
  bool get isStreaming;

  /// Whether a session has the camera, whether or not it is sending frames yet.
  ///
  /// The two are not the same for a few hundred milliseconds at startup, and
  /// that gap is a trap: a [DetectionService] that sees "not streaming" and
  /// opens `CameraController` will fail — the camera is taken — and then run
  /// the whole screen in demo mode with no obstacle detection and no sign
  /// reading, silently, for the rest of the route. Waiting for frames that are
  /// coming is always the better bet than fighting for a camera that is gone.
  bool get holdsCamera;

  Stream<AnalysisFrame> get analysisFrames;

  /// Says that the last frame has been analysed and another is wanted.
  ///
  /// **This is what sets the frame rate.** The source hands over one frame at a
  /// time and waits for this before copying the next, so the rate lands
  /// wherever the hardware puts it instead of on a number guessed in advance —
  /// a guess that is either wasteful, or slow at reading the door sign that
  /// tells a blind user they have arrived.
  ///
  /// Not calling it stalls the feed until the source's own timeout, so call it
  /// exactly once per frame that was actually analysed.
  void frameHandled();
}
