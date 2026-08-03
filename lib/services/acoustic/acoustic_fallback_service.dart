import 'dart:math' as math;

import '../../core/utils/logger.dart';
import '../audio/sonar_audio_service.dart';
import 'acoustic_range.dart';

/// Supplies a distance by sound when camera depth cannot.
///
/// This is the hand-off the build plan's M5 calls for — *"acoustic fallback
/// distance when depth is unreliable"* — and the chapter text's *"fallback
/// distance estimate for situations in which vision-based depth fails"*, in
/// low light or against featureless surfaces. Pair it with [DepthReliability],
/// which decides when depth has failed; this decides what sound can say about
/// it.
///
/// Deliberately a separate service rather than a method on
/// [SonarAudioService]. The sonar screen and this fallback want opposite
/// things from the same hardware: the screen is driven by a user who pressed a
/// button and will wait, while this is driven by a camera frame that failed
/// and must not be allowed to chirp on every subsequent one. The throttle,
/// the range floor and the refusal vocabulary all belong to the second case
/// and would be noise in the first.
class AcousticFallbackService {
  AcousticFallbackService(
    this._audio, {
    this.sweeps = 3,
    this.cooldown = const Duration(seconds: 4),
    this.uncalibratedFloorMeters = 0.6,
    this.confidenceSaturationRatio = 30.0,
    DateTime Function() clock = DateTime.now,
  }) : _clock = clock;

  final SonarAudioService _audio;
  final DateTime Function() _clock;

  /// Sweeps per request. The median of several discards the odd bad lock —
  /// see [SonarAudioService.measure] — at roughly 1.8s per sweep.
  final int sweeps;

  /// Least time between measurements.
  ///
  /// The reason this service owns a throttle at all: its trigger is a depth
  /// frame that failed, and depth fails for a *duration* — a dim corridor
  /// keeps failing at 30 frames a second. A caller looping "if depth is bad,
  /// get a range" would queue thirty requests a second against a measurement
  /// that takes seconds and holds the speaker while it runs. Rate limiting
  /// cannot be left to each caller: it is a property of the hardware, so it
  /// lives with the hardware.
  ///
  /// Slightly longer than one measurement, so successive requests leave the
  /// audio free in between for the callouts that share it.
  final Duration cooldown;

  /// Closest distance reportable without a clutter profile.
  ///
  /// Below this the phone's own speaker ringing dominates: measured at ~13x
  /// the correlation noise floor out to roughly this range, which wins the
  /// peak search outright and reports the handset back to the caller as if it
  /// were a wall. [ToFCalculator] can be pushed to 0.08m, but only with a
  /// clutter profile subtracted — and device calibration is exactly what this
  /// fallback is meant to work without. A near reading is therefore refused
  /// rather than reported: for a fallback whose job is walls and obstacles at
  /// one to five metres, losing the near field costs nothing, while a
  /// confident 0.2m that is really the phone would corrupt the fused result.
  final double uncalibratedFloorMeters;

  /// Peak-to-noise ratio at which [AcousticRange.confidence] reaches 1.0.
  ///
  /// Anchored on measured values: a real wall echo stood at 10-12x the median
  /// floor, and the gate to accept a reading at all is 8x
  /// ([ToFCalculator.noiseGateRatio]). Saturating at 30 puts a typical good
  /// echo near the middle of the scale rather than pinned at the top, so the
  /// number can still distinguish a strong return from a marginal one.
  final double confidenceSaturationRatio;

  DateTime? _lastMeasuredAt;

  /// True when a request right now would be throttled. Lets a caller skip the
  /// call entirely rather than await a refusal it could have predicted.
  bool get isThrottled {
    final last = _lastMeasuredAt;
    return last != null && _clock().difference(last) < cooldown;
  }

  /// Measures the distance to whatever is in front of the phone.
  ///
  /// Never throws and never guesses: every failure is a named [RangeRefusal],
  /// because a fusion layer that cannot tell "no surface there" from "the
  /// speaker was busy" will eventually treat the second as the first.
  Future<AcousticRangeResult> rangeAhead() async {
    if (!_audio.isReady) {
      return const AcousticRangeResult.refused(RangeRefusal.audioUnavailable);
    }
    if (isThrottled) {
      return const AcousticRangeResult.refused(RangeRefusal.throttled);
    }
    if (_audio.isBusy) {
      return const AcousticRangeResult.refused(RangeRefusal.audioBusy);
    }

    // Stamped before the measurement, not after: the cooldown is there to
    // stop a failing camera queueing requests, and a measurement that takes
    // seconds would otherwise accept a fresh one the instant it returned.
    _lastMeasuredAt = _clock();

    final result = await _audio.measure(sweeps: sweeps);

    if (result == null) {
      final refusal = _audio.lastCaptureYielded
          ? RangeRefusal.audioBusy
          : RangeRefusal.noEcho;
      AppLogger.debug('ACOUSTIC-FALLBACK refused :: ${refusal.name}');
      return AcousticRangeResult.refused(refusal);
    }

    final calibrated = _audio.hasClutterProfile;
    if (!calibrated && result.distanceMeters < uncalibratedFloorMeters) {
      AppLogger.debug(
        'ACOUSTIC-FALLBACK refused :: '
        '${result.distanceMeters.toStringAsFixed(2)}m is inside the '
        'uncalibrated floor (${uncalibratedFloorMeters}m) — likely ringing',
      );
      return const AcousticRangeResult.refused(
        RangeRefusal.belowUncalibratedFloor,
      );
    }

    final range = AcousticRange(
      distanceMeters: result.distanceMeters,
      confidence: _confidence(result.peakToNoiseRatio),
      // The emission time the audio service stamped, not "now": the
      // measurement took seconds, and the caller needs the instant the sound
      // left the speaker to pair this with a depth frame.
      capturedAt: result.capturedAt ?? _clock(),
      calibrated: calibrated,
    );
    AppLogger.info('ACOUSTIC-FALLBACK $range');
    return AcousticRangeResult.measured(range);
  }

  /// Maps peak-to-noise ratio onto 0..1, from the acceptance gate up to
  /// [confidenceSaturationRatio].
  double _confidence(double peakToNoiseRatio) {
    const gate = 8.0; // ToFCalculator.noiseGateRatio — nothing weaker arrives.
    final span = confidenceSaturationRatio - gate;
    if (span <= 0) return 1.0;
    return math.min(1.0, math.max(0.0, (peakToNoiseRatio - gate) / span));
  }
}
