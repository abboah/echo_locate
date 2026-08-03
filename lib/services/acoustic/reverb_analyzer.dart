import 'dart:math' as math;
import 'dart:typed_data';

import 'reverb_features.dart';

/// Extracts reverberation time from a room's impulse response.
///
/// Feeds the M5 room-type classifier, and shares its input with the sonar:
/// the matched-filter output [CrossCorrelationService] already produces IS an
/// impulse response estimate, so the same chirp serves both features.
///
/// Method is Schroeder backward integration (Schroeder 1965), the standard
/// approach and what ISO 3382 specifies. Rather than measure a 60dB decay
/// directly — which would need a signal 60dB above the room's noise floor,
/// unachievable from a phone speaker — it integrates the squared response
/// backwards in time to recover a smooth energy decay curve, fits a line to a
/// reliable stretch of it, and extrapolates that slope to 60dB.
class ReverbAnalyzer {
  const ReverbAnalyzer({
    this.upperDb = -5.0,
    this.lowerDb = -25.0,
    this.minimumDecayDb = 10.0,
    this.maximumFitPositionInCapture = 0.9,
  });

  /// Where the fit starts, in dB below the initial energy.
  ///
  /// Not 0dB: the first instant of the curve is dominated by the direct sound
  /// and the earliest reflections, which decay at their own rate and would
  /// bias the fit. Backing off 5dB is the ISO 3382 convention.
  final double upperDb;

  /// Where the fit ends. With [upperDb] at -5 this spans 20dB — the "T20"
  /// estimate. A wider span is more reliable when the noise floor allows it,
  /// but 20dB is what a phone can usually clear indoors.
  final double lowerDb;

  /// Least decay that may be fitted before the result is refused outright.
  final double minimumDecayDb;

  /// How far into the capture the fitted stretch may extend, as a fraction.
  ///
  /// Guards the one artifact this method cannot otherwise see. Backward
  /// integration means the curve always collapses at the end of the buffer —
  /// there is no energy left to integrate — so a capture that simply stopped
  /// too early exhibits a steep, convincing, entirely fictitious decay. A 20ms
  /// capture of a 1.5s reverberant space reported RT60 = 0.033s over 20dB of
  /// this artifact. A real decay completes well inside its recording; one that
  /// only reaches the target level as the tape runs out is measuring the tape.
  final double maximumFitPositionInCapture;

  /// Returns null when [impulseResponse] contains no usable decay — too
  /// short, too noisy, or no impulse at all. Never guesses: a wrong RT60
  /// silently mislabels a room.
  ReverbFeatures? analyze({
    required Float64List impulseResponse,
    required int sampleRate,
  }) {
    if (impulseResponse.isEmpty || sampleRate <= 0) return null;

    // Integration starts at the direct sound. Anything before it is the
    // pre-arrival noise floor and would add energy the room never contained.
    final onset = _onsetIndex(impulseResponse);
    if (onset >= impulseResponse.length - 2) return null;

    final decayCurveDb = _schroederCurveDb(impulseResponse, onset);
    if (decayCurveDb == null) return null;

    final rt60 = _extrapolatedDecayTime(
      decayCurveDb: decayCurveDb,
      sampleRate: sampleRate,
      fromDb: upperDb,
      toDb: lowerDb,
    );
    if (rt60 == null) return null;

    // EDT over the first 10dB. Falls back to the main estimate when the
    // curve is too coarse there, so a usable RT60 is not thrown away just
    // because its early portion was short.
    final edt = _extrapolatedDecayTime(
          decayCurveDb: decayCurveDb,
          sampleRate: sampleRate,
          fromDb: 0.0,
          toDb: -10.0,
        ) ??
        rt60;

    return ReverbFeatures(
      rt60Seconds: rt60.seconds,
      earlyDecayTimeSeconds: edt.seconds,
      fitQuality: rt60.rSquared,
      decayRangeDb: rt60.spanDb,
    );
  }

  /// Index of the direct sound — the response's largest absolute value.
  int _onsetIndex(Float64List response) {
    var peakIndex = 0;
    var peak = response[0].abs();
    for (var i = 1; i < response.length; i++) {
      final value = response[i].abs();
      if (value > peak) {
        peak = value;
        peakIndex = i;
      }
    }
    return peakIndex;
  }

  /// Schroeder energy decay curve, in dB relative to total energy.
  ///
  /// `EDC[n] = sum of h[k]^2 for k >= n`, so each point is the energy still
  /// to come. Integrating backwards is what turns a noisy, wildly fluctuating
  /// squared response into a monotonically decreasing curve smooth enough to
  /// fit a line to — the whole reason the method exists.
  Float64List? _schroederCurveDb(Float64List response, int onset) {
    final length = response.length - onset;
    if (length < 4) return null;

    final curve = Float64List(length);
    var running = 0.0;
    for (var i = length - 1; i >= 0; i--) {
      final sample = response[onset + i];
      running += sample * sample;
      curve[i] = running;
    }

    final total = curve[0];
    if (total <= 0) return null;

    for (var i = 0; i < length; i++) {
      // Guard the log: the final sample integrates to exactly zero energy.
      curve[i] = curve[i] <= 0 ? -double.infinity : 10 * math.log(curve[i] / total) / math.ln10;
    }
    return curve;
  }

  /// Least-squares slope of [decayCurveDb] between two dB levels, scaled to
  /// the time a 60dB decay would take.
  _DecayFit? _extrapolatedDecayTime({
    required Float64List decayCurveDb,
    required int sampleRate,
    required double fromDb,
    required double toDb,
  }) {
    // The curve decreases monotonically, so the first crossing of each level
    // is the one wanted.
    final start = _firstIndexAtOrBelow(decayCurveDb, fromDb);
    if (start == null) return null;
    final end = _firstIndexAtOrBelow(decayCurveDb, toDb);
    if (end == null || end <= start + 2) return null;
    // See [maximumFitPositionInCapture]: a decay that only reaches its target
    // level as the buffer ends is the buffer ending, not the room decaying.
    if (end > decayCurveDb.length * maximumFitPositionInCapture) return null;

    final spanDb = decayCurveDb[start] - decayCurveDb[end];
    if (spanDb < minimumDecayDb) return null;

    // Least squares over t (seconds) against level (dB).
    var sumT = 0.0;
    var sumL = 0.0;
    var sumTT = 0.0;
    var sumTL = 0.0;
    final n = end - start + 1;
    for (var i = start; i <= end; i++) {
      final t = i / sampleRate;
      final l = decayCurveDb[i];
      sumT += t;
      sumL += l;
      sumTT += t * t;
      sumTL += t * l;
    }
    final denominator = n * sumTT - sumT * sumT;
    if (denominator == 0) return null;

    final slope = (n * sumTL - sumT * sumL) / denominator; // dB per second
    // A decay must fall. A non-negative slope means this was not one.
    if (slope >= 0) return null;

    final intercept = (sumL - slope * sumT) / n;

    // r²: how much of the level variation the straight line accounts for.
    var totalSumSquares = 0.0;
    var residualSumSquares = 0.0;
    final meanL = sumL / n;
    for (var i = start; i <= end; i++) {
      final t = i / sampleRate;
      final l = decayCurveDb[i];
      final predicted = slope * t + intercept;
      totalSumSquares += (l - meanL) * (l - meanL);
      residualSumSquares += (l - predicted) * (l - predicted);
    }
    final rSquared =
        totalSumSquares == 0 ? 1.0 : 1 - residualSumSquares / totalSumSquares;

    return _DecayFit(
      seconds: -60.0 / slope,
      rSquared: rSquared.clamp(0.0, 1.0),
      spanDb: spanDb,
    );
  }

  int? _firstIndexAtOrBelow(Float64List curveDb, double level) {
    for (var i = 0; i < curveDb.length; i++) {
      if (curveDb[i] <= level) return i;
    }
    return null;
  }
}

class _DecayFit {
  const _DecayFit({
    required this.seconds,
    required this.rSquared,
    required this.spanDb,
  });

  final double seconds;
  final double rSquared;
  final double spanDb;
}
