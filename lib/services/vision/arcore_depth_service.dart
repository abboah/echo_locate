import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../../core/utils/logger.dart';
import 'depth_frame.dart';

/// Dart side of the M0 ARCore spike: owns the depth session and exposes it as
/// a typed [DepthFrame] stream.
///
/// GetIt-registered per CLAUDE.md's live-sensing pattern — a Bloc subscribes
/// to [frames] and emits per frame; this class owns the hardware.
///
/// Every entry point degrades instead of throwing. ARCore is unavailable on a
/// large share of budget Android hardware (and on all iOS/desktop targets), so
/// "cannot scan" is a normal state this app has to render, not an exception.
class ArCoreDepthService {
  ArCoreDepthService({
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
  })  : _method = methodChannel ?? const MethodChannel(_methodChannelName),
        _events = eventChannel ?? const EventChannel(_eventChannelName);

  static const String _methodChannelName = 'echo_locate/arcore_depth';
  static const String _eventChannelName = 'echo_locate/arcore_depth/frames';

  final MethodChannel _method;
  final EventChannel _events;

  Stream<DepthFrame>? _frames;
  bool _running = false;

  bool get isRunning => _running;

  /// Whether this device can run ARCore at all.
  ///
  /// Returns [ArCoreAvailability.unsupported] off Android without touching the
  /// channel — there is no handler registered on other platforms, and a
  /// MissingPluginException there would be noise, not information.
  Future<ArCoreAvailability> checkAvailability() async {
    if (!Platform.isAndroid) return ArCoreAvailability.unsupported;
    try {
      final result = await _method.invokeMethod<String>('checkAvailability');
      return ArCoreAvailability.fromNative(result);
    } on PlatformException catch (e) {
      AppLogger.warn('ARCore availability check failed: ${e.message}');
      return ArCoreAvailability.unknown;
    } on MissingPluginException {
      return ArCoreAvailability.unsupported;
    }
  }

  /// Whether the Depth API specifically is supported.
  ///
  /// Separate from [checkAvailability] because they genuinely differ: ARCore
  /// certification does not imply Depth API support, and a device can pass the
  /// first check and fail this one. Scanning needs both.
  Future<bool> isDepthSupported() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _method.invokeMethod<bool>('isDepthSupported') ?? false;
    } on PlatformException catch (e) {
      AppLogger.warn('ARCore depth support check failed: ${e.message}');
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Starts the ARCore session. Returns null on success, or a human-readable
  /// reason it could not start — callers should surface that rather than
  /// retrying, since every failure here needs user action (grant camera,
  /// install ARCore) or is permanent (uncertified device).
  ///
  /// Camera permission must already be granted; this does not request it, so
  /// the existing camera primer flow stays the single place that asks.
  Future<String?> start() async {
    if (_running) return null;
    if (!Platform.isAndroid) return 'Depth scanning is Android-only for now';

    try {
      await _method.invokeMethod<void>('start');
      _running = true;
      AppLogger.info('ARCORE-DEPTH session started');
      return null;
    } on PlatformException catch (e) {
      AppLogger.warn('ARCore start failed [${e.code}]: ${e.message}');
      return switch (e.code) {
        'permission' => 'Camera permission is needed to scan',
        'unavailable' => 'ARCore is not available on this device',
        'depthUnsupported' =>
          'This device supports ARCore but not depth sensing',
        'camera' => 'The camera is in use by another app',
        _ => e.message ?? 'Could not start depth scanning',
      };
    } on MissingPluginException {
      return 'Depth scanning is not available on this platform';
    }
  }

  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    try {
      await _method.invokeMethod<void>('stop');
      AppLogger.info('ARCORE-DEPTH session stopped');
    } on PlatformException catch (e) {
      AppLogger.warn('ARCore stop failed: ${e.message}');
    } on MissingPluginException {
      // Nothing was running natively; the flag is already cleared.
    }
  }

  /// Live depth frames. Broadcast and cached, so several listeners share one
  /// native session rather than each spinning up their own.
  Stream<DepthFrame> get frames {
    return _frames ??= _events
        .receiveBroadcastStream()
        .map((event) => event is Map
            ? DepthFrame.fromNative(event)
            : const DepthFrame.untracked(DepthTrackingState.stopped))
        .handleError((Object e) => AppLogger.warn('ARCore frame error: $e'))
        .asBroadcastStream();
  }
}
