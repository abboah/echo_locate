import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../../core/utils/logger.dart';
// Shared with the depth spike rather than redeclared: a device is or is not
// ARCore-capable, and two enums saying so would eventually disagree.
import 'depth_frame.dart' show ArCoreAvailability;

/// How ARCore tracking is doing, and what to tell the user to do about it.
enum CaptureTracking {
  /// Everything working — corners can be placed.
  tracking,

  /// Temporarily lost. Points already captured survive; see [CaptureFrame].
  paused,

  /// Gone for good this session.
  stopped;

  static CaptureTracking fromName(String? value) => switch (value) {
    'TRACKING' => CaptureTracking.tracking,
    'PAUSED' => CaptureTracking.paused,
    _ => CaptureTracking.stopped,
  };

  bool get canCapture => this == CaptureTracking.tracking;
}

/// Why tracking stopped, phrased as the thing the user can change.
///
/// Real buildings — plain painted walls, terrazzo floors, fluorescent light —
/// degrade tracking constantly, so this is not an edge case but the normal
/// texture of using the feature. A bare "tracking lost" leaves somebody
/// standing in a corridor with nothing to try.
enum CaptureTrackingIssue {
  none,
  insufficientFeatures,
  excessiveMotion,
  insufficientLight,
  cameraUnavailable,
  relocalising,
  unknown;

  static CaptureTrackingIssue fromName(String? value) => switch (value) {
    null => CaptureTrackingIssue.none,
    'NONE' => CaptureTrackingIssue.none,
    'INSUFFICIENT_FEATURES' => CaptureTrackingIssue.insufficientFeatures,
    'EXCESSIVE_MOTION' => CaptureTrackingIssue.excessiveMotion,
    'INSUFFICIENT_LIGHT' => CaptureTrackingIssue.insufficientLight,
    'CAMERA_UNAVAILABLE' => CaptureTrackingIssue.cameraUnavailable,
    'BAD_STATE' => CaptureTrackingIssue.unknown,
    _ => CaptureTrackingIssue.relocalising,
  };

  /// What to put on screen. Every one of these is an instruction, not a
  /// diagnosis — the user cannot act on "insufficient features".
  String get advice => switch (this) {
    CaptureTrackingIssue.none => 'Tracking',
    CaptureTrackingIssue.insufficientFeatures =>
      'Point at something with more texture — a door, a sign, furniture.',
    CaptureTrackingIssue.excessiveMotion => 'Move the phone more slowly.',
    CaptureTrackingIssue.insufficientLight => 'More light needed here.',
    CaptureTrackingIssue.cameraUnavailable =>
      'The camera is being used by something else.',
    CaptureTrackingIssue.relocalising =>
      'Finding your place again — look around slowly.',
    CaptureTrackingIssue.unknown => 'Tracking lost. Look around slowly.',
  };
}

/// Which horizontal surface a room is being traced against.
///
/// A furnished room hides its own floor — desks, stacked chairs and boxes sit
/// in exactly the corners that define the shape — while the ceiling above those
/// corners is almost always clear. Walls are vertical, so a ceiling corner is
/// directly above its floor corner and the two differ only in height, which
/// [ArCoreCaptureService.toPlan] drops. **Tracing a room around its ceiling
/// therefore produces the same polygon**, which is what makes this a fallback
/// rather than a second coordinate system.
enum CaptureSurface {
  /// Nothing locked yet — the first corner of a room decides.
  none,
  floor,
  ceiling;

  static CaptureSurface fromName(String? value) => switch (value) {
    'floor' => CaptureSurface.floor,
    'ceiling' => CaptureSurface.ceiling,
    _ => CaptureSurface.none,
  };

  /// What to call it on screen, mid-sentence.
  String get noun => switch (this) {
    CaptureSurface.ceiling => 'ceiling',
    _ => 'floor',
  };

  /// Where on a corner to aim, as a phrase.
  ///
  /// **Load-bearing wording, not decoration.** You tap the *surface* at the
  /// corner — never the wall-to-wall junction itself, which is where ARCore's
  /// plane boundaries are least reliable and where a hit-test most often
  /// returns nothing or the wrong plane. See `SurfaceHitTester`. Dropping this
  /// phrase leaves "tap the floor at each corner", which reads as an
  /// instruction to tap the corner.
  String get cornerAim => switch (this) {
    CaptureSurface.ceiling => 'at the top of each corner',
    _ => 'at the base of each corner',
  };
}

/// One update from the capture session.
///
/// Arrives **on change**, not per frame: the camera reaches the screen as a
/// texture Flutter composites directly, so this stream carries only the handful
/// of facts the UI renders, and they change a few times a minute.
class CaptureFrame {
  const CaptureFrame({
    required this.tracking,
    required this.issue,
    required this.planeLocked,
    this.surface = CaptureSurface.none,
  });

  final CaptureTracking tracking;
  final CaptureTrackingIssue issue;

  /// Whether a surface has been locked for the room being traced.
  final bool planeLocked;

  /// Floor or ceiling, once the room's first corner has landed on one.
  final CaptureSurface surface;

  bool get canCapture => tracking.canCapture;

  static CaptureFrame fromNative(Map<Object?, Object?> map) => CaptureFrame(
    tracking: CaptureTracking.fromName(map['trackingState'] as String?),
    issue: CaptureTrackingIssue.fromName(map['failureReason'] as String?),
    planeLocked: map['planeLocked'] as bool? ?? false,
    surface: CaptureSurface.fromName(map['surface'] as String?),
  );
}

/// A tapped floor point, already in the plan's frame.
class CapturedCorner {
  const CapturedCorner({
    required this.position,
    required this.confidence,
    this.anchorId,
    this.surface = CaptureSurface.none,
  });

  /// Which surface this corner was taken from. Every corner of one room shares
  /// it — the hit tester rejects a tap on the other one — so it is really a
  /// property of the room, kept here because this is where it arrives.
  final CaptureSurface surface;

  /// ARCore's handle on this point, when the platform gave one.
  ///
  /// Held so the position can be **re-read at close**. Between a room's first
  /// corner and its last, ARCore may lose tracking and relocalise, shifting its
  /// idea of where the world origin is — after which [position] is a
  /// measurement in a frame that no longer exists. Anchors are corrected along
  /// with everything else, so asking for them again is what keeps a room the
  /// shape it actually is.
  final String? anchorId;

  /// Metres, in the **plan frame**: +x east, +y north. See [ArCoreCaptureService.toPlan].
  final Offset position;

  /// 1 while the plane was actively tracked, 0.5 when it was not. Kept so a
  /// finished plan can report how much of it was captured under good tracking
  /// rather than quietly averaging that away.
  final double confidence;
}

/// Dart side of AR room capture — floorplan spec §2.
///
/// Owns the ARCore session and exposes it as a typed [CaptureFrame] stream,
/// mirroring [ArCoreDepthService] so the two read the same way and neither has
/// to be learned twice.
///
/// **Every entry point degrades rather than throwing.** ARCore is unavailable
/// on a large share of budget Android hardware — including this project's own
/// daily test device — and on every non-Android target. "This phone cannot
/// scan" is a normal state the UI renders and an offer of photo tracing
/// instead, not an exception.
class ArCoreCaptureService {
  ArCoreCaptureService({
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
    bool? platformSupported,
  }) : _method = methodChannel ?? const MethodChannel(_methodChannelName),
       _events = eventChannel ?? const EventChannel(_eventChannelName),
       _platformSupported = platformSupported ?? Platform.isAndroid;

  static const String _methodChannelName = 'echo_locate/arcore_capture';
  static const String _eventChannelName = 'echo_locate/arcore_capture/frames';

  final MethodChannel _method;
  final EventChannel _events;

  /// Whether the platform has a native side at all.
  ///
  /// Injectable purely so this class can be tested. Defaults to
  /// `Platform.isAndroid`, and reading it once in the constructor rather than
  /// at every call site is what stops the guard drifting between methods —
  /// which is how the depth spike ended up with one path that checked and one
  /// that did not.
  final bool _platformSupported;

  Stream<CaptureFrame>? _frames;
  bool _running = false;
  int? _textureId;

  bool get isRunning => _running;

  /// The Flutter texture the camera is being drawn into, once [start] has
  /// succeeded.
  ///
  /// The camera image never crosses the platform channel: ARCore renders into a
  /// GL texture, native blits that into a surface Flutter registered, and the
  /// screen shows it with a `Texture` widget. The earlier version shipped
  /// throttled JPEG frames over the event channel instead, which cost enough
  /// per frame — subsample, encode, marshal, decode — to starve the tracking
  /// loop it shared a thread with.
  int? get textureId => _textureId;

  /// ARCore world space to the plan frame.
  ///
  /// **This function is the whole coordinate contract, and the sign is the
  /// easiest thing in the feature to get wrong.**
  ///
  /// ARCore is right-handed with **+Y up**, so the floor is the XZ plane and Y
  /// is dropped. But ARCore's **−Z points away from the camera** — forward is
  /// negative Z — while the plan frame's +y is north, the direction you are
  /// facing when you set off. So plan y is `-z`, not `z`.
  ///
  /// Getting this backwards mirrors the entire floor about its east-west axis.
  /// Nothing looks broken: rooms are still rooms, corridors are still
  /// corridors, and every single left and right the directions layer generates
  /// is inverted. `room_geometry.dart`'s header is the long version of why that
  /// matters more here than almost anywhere.
  static Offset toPlan(double x, double z) => Offset(x, -z);

  /// Whether this device can run ARCore at all.
  ///
  /// Returns [ArCoreAvailability.unsupported] off Android without touching the
  /// channel — nothing is registered there and a MissingPluginException would
  /// be noise rather than information.
  Future<ArCoreAvailability> checkAvailability() async {
    if (!_platformSupported) return ArCoreAvailability.unsupported;
    try {
      final result = await _method.invokeMethod<String>('checkAvailability');
      return ArCoreAvailability.fromNative(result);
    } on PlatformException catch (e) {
      AppLogger.warn('ARCore capture availability check failed: ${e.message}');
      return ArCoreAvailability.unknown;
    } on MissingPluginException {
      return ArCoreAvailability.unsupported;
    }
  }

  /// Starts the session. Returns null on success, or a readable reason it could
  /// not start.
  ///
  /// Camera permission must already be granted — the existing camera primer
  /// flow stays the single place that asks for it.
  /// Starts the session for a view [viewWidth] x [viewHeight] device pixels.
  ///
  /// **This is what makes hit-testing correct.** ARCore is handed the view it
  /// is notionally drawing into and does the camera-to-view mapping itself —
  /// sensor orientation, aspect mismatch and all — so nothing here has to
  /// reason about how a landscape sensor image lands in a portrait widget.
  ///
  /// The display rotation is **not** passed: Flutter has no portable way to
  /// report Android's `Surface.ROTATION_*`, so this used to send a hardcoded
  /// zero that was right only in portrait. Native reads it from the activity
  /// instead, on every call, which is both shorter and always right.
  /// The same geometry drives the preview — the renderer asks ARCore for its
  /// texture coordinates rather than deriving them — so the picture and the
  /// taps are mapped by one calculation and cannot disagree.
  ///
  /// On success [textureId] is set to the Flutter texture the camera is being
  /// drawn into.
  Future<String?> start({
    required int viewWidth,
    required int viewHeight,
  }) async {
    if (_running) return null;
    if (!_platformSupported) return 'AR capture is Android-only';

    try {
      final result = await _method.invokeMethod<Map<Object?, Object?>>('start', {
        'width': viewWidth,
        'height': viewHeight,
      });
      _running = true;
      _textureId = (result?['textureId'] as num?)?.toInt();
      return null;
    } on PlatformException catch (e) {
      AppLogger.warn('AR capture start failed: ${e.code} ${e.message}');
      return switch (e.code) {
        'permission' => 'Camera permission is needed to scan.',
        'unavailable' =>
          'This phone is not certified for AR scanning. Trace from a photo instead.',
        'camera' => 'The camera is not available right now.',
        _ => e.message ?? 'Could not start scanning.',
      };
    } on MissingPluginException {
      return 'AR capture is not available on this build.';
    }
  }

  /// Tells ARCore the view changed size or the device rotated.
  ///
  /// Cheap, and skipping it leaves ARCore mapping taps against a viewport that
  /// no longer exists — which shows up as corners landing progressively further
  /// from the finger after a rotation, rather than as anything that looks like
  /// an error. It also resizes the preview texture and rebuilds the GL surface
  /// drawn into it, both of which are bound to the old size.
  ///
  /// A size change is the only signal Dart has that the device rotated, so this
  /// is what prompts native to re-read the display rotation.
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
      AppLogger.warn('Viewport update failed: ${e.message}');
    } on MissingPluginException {
      // Nothing native to tell.
    }
  }

  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    // Cleared with the session: the texture is released natively, and a screen
    // still holding the id would show a `Texture` widget over nothing.
    _textureId = null;
    try {
      await _method.invokeMethod<void>('stop');
    } on PlatformException catch (e) {
      AppLogger.warn('AR capture stop failed: ${e.message}');
    } on MissingPluginException {
      // Nothing was running to stop.
    }
  }

  /// Hit-tests the floor at a normalised point in the preview.
  ///
  /// [u] and [v] are 0..1 across the preview, so the caller never has to know
  /// the camera image's size and a preview laid out at any size maps to the
  /// same place.
  ///
  /// Null means the tap hit nothing usable — no tracking, no plane there, a
  /// point beyond what ARCore has actually seen, or a surface that is not the
  /// one this room locked to. That is a normal outcome, and the screen says
  /// where to aim rather than reporting a failure.
  /// [lock] ties this tap to the surface the room is being traced on, and is
  /// what rejects a corner placed on a desk. Doors pass false: a door is a
  /// single point tapped in a doorway elsewhere in the building, on a plane
  /// ARCore may never have merged with the last room's, and holding it to the
  /// lock rejected every doorway after the first.
  Future<CapturedCorner?> hitTest(double u, double v, {bool lock = true}) async {
    if (!_running) return null;
    try {
      final result = await _method.invokeMethod<Map<Object?, Object?>>(
        'hitTest',
        {'u': u, 'v': v, 'lock': lock},
      );
      if (result == null) return null;

      final x = (result['x'] as num?)?.toDouble();
      final z = (result['z'] as num?)?.toDouble();
      if (x == null || z == null) return null;

      return CapturedCorner(
        position: toPlan(x, z),
        confidence: (result['confidence'] as num?)?.toDouble() ?? 1,
        anchorId: result['id'] as String?,
        surface: CaptureSurface.fromName(result['surface'] as String?),
      );
    } on PlatformException catch (e) {
      AppLogger.warn('Hit test failed: ${e.message}');
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Re-reads the given corners, as ARCore believes them **now**.
  ///
  /// Called when a room closes. Returns the corners with any anchor that is
  /// still tracked moved to its corrected position, and the rest untouched —
  /// an anchor ARCore has lost is not guessed at, and its tapped position is
  /// the best that remains.
  ///
  /// Without this a room whose capture straddled a relocalisation comes out
  /// deformed: some corners in the old frame, some in the new, no error
  /// anywhere, and a floor plan that is simply the wrong shape.
  Future<List<CapturedCorner>> resolveCorners(
    List<CapturedCorner> corners,
  ) async {
    if (!_running) return corners;
    final ids = [
      for (final corner in corners)
        if (corner.anchorId != null) corner.anchorId!,
    ];
    if (ids.isEmpty) return corners;

    try {
      final resolved = await _method.invokeMethod<Map<Object?, Object?>>(
        'resolveAnchors',
        {'ids': ids},
      );
      if (resolved == null || resolved.isEmpty) return corners;

      return [
        for (final corner in corners)
          if (resolved[corner.anchorId] case final Map<Object?, Object?> at)
            CapturedCorner(
              position: toPlan(
                (at['x'] as num).toDouble(),
                (at['z'] as num).toDouble(),
              ),
              confidence: corner.confidence,
              anchorId: corner.anchorId,
              surface: corner.surface,
            )
          else
            corner,
      ];
    } on PlatformException catch (e) {
      AppLogger.warn('Anchor resolve failed: ${e.message}');
      return corners;
    } on MissingPluginException {
      return corners;
    }
  }

  /// Detaches anchors that are no longer needed.
  ///
  /// Anchors cost ARCore tracking work every frame, so a session that never
  /// releases them gets slower the longer a building is walked — which is
  /// exactly the session that can least afford it.
  Future<void> releaseCorners(List<CapturedCorner> corners) async {
    if (!_running) return;
    final ids = [
      for (final corner in corners)
        if (corner.anchorId != null) corner.anchorId!,
    ];
    if (ids.isEmpty) return;
    try {
      await _method.invokeMethod<void>('releaseAnchors', {'ids': ids});
    } on PlatformException catch (e) {
      AppLogger.warn('Anchor release failed: ${e.message}');
    } on MissingPluginException {
      // Nothing native to release.
    }
  }

  /// Forgets the locked floor plane, so the next room locks to its own.
  ///
  /// Called when a room is finished rather than when one starts, so the lock is
  /// already clear if the user simply walks into the next room and taps.
  Future<void> resetPlaneLock() async {
    if (!_running) return;
    try {
      await _method.invokeMethod<void>('resetPlaneLock');
    } on PlatformException catch (e) {
      AppLogger.warn('Plane lock reset failed: ${e.message}');
    } on MissingPluginException {
      // Nothing native to reset.
    }
  }

  /// Tracking state, pushed when it changes.
  ///
  /// Not per frame. The camera is a texture Flutter composites, so nothing here
  /// is on the hot path, and native suppresses repeats — otherwise every screen
  /// listening rebuilt at camera rate for facts that had not moved.
  ///
  /// Broadcast and cached, so the Bloc and any diagnostic view can both listen
  /// without starting two sessions.
  Stream<CaptureFrame> get frames {
    if (!_platformSupported) return const Stream<CaptureFrame>.empty();
    return _frames ??= _events
        .receiveBroadcastStream()
        .map(
          (event) =>
              CaptureFrame.fromNative((event as Map).cast<Object?, Object?>()),
        )
        .handleError((Object error) {
          AppLogger.warn('AR capture stream error: $error');
        })
        .asBroadcastStream();
  }
}
