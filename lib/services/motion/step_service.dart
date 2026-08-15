import 'dart:async';

import 'package:pedometer/pedometer.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/utils/logger.dart';

/// Whether this device can count steps at all.
enum StepCounterStatus {
  /// Started, but nothing has ticked yet. A stationary user looks like this,
  /// so it is not on its own a reason to fall back.
  unknown,

  /// A reading has arrived; the sensor is real.
  available,

  /// No permission, or no counter on this hardware. Guidance drops to the
  /// OCR-only rung of the fallback ladder (spec §7 B5 rung 2).
  unavailable,
}

/// Steps walked since the last landmark.
///
/// Wraps Android's `TYPE_STEP_COUNTER` (via `pedometer`) — the same hardware
/// sensor Google Fit reads, not accelerometer maths — so holding the phone up
/// to read a sign does not invent steps.
///
/// The sensor reports a count since boot, which is not what guidance needs.
/// This class keeps the baseline and publishes steps *since the last [reset]*;
/// an OCR landmark match resets it, which is the mechanism that stops step
/// error accumulating over a route.
///
/// [cumulativeSteps] and [requestPermission] are injectable so the baseline
/// arithmetic — where the reboot and reset bugs live — is testable without a
/// phone.
class StepService {
  StepService({
    Stream<int>? cumulativeSteps,
    Future<bool> Function()? requestPermission,
  }) : _source = cumulativeSteps,
       _requestPermission = requestPermission;

  final Stream<int>? _source;
  final Future<bool> Function()? _requestPermission;

  StreamSubscription<int>? _subscription;
  final _stepsController = StreamController<int>.broadcast();

  int? _baseline;
  int _stepsSinceReset = 0;
  StepCounterStatus _status = StepCounterStatus.unknown;

  /// Steps since the last [reset], one event per hardware tick.
  Stream<int> get steps => _stepsController.stream;

  int get stepsSinceReset => _stepsSinceReset;

  StepCounterStatus get status => _status;

  /// Requests permission and subscribes. Returns false when the counter is
  /// unusable, which is a supported outcome, not an error — the caller drops
  /// to OCR-only guidance.
  Future<bool> start() async {
    if (_subscription != null) return _status != StepCounterStatus.unavailable;

    final granted = await (_requestPermission ?? _defaultPermission)();
    if (!granted) {
      AppLogger.warn('Activity recognition denied — guidance runs OCR-only');
      _status = StepCounterStatus.unavailable;
      return false;
    }

    _status = StepCounterStatus.unknown;
    _subscription = (_source ?? _defaultSource()).listen(
      _onReading,
      onError: (Object e) {
        // No counter on this hardware. Reported rather than thrown: the
        // fallback ladder is designed for exactly this device.
        AppLogger.warn('Step counter unavailable: $e');
        _status = StepCounterStatus.unavailable;
      },
      cancelOnError: false,
    );
    return true;
  }

  /// Zeroes the count at the current reading. Called when a landmark is
  /// confirmed, and at the start of each leg.
  void reset() {
    _baseline = _baseline == null ? null : _baseline! + _stepsSinceReset;
    _stepsSinceReset = 0;
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    _baseline = null;
    _stepsSinceReset = 0;
    _status = StepCounterStatus.unknown;
  }

  Future<void> dispose() async {
    await stop();
    await _stepsController.close();
  }

  void _onReading(int cumulative) {
    _status = StepCounterStatus.available;

    // First reading of the session, or the count went backwards. The sensor
    // restarts at zero on reboot, and subtracting a stale baseline would
    // publish a negative walk — which `expectedSteps` would read as progress
    // in the wrong direction.
    if (_baseline == null || cumulative < _baseline!) {
      _baseline = cumulative;
      _stepsSinceReset = 0;
      _stepsController.add(0);
      return;
    }

    _stepsSinceReset = cumulative - _baseline!;
    _stepsController.add(_stepsSinceReset);
  }

  static Future<bool> _defaultPermission() async {
    final status = await Permission.activityRecognition.request();
    return status.isGranted;
  }

  Stream<int> _defaultSource() =>
      Pedometer.stepCountStream.map((event) => event.steps);
}
