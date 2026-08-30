import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../../core/utils/logger.dart';
import '../sensing/analysis_frame.dart';
import 'depth_frame.dart' show ArCoreAvailability;

/// How the AR guidance session is doing, and what the screen should draw.
///
/// Arrives on change and on a slow heartbeat, never per frame: the arrows are
/// drawn natively, in the same buffer as the camera image, so nothing on this
/// stream is on the hot path. What crosses is the handful of numbers the
/// *Flutter* overlay needs — how far is left, and whether the walker is even
/// pointing the right way.
class ArGuidanceFrame {
  const ArGuidanceFrame({
    required this.tracking,
    required this.issue,
    this.hasLeg = false,
    this.headingReady = false,
    this.anchoredFromCamera = false,
    this.sessionEnded = false,
    this.walkedM = 0,
    this.remainingM = 0,
    this.overshootM = 0,
    this.bearingDeg = 0,
    this.hasRoute = false,
    this.offRouteM = 0,
    this.arrived = false,
    this.cameraX,
    this.cameraZ,
    this.travelHeadingDeg,
    this.registrationHeadingDeg,
    this.wallGridDeg,
  });

  final CaptureTrackingLike tracking;
  final ArGuidanceIssue issue;

  /// Whether a leg is anchored and arrows are being drawn.
  final bool hasLeg;

  /// Whether there has been enough recent walking to know which way is forward.
  final bool headingReady;

  /// Whether the leg on screen was anchored from where the phone was *pointing*
  /// rather than from how the walker was moving.
  ///
  /// True at the start of a route, standing still. It is the one case where the
  /// arrows can be confidently wrong, so the screen says "walk a few steps"
  /// instead of pretending otherwise.
  final bool anchoredFromCamera;

  /// The session stopped itself and there will be no more frames.
  ///
  /// Sent when the camera is taken away — another app, an incoming call — as
  /// opposed to when this side asked for the stop and has already stopped
  /// listening. Whoever is showing the texture has to let it go: it now points
  /// at nothing, which draws as a frozen picture rather than an error.
  final bool sessionEnded;

  final double walkedM;
  final double remainingM;

  /// How far past the end of the leg the walker has gone, in metres.
  ///
  /// Legs are as long as whoever recorded the route said they were, so this is
  /// routinely non-zero by a metre or two. It only becomes worth saying
  /// something about when it is large enough that the landmark was missed.
  final double overshootM;

  /// Where the destination is relative to where the phone points, in degrees;
  /// positive is to the right. This is what the arrow points along.
  final double bearingDeg;

  /// Whether a whole route has been registered into the room, as opposed to a
  /// single dead-reckoned leg.
  ///
  /// The difference the walker feels: a registered route knows where the
  /// corners are and can steer to them, and a leg can only say "keep going".
  final bool hasRoute;

  /// How far the walker is standing from the registered line, in metres.
  ///
  /// **The honesty check on the whole registration.** Everything else reports
  /// what the app believes; this reports whether the building agrees. Someone
  /// walking a corridor that was registered correctly stays within a metre or
  /// so of the line, and a registration that came out rotated shows up as this
  /// climbing steadily — which is the only thing that distinguishes it from a
  /// walker who has simply wandered off.
  final double offRouteM;

  /// Whether the walker has reached the end of the registered route.
  final bool arrived;

  /// Where ARCore has the phone, on the floor plane, in its own world frame.
  ///
  /// Null while tracking is lost. Published for one purpose: solving the
  /// transform between the floor plan and that world (`route_registration`).
  final double? cameraX;
  final double? cameraZ;

  /// Which way the walker is *moving*, in degrees clockwise from ARCore's
  /// forward, or null when they have not moved far enough recently to say.
  ///
  /// The other half of the registration. Not where the phone points — that
  /// swings wildly as somebody sweeps it looking for a sign — but the
  /// direction the last couple of metres of walking went in.
  final double? travelHeadingDeg;

  /// The same direction, measured over a much longer baseline, or null until
  /// the walker has covered it.
  ///
  /// **This is the one a registration is solved from, and the distinction is
  /// the whole accuracy of the AR layer.** [travelHeadingDeg] is released after
  /// 0.7 m so a leg can be anchored promptly and corrected a few metres later.
  /// A registration gets no such second chance — its yaw rotates the entire
  /// building and no landmark can take it back out — so it waits for metres of
  /// walking instead of centimetres.
  final double? registrationHeadingDeg;

  /// The building's rectilinear grid, folded to [0, 90), in degrees.
  ///
  /// Measured from the normals of vertical planes: an absolute direction that
  /// owes nothing to how the walker happened to set off. Null when too few
  /// walls have been fitted, or when the ones that were disagree — an
  /// out-of-square room, or a plane fitted to something that is not a wall.
  ///
  /// Folded, so it names the grid rather than a direction on it. Which of the
  /// four quarter-turns applies is resolved against the travel heading in
  /// `Registration.snappedToGrid`.
  final double? wallGridDeg;

  bool get isTracking => tracking == CaptureTrackingLike.tracking;

  /// Whether this frame carries what a registration needs to be solved.
  bool get canRegister =>
      isTracking &&
      cameraX != null &&
      cameraZ != null &&
      registrationHeadingDeg != null;

  static ArGuidanceFrame fromNative(Map<Object?, Object?> map) => ArGuidanceFrame(
    tracking: switch (map['trackingState'] as String?) {
      'TRACKING' => CaptureTrackingLike.tracking,
      'PAUSED' => CaptureTrackingLike.paused,
      _ => CaptureTrackingLike.stopped,
    },
    issue: ArGuidanceIssue.fromName(map['failureReason'] as String?),
    hasLeg: map['hasLeg'] as bool? ?? false,
    headingReady: map['headingReady'] as bool? ?? false,
    anchoredFromCamera: map['anchoredFromCamera'] as bool? ?? false,
    sessionEnded: map['ended'] as bool? ?? false,
    walkedM: (map['walkedM'] as num?)?.toDouble() ?? 0,
    remainingM: (map['remainingM'] as num?)?.toDouble() ?? 0,
    overshootM: (map['overshootM'] as num?)?.toDouble() ?? 0,
    bearingDeg: (map['bearingDeg'] as num?)?.toDouble() ?? 0,
    hasRoute: map['hasRoute'] as bool? ?? false,
    offRouteM: (map['offRouteM'] as num?)?.toDouble() ?? 0,
    arrived: map['arrived'] as bool? ?? false,
    // Left null rather than defaulted to zero: zero is a real position and a
    // real bearing, and a registration solved from a defaulted one would be
    // silently anchored at ARCore's origin facing its forward.
    cameraX: (map['camX'] as num?)?.toDouble(),
    cameraZ: (map['camZ'] as num?)?.toDouble(),
    travelHeadingDeg: (map['travelHeadingDeg'] as num?)?.toDouble(),
    registrationHeadingDeg:
        (map['registrationHeadingDeg'] as num?)?.toDouble(),
    wallGridDeg: (map['wallGridDeg'] as num?)?.toDouble(),
  );
}

/// Tracking state, named separately from the capture screen's so the two
/// features can diverge without one silently changing the other's meaning.
enum CaptureTrackingLike { tracking, paused, stopped }

/// Why tracking stopped, phrased as the thing the walker can change.
///
/// Deliberately the same advice as the capture screen's: a corridor that
/// defeats tracking defeats it the same way whichever screen is up, and a blind
/// user hearing this needs an instruction rather than a diagnosis.
enum ArGuidanceIssue {
  none,
  insufficientFeatures,
  excessiveMotion,
  insufficientLight,
  cameraUnavailable,
  relocalising,
  unknown;

  static ArGuidanceIssue fromName(String? value) => switch (value) {
    null || 'NONE' => ArGuidanceIssue.none,
    'INSUFFICIENT_FEATURES' => ArGuidanceIssue.insufficientFeatures,
    'EXCESSIVE_MOTION' => ArGuidanceIssue.excessiveMotion,
    'INSUFFICIENT_LIGHT' => ArGuidanceIssue.insufficientLight,
    // Another app took the camera, or the system did. Not something more
    // walking fixes, which is what every other reason here is.
    'CAMERA_UNAVAILABLE' => ArGuidanceIssue.cameraUnavailable,
    'BAD_STATE' => ArGuidanceIssue.unknown,
    _ => ArGuidanceIssue.relocalising,
  };

  String get advice => switch (this) {
    ArGuidanceIssue.none => '',
    ArGuidanceIssue.insufficientFeatures =>
      'Point the phone along the corridor, not at a blank wall.',
    ArGuidanceIssue.excessiveMotion => 'Hold the phone steadier as you walk.',
    ArGuidanceIssue.insufficientLight => 'It is too dark here to see the way.',
    ArGuidanceIssue.cameraUnavailable =>
      'The camera is busy elsewhere. Voice directions still work.',
    ArGuidanceIssue.relocalising => 'Finding your place again — keep walking.',
    ArGuidanceIssue.unknown => 'The arrows have stopped. Voice still works.',
  };
}

/// The AR half of guidance: an arrow on the floor pointing along the leg.
///
/// ## What it does not do
///
/// It does not locate the user in the building. There is no alignment to a
/// floor plan and none is wanted: guidance is a chain of legs between
/// landmarks, and this draws one leg at a time, anchored the moment a landmark
/// is confirmed. Every confirmation re-anchors from scratch, so heading error
/// never accumulates past one corridor — the same trick that keeps the step
/// counter honest, applied to geometry.
///
/// ## Why it also carries camera frames
///
/// ARCore takes the camera exclusively, so while this session runs the camera
/// plugin cannot open. Sign reading and obstacle detection would go dead — and
/// those are what guidance actually runs on. Instead the session's own CPU
/// images come across [analysisFrames], and `DetectionService` feeds them to
/// the same ML Kit analysers it always used. See [AnalysisFrame].
class ArGuidanceService implements AnalysisFrameSource {
  ArGuidanceService({
    MethodChannel? methodChannel,
    EventChannel? stateChannel,
    EventChannel? frameChannel,
    bool? platformSupported,
  }) : _method = methodChannel ?? const MethodChannel(_methodChannelName),
       _states = stateChannel ?? const EventChannel(_stateChannelName),
       _frames = frameChannel ?? const EventChannel(_frameChannelName),
       _platformSupported = platformSupported ?? Platform.isAndroid;

  static const String _methodChannelName = 'echo_locate/ar_guidance';
  static const String _stateChannelName = 'echo_locate/ar_guidance/state';
  static const String _frameChannelName = 'echo_locate/ar_guidance/frames';

  final MethodChannel _method;
  final EventChannel _states;
  final EventChannel _frames;
  final bool _platformSupported;

  Stream<ArGuidanceFrame>? _stateStream;
  Stream<AnalysisFrame>? _frameStream;

  bool _running = false;
  bool _analysing = false;
  int? _textureId;

  /// True while [start] is waiting on ARCore.
  bool _starting = false;

  /// Bumped by every [stop], so a [start] that was overtaken by one can tell.
  ///
  /// Without this, a stop that arrives during startup is a no-op — there is
  /// nothing running yet to stop — and the session that comes up a moment later
  /// holds the camera with nobody left to release it. That is a phone whose
  /// camera stays busy after the user has walked away from the screen.
  int _stopEpoch = 0;

  bool get isRunning => _running;

  /// The Flutter texture the camera and the arrows are drawn into.
  int? get textureId => _textureId;

  @override
  bool get isStreaming => _running && _analysing;

  @override
  bool get holdsCamera => _running;

  Future<ArCoreAvailability> checkAvailability() async {
    if (!_platformSupported) return ArCoreAvailability.unsupported;
    try {
      final result = await _method.invokeMethod<String>('checkAvailability');
      return ArCoreAvailability.fromNative(result);
    } on PlatformException catch (e) {
      AppLogger.warn('AR guidance availability check failed: ${e.message}');
      return ArCoreAvailability.unknown;
    } on MissingPluginException {
      return ArCoreAvailability.unsupported;
    }
  }

  /// Asks Play to install or update ARCore.
  ///
  /// Only worth calling when [checkAvailability] came back
  /// [ArCoreAvailability.isUserFixable]. Returns true when ARCore is ready
  /// *now* — the install turned out to be there already — and false when the
  /// user has been sent to Play, or when nothing can be installed. In the
  /// middle case this app is backgrounded while Play works, so the answer that
  /// matters arrives on the next [checkAvailability] after the user returns.
  Future<bool> requestInstall() async {
    if (!_platformSupported) return false;
    try {
      final status = await _method.invokeMethod<String>('requestInstall');
      AppLogger.info('ARCore install request: $status');
      return status == 'installed';
    } on PlatformException catch (e) {
      AppLogger.warn('ARCore install request failed: ${e.message}');
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Starts the session for a view [viewWidth] x [viewHeight] device pixels.
  ///
  /// Returns null on success, or a readable reason it could not start. Every
  /// failure here is survivable: guidance without arrows is the guidance this
  /// app already shipped, and it is the mode a blind user is in anyway.
  Future<String?> start({
    required int viewWidth,
    required int viewHeight,
  }) async {
    if (_running || _starting) return null;
    if (!_platformSupported) return 'AR guidance is Android-only';

    final epoch = _stopEpoch;
    _starting = true;
    try {
      final result = await _method.invokeMethod<Map<Object?, Object?>>('start', {
        'width': viewWidth,
        'height': viewHeight,
      });
      if (epoch != _stopEpoch) {
        // Somebody asked for this to stop while ARCore was coming up — the app
        // was backgrounded, or the screen was left. The session exists now, so
        // it has to be told again.
        _textureId = null;
        await _sendStop();
        return 'The AR view was closed while it was starting.';
      }
      _running = true;
      _textureId = (result?['textureId'] as num?)?.toInt();
      return null;
    } on PlatformException catch (e) {
      AppLogger.warn('AR guidance start failed: ${e.code} ${e.message}');
      return switch (e.code) {
        'permission' => 'Camera permission is needed for the AR view.',
        'unavailable' => 'This phone is not certified for AR.',
        'camera' => 'The camera is not available right now.',
        _ => e.message ?? 'Could not start the AR view.',
      };
    } on MissingPluginException {
      return 'AR guidance is not available on this build.';
    } finally {
      _starting = false;
    }
  }

  Future<void> stop() async {
    final wasActive = _running || _starting;
    _stopEpoch++;
    _running = false;
    _analysing = false;
    _textureId = null;
    if (!wasActive) return;
    await _sendStop();
  }

  Future<void> _sendStop() async {
    try {
      await _method.invokeMethod<void>('stop');
    } on PlatformException catch (e) {
      AppLogger.warn('AR guidance stop failed: ${e.message}');
    } on MissingPluginException {
      // Nothing was running to stop.
    }
  }

  Future<void> setViewport({
    required int viewWidth,
    required int viewHeight,
  }) async {
    if (!_running) return;
    try {
      await _method.invokeMethod<void>('setViewport', {
        'width': viewWidth,
        'height': viewHeight,
      });
    } on PlatformException catch (e) {
      AppLogger.warn('AR viewport update failed: ${e.message}');
    } on MissingPluginException {
      // Nothing native to tell.
    }
  }

  /// Anchors the leg now being walked.
  ///
  /// **Call this at the moment a landmark is confirmed**, not before and not
  /// on a timer. Native reads the walker's direction of travel from the last
  /// few metres of ARCore trajectory, turns it by [turnDeg] — positive is
  /// right, matching `PlannedLeg.turnDeg` — and lays the arrows along the
  /// result. Anchoring at any other time anchors against a direction the walker
  /// is not travelling in.
  ///
  /// [distanceM] is how far the leg runs. On a route whose distances are not
  /// really metres — one planned over a photo-traced plan — pass a nominal
  /// length and do not quote the countdown; the *direction* is still right,
  /// because direction does not have units.
  Future<void> setLeg({required int turnDeg, required double distanceM}) async {
    if (!_running) return;
    try {
      await _method.invokeMethod<void>('setLeg', {
        'turnDeg': turnDeg,
        'distanceM': distanceM,
      });
    } on PlatformException catch (e) {
      AppLogger.warn('Leg anchor failed: ${e.message}');
    } on MissingPluginException {
      // Nothing native to anchor.
    }
  }

  /// Lays a whole route into the room, in ARCore's own world coordinates.
  ///
  /// The replacement for [setLeg] wherever a plan can be registered. [points]
  /// is the path flattened to (x, z) pairs — already transformed, because the
  /// transform is solved in Dart where the plan geometry and the tests that
  /// pin its conventions live (`route_registration.dart`).
  ///
  /// Sending it again re-registers: native keeps the walker's progress when
  /// the new route is the same length as the old one, so correcting a
  /// registration mid-corridor does not send them back to the start of it.
  Future<void> setRoute(List<double> points) async {
    if (!_running) return;
    if (points.length < 4 || points.length.isOdd) {
      AppLogger.warn('Refusing a route of ${points.length} coordinates');
      return;
    }
    try {
      await _method.invokeMethod<void>('setRoute', {'points': points});
    } on PlatformException catch (e) {
      AppLogger.warn('Route registration failed: ${e.message}');
    } on MissingPluginException {
      // Nothing native to register with.
    }
  }

  /// Forgets the registered route, leaving the leg arrows to carry on.
  Future<void> clearRoute() async {
    if (!_running) return;
    try {
      await _method.invokeMethod<void>('clearRoute');
    } on PlatformException catch (e) {
      AppLogger.warn('Route clear failed: ${e.message}');
    } on MissingPluginException {
      // Nothing native to clear.
    }
  }

  /// Stops drawing arrows — on arrival, and while the walker is lost.
  ///
  /// Recovery is the important one: a sweep to find a sign is exactly when the
  /// last leg's arrows are least trustworthy, and leaving them on screen tells
  /// somebody to keep walking a route they have already left.
  Future<void> clearLeg() async {
    if (!_running) return;
    try {
      await _method.invokeMethod<void>('clearLeg');
    } on PlatformException catch (e) {
      AppLogger.warn('Leg clear failed: ${e.message}');
    } on MissingPluginException {
      // Nothing native to clear.
    }
  }

  /// Tells the session that the frame it sent has been analysed.
  ///
  /// Fire and forget, and cheap — no payload, just a nudge. It is what lets the
  /// feed run at the speed of this phone's ML Kit rather than at a rate picked
  /// in advance: too high and camera images are copied only to be dropped, too
  /// low and a door sign goes past unread.
  @override
  void frameHandled() {
    if (!_running || !_analysing) return;
    unawaited(_ackFrame());
  }

  Future<void> _ackFrame() async {
    try {
      await _method.invokeMethod<void>('analysisDone');
    } on PlatformException catch (e) {
      AppLogger.warn('Analysis acknowledgement failed: ${e.message}');
    } on MissingPluginException {
      // Nothing native to tell.
    }
  }

  /// Turns the ML Kit frame feed on or off.
  ///
  /// Off by default, because the copy per frame is only worth paying for on a
  /// screen that is actually reading signs.
  Future<void> setAnalysis({required bool enabled}) async {
    if (!_running) return;
    try {
      await _method.invokeMethod<void>('setAnalysis', {'enabled': enabled});
      _analysing = enabled;
    } on PlatformException catch (e) {
      AppLogger.warn('Analysis toggle failed: ${e.message}');
    } on MissingPluginException {
      // Nothing native to feed.
    }
  }

  /// State from the running session.
  ///
  /// Cached, but deliberately **not** wrapped in `asBroadcastStream()`. The
  /// channel's own stream is already a broadcast one and can be listened to
  /// again after the last subscriber leaves — which is exactly what happens
  /// every time the app is backgrounded and comes back. `asBroadcastStream()`
  /// closes for good when its last listener cancels, so wrapping this would
  /// mean the arrows work once and never again after a resume, with nothing in
  /// the log to say why.
  Stream<ArGuidanceFrame> get states {
    if (!_platformSupported) return const Stream<ArGuidanceFrame>.empty();
    return _stateStream ??= _states
        .receiveBroadcastStream()
        .map(
          (event) => ArGuidanceFrame.fromNative(
            (event as Map).cast<Object?, Object?>(),
          ),
        )
        .handleError((Object error) {
          AppLogger.warn('AR guidance stream error: $error');
        });
  }

  /// Camera frames for ML Kit. Same caching rule, and the same reason: this one
  /// going dead after a resume costs a blind user every automatic landmark
  /// confirmation for the rest of the route.
  @override
  Stream<AnalysisFrame> get analysisFrames {
    if (!_platformSupported) return const Stream<AnalysisFrame>.empty();
    return _frameStream ??= _frames
        .receiveBroadcastStream()
        .map((event) {
          final map = (event as Map).cast<Object?, Object?>();
          return AnalysisFrame(
            bytes: map['bytes'] as Uint8List,
            width: (map['width'] as num).toInt(),
            height: (map['height'] as num).toInt(),
            rotationDegrees: (map['rotation'] as num?)?.toInt() ?? 0,
          );
        })
        .handleError((Object error) {
          AppLogger.warn('AR frame stream error: $error');
        });
  }
}
