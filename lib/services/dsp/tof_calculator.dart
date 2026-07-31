import 'dart:math' as math;
import 'dart:typed_data';

import 'package:equatable/equatable.dart';

/// Distance derived from a correlation peak, plus how trustworthy that peak
/// is (ratio of the peak to the correlation noise floor).
class ToFResult extends Equatable {
  const ToFResult({
    required this.distanceMeters,
    required this.peakToNoiseRatio,
  });

  final double distanceMeters;

  /// How far the echo stood above the noise floor. See
  /// [ToFCalculator.noiseGateRatio] for the measured scale.
  final double peakToNoiseRatio;

  @override
  List<Object?> get props => [distanceMeters, peakToNoiseRatio];
}

/// Converts a [CrossCorrelationService] correlation array into a
/// time-of-flight distance.
///
/// Timing anchor: the recording starts long before the chirp plays (recorder
/// warmup) and the playback engine adds its own latency, so the chirp lands
/// hundreds of ms into the buffer at an offset that varies run to run. The
/// buffer's first sample therefore means nothing as a t=0. Instead, the
/// strongest correlation peak — the direct speaker-to-mic breakthrough,
/// travelling ~0m — IS t=0, measured physically. Echoes are searched relative
/// to it. (On-device logs previously showed a "very strong repeatable false
/// peak around 140-155m" when searching from the buffer start: 147m round
/// trip is ~857ms of lag, exactly where the chirp actually sat in the buffer.
/// That "artifact" was the breakthrough all along.)
///
/// Multi-pulse averaging: a recording may contain several chirps
/// ([pulseCount] > 1). Each pulse's breakthrough is located independently,
/// and the per-pulse correlation envelopes (|corr| relative to each anchor)
/// are averaged before peak-picking. Real echoes sit at the same delay after
/// every anchor and survive the average; incoherent noise doesn't, so the
/// floor drops by roughly sqrt(pulseCount).
class ToFCalculator {
  const ToFCalculator({
    this.speedOfSoundMps = 343.0,
    this.noiseGateRatio = 8.0,
    // The guard must sit well BELOW the closest range to be measured, not
    // at it. A target's compressed pulse is ~7 samples wide (set by the
    // 6kHz bandwidth), so a peak whose centre is only a few samples past
    // the guard still has its maximum land on the boundary — where
    // [_Echo.atGuardEdge] correctly discards it as a ringing shoulder. At
    // 0.10m the guard fell 3 samples short of a 0.15m target and rejected
    // it outright, despite the peak standing 300-500x over the noise floor.
    // It cannot go arbitrarily low either: the breakthrough's own compressed
    // pulse is ~7 samples wide, so a guard inside that lobe just finds the
    // breakthrough's skirt instead (0.05m = 13 samples did exactly that,
    // reporting a confident 0.055m against empty air).
    //
    // 0.08m (~21 samples) threads both: clear of the breakthrough lobe, and
    // ~8 samples below a 0.15m target so that target's peak is unambiguously
    // interior.
    //
    // Going this low depends on a [clutterProfile]. Without one the
    // device's ringing measured ~13x the noise floor out to ~0.6m
    // equivalent and won the peak search outright.
    this.minRangeMeters = 0.08,
    this.maxRangeMeters = 10.0,
    this.speakerMicBaselineMeters = 0.074,
  });

  /// Straight-line distance from the speaker to the microphone.
  ///
  /// t=0 is taken from the direct breakthrough, but that path is not
  /// zero-length — it is the few centimetres across the phone body. An echo
  /// from a surface at `d` therefore arrives `(2d - baseline)/c` after the
  /// breakthrough rather than `2d/c`, so halving the measured delay
  /// under-reports every distance by `baseline/2`, at every range equally.
  ///
  /// Measured on an Infinix X657C: a tape-measured 0.15m target read 0.113m,
  /// a 0.037m shortfall implying a ~0.074m baseline. This is per-device
  /// geometry — a handset with different speaker/mic placement needs a
  /// different value, which is why it is a parameter rather than a constant.
  final double speakerMicBaselineMeters;

  final double speedOfSoundMps;

  /// Minimum peak-to-noise-floor ratio to accept a reading, where the floor
  /// is the MEDIAN of the search window (see [_bestEcho]). A peak only
  /// barely above the floor is a false lock, not a wall.
  ///
  /// Calibrated against a measured on-device envelope (Infinix X657C, 4
  /// pulses, wall at a tape-measured 1m): the real echo stood at 10-12x the
  /// median floor, quiet far-field bins at 1.2-2.8x, and the loudest
  /// non-echo bins ~6x. Pure Gaussian noise over a window this size tops out
  /// near 5.9x by chance. 8.0 sits in the gap.
  final double noiseGateRatio;

  /// Echoes closer than this aren't searched — see the constructor comment
  /// for the measured speaker-ringing tail this guards against.
  final double minRangeMeters;

  /// Echoes beyond this round-trip range aren't searched — bounds the echo
  /// window (relative to the breakthrough) to physically plausible indoor
  /// distances.
  final double maxRangeMeters;

  /// Returns `null` when no confident echo is found (no clamping to a
  /// fallback distance — callers should treat that as "out of range").
  ToFResult? calculate({
    required Float64List correlation,
    required int sampleRate,
    int pulseCount = 1,
    int pulseSpacingSamples = 0,
    Float64List? clutterProfile,
  }) {
    final peak = _bestEcho(
      correlation: correlation,
      sampleRate: sampleRate,
      pulseCount: pulseCount,
      pulseSpacingSamples: pulseSpacingSamples,
      clutterProfile: clutterProfile,
    );
    if (peak == null || peak.atGuardEdge) return null;
    if (peak.noiseFloor == 0) return null;
    if (peak.value < noiseGateRatio * peak.noiseFloor) return null;

    return ToFResult(
      distanceMeters: peak.distanceMeters(
        speedOfSoundMps,
        sampleRate,
        speakerMicBaselineMeters,
      ),
      peakToNoiseRatio: peak.value / peak.noiseFloor,
    );
  }

  /// Breakthrough indices the averaging aligned on — diagnostic only, so a
  /// device log can confirm the pulses were found at their true spacing
  /// rather than on one pulse's reverberation.
  List<int> debugAnchors({
    required Float64List correlation,
    required int pulseCount,
    required int pulseSpacingSamples,
  }) {
    if (correlation.isEmpty) return const [];
    return _deriveAnchors(
      correlation: correlation,
      pulseCount: pulseCount,
      pulseSpacingSamples: pulseSpacingSamples,
    );
  }

  /// Same search as [calculate] but ignores the noise gate and the guard-edge
  /// rejection — for on-device calibration logging only, so a rejected
  /// reading still shows what the best in-range candidate actually was
  /// (peak/noise ratio, distance), to tell "gate too strict" apart from
  /// "genuinely nothing there".
  ToFResult? debugBestPeak({
    required Float64List correlation,
    required int sampleRate,
    int pulseCount = 1,
    int pulseSpacingSamples = 0,
    Float64List? clutterProfile,
  }) {
    final peak = _bestEcho(
      correlation: correlation,
      sampleRate: sampleRate,
      pulseCount: pulseCount,
      pulseSpacingSamples: pulseSpacingSamples,
      clutterProfile: clutterProfile,
    );
    if (peak == null || peak.noiseFloor == 0) return null;

    return ToFResult(
      distanceMeters: peak.distanceMeters(
        speedOfSoundMps,
        sampleRate,
        speakerMicBaselineMeters,
      ),
      peakToNoiseRatio: peak.value / peak.noiseFloor,
    );
  }

  /// Calibration-only: the peak/noise ratio right around the delay (relative
  /// to the breakthrough anchor) that [knownDistanceMeters] implies,
  /// regardless of whether it's the global best candidate. Answers "is there
  /// any real correlate at the distance I actually measured with a tape,
  /// even a weak one" — separate from whatever else in the window happens
  /// to be louder.
  double? debugRatioAtKnownDistance({
    required Float64List correlation,
    required int sampleRate,
    required double knownDistanceMeters,
    int pulseCount = 1,
    int pulseSpacingSamples = 0,
    Float64List? clutterProfile,
  }) {
    final peak = _bestEcho(
      correlation: correlation,
      sampleRate: sampleRate,
      pulseCount: pulseCount,
      pulseSpacingSamples: pulseSpacingSamples,
      clutterProfile: clutterProfile,
    );
    if (peak == null || peak.noiseFloor == 0) return null;

    final targetDelay =
        (2 * knownDistanceMeters / speedOfSoundMps * sampleRate).round();

    var localPeak = 0.0;
    for (var i = targetDelay - 3; i <= targetDelay + 3; i++) {
      if (i < 0 || i >= peak.envelope.length) continue;
      final value = peak.envelope[i];
      if (value > localPeak) localPeak = value;
    }
    return localPeak / peak.noiseFloor;
  }

  /// Pulse-averaged envelope scaled so the breakthrough is exactly 1.0 —
  /// this device's fixed acoustic signature, for use as [clutterProfile].
  ///
  /// Capture it with nothing in front of the phone: what it records is the
  /// speaker's ringing and the phone body's own reflections, which are the
  /// same on every ping. Scaling by the breakthrough is what lets it stay
  /// valid as playback level drifts between measurements.
  Float64List? buildClutterProfile({
    required Float64List correlation,
    required int sampleRate,
    int pulseCount = 1,
    int pulseSpacingSamples = 0,
  }) {
    final envelope = _buildEnvelope(
      correlation: correlation,
      sampleRate: sampleRate,
      pulseCount: pulseCount,
      pulseSpacingSamples: pulseSpacingSamples,
    );
    if (envelope == null || envelope[0] == 0) return null;

    final breakthrough = envelope[0];
    final profile = Float64List(envelope.length);
    for (var d = 0; d < envelope.length; d++) {
      profile[d] = envelope[d] / breakthrough;
    }
    return profile;
  }

  /// Pulse-averaged |correlation| envelope, aligned at each pulse's own
  /// breakthrough. Index = delay in samples after t=0, so `envelope[0]` is
  /// the breakthrough magnitude itself.
  Float64List? _buildEnvelope({
    required Float64List correlation,
    required int sampleRate,
    required int pulseCount,
    required int pulseSpacingSamples,
  }) {
    if (correlation.isEmpty || pulseCount < 1) return null;

    final maxDelaySamples =
        (2 * maxRangeMeters / speedOfSoundMps * sampleRate).round();

    final anchors = _deriveAnchors(
      correlation: correlation,
      pulseCount: pulseCount,
      pulseSpacingSamples: pulseSpacingSamples,
    );
    if (anchors.isEmpty) return null;

    final envelope = Float64List(maxDelaySamples + 1);
    for (var d = 0; d <= maxDelaySamples; d++) {
      var sum = 0.0;
      var contributors = 0;
      for (final anchor in anchors) {
        final i = anchor + d;
        if (i >= correlation.length) continue;
        sum += correlation[i].abs();
        contributors++;
      }
      envelope[d] = contributors == 0 ? 0 : sum / contributors;
    }
    return envelope;
  }

  _Echo? _bestEcho({
    required Float64List correlation,
    required int sampleRate,
    required int pulseCount,
    required int pulseSpacingSamples,
    Float64List? clutterProfile,
  }) {
    final envelope = _buildEnvelope(
      correlation: correlation,
      sampleRate: sampleRate,
      pulseCount: pulseCount,
      pulseSpacingSamples: pulseSpacingSamples,
    );
    if (envelope == null) return null;

    // Clutter subtraction: the device's own ringing and body reflections are
    // fixed, so a profile captured once (scaled to this ping's breakthrough)
    // can be removed, leaving only what the scene put there. This is what
    // makes near-field ranging possible at all — at 0.15m the echo lands
    // ~38 samples after t=0, deep inside a ringing tail that measured ~13x
    // the noise floor out to ~154 samples (0.6m equivalent). Without this
    // the peak search simply finds the ringing every time.
    if (clutterProfile != null && envelope[0] > 0) {
      final breakthrough = envelope[0];
      final shared = math.min(clutterProfile.length, envelope.length);
      for (var d = 0; d < shared; d++) {
        // Deliberately NOT clamped at zero. A negative residual means this
        // ping's clutter came in slightly under the reference, which is
        // exactly the run-to-run noise the gate needs to measure itself
        // against. Clamping discards it, and when cancellation is good most
        // of the window becomes exactly 0 — the median floor collapses to
        // zero and every reading is rejected as ungateable. Peak search
        // ignores negatives naturally, and the floor is taken from the
        // residual's magnitude below.
        envelope[d] = envelope[d] - clutterProfile[d] * breakthrough;
      }
    }

    final minDelaySamples =
        (2 * minRangeMeters / speedOfSoundMps * sampleRate).round();
    if (minDelaySamples >= envelope.length) return null;

    var peakIndex = minDelaySamples;
    var peakValue = envelope[minDelaySamples];
    for (var d = minDelaySamples; d < envelope.length; d++) {
      if (envelope[d] > peakValue) {
        peakValue = envelope[d];
        peakIndex = d;
      }
    }

    // Noise floor = MEDIAN of the search window, not its RMS. The window
    // legitimately contains echoes and room reverberation, and RMS counts
    // all of that as "noise" — on-device that inflated the floor ~2.6x and
    // scored a genuine 10-12x echo as a sub-gate 3.6-4.5x. The median is
    // unmoved by a minority of loud bins, so it tracks the true floor
    // whether or not an echo is present.
    // Magnitudes, and a copy rather than a view: sorting a view would
    // reorder [envelope] itself, which callers still read for the peak
    // refinement and the calibration probe. Magnitude matters because
    // clutter subtraction leaves signed residuals, and it is how far the
    // residual sits from zero — in either direction — that measures noise.
    final window = Float64List(envelope.length - minDelaySamples);
    for (var i = 0; i < window.length; i++) {
      window[i] = envelope[minDelaySamples + i].abs();
    }
    window.sort();
    final noiseFloor = window[window.length ~/ 2];

    final refinedDelay = _parabolicPeak(envelope, peakIndex);
    if (refinedDelay <= 0) return null;

    return _Echo(
      value: peakValue,
      delaySamples: refinedDelay,
      noiseFloor: noiseFloor,
      envelope: envelope,
      atGuardEdge: peakIndex == minDelaySamples,
    );
  }

  /// Breakthrough index for each pulse of an emitted train.
  ///
  /// The train is one sample-accurate buffer (see
  /// [ChirpGenerator.generateTrain]), so once any one breakthrough is known
  /// the rest sit at exact multiples of [pulseSpacingSamples] from it — they
  /// are derived, never searched for. Only the global maximum is located;
  /// which pulse of the train it belongs to is resolved by trying each
  /// alignment and keeping the one with the most total energy at the implied
  /// anchor positions.
  ///
  /// Searching for each anchor independently (strongest peaks with mutual
  /// exclusion) does NOT work: a single pulse's reverberation outruns the
  /// exclusion zone and gets adopted as another pulse's breakthrough, so the
  /// average is taken over positions that aren't aligned to anything.
  List<int> _deriveAnchors({
    required Float64List correlation,
    required int pulseCount,
    required int pulseSpacingSamples,
  }) {
    var globalMax = 0;
    var globalValue = correlation[0].abs();
    for (var i = 1; i < correlation.length; i++) {
      final value = correlation[i].abs();
      if (value > globalValue) {
        globalValue = value;
        globalMax = i;
      }
    }
    if (globalValue == 0) return const [];
    if (pulseCount <= 1 || pulseSpacingSamples <= 0) return [globalMax];

    var bestFirst = globalMax;
    var bestEnergy = -1.0;
    for (var k = 0; k < pulseCount; k++) {
      final first = globalMax - k * pulseSpacingSamples;
      if (first < 0) break;
      var energy = 0.0;
      for (var p = 0; p < pulseCount; p++) {
        final i = first + p * pulseSpacingSamples;
        if (i >= correlation.length) continue;
        energy += correlation[i].abs();
      }
      if (energy > bestEnergy) {
        bestEnergy = energy;
        bestFirst = first;
      }
    }

    final anchors = <int>[];
    for (var p = 0; p < pulseCount; p++) {
      final i = bestFirst + p * pulseSpacingSamples;
      if (i < correlation.length) anchors.add(i);
    }
    return anchors;
  }

  /// Sub-sample peak position via parabolic interpolation of the three
  /// samples around [peakIndex] — the correlation peak rarely lands exactly
  /// on a sample, and at 44.1 kHz one sample is ~7.8mm of round-trip range.
  double _parabolicPeak(Float64List data, int peakIndex) {
    if (peakIndex <= 0 || peakIndex >= data.length - 1) {
      return peakIndex.toDouble();
    }
    final left = data[peakIndex - 1].abs();
    final center = data[peakIndex].abs();
    final right = data[peakIndex + 1].abs();
    final denominator = left - 2 * center + right;
    if (denominator == 0) return peakIndex.toDouble();
    final offset = 0.5 * (left - right) / denominator;
    return peakIndex + offset;
  }
}

class _Echo {
  const _Echo({
    required this.value,
    required this.delaySamples,
    required this.noiseFloor,
    required this.envelope,
    required this.atGuardEdge,
  });

  /// True when the winning peak sat exactly on [ToFCalculator.minRangeMeters].
  /// That's the shoulder of the speaker's decaying ringing tail, not an echo:
  /// the tail falls monotonically through the guard, so its maximum inside
  /// the window is always the very first sample. Measured on-device as
  /// readings pinned to the guard distance (0.598m against a 0.6m guard)
  /// while the genuine wall echo sat further out. A real echo peaks in the
  /// window's interior.
  final bool atGuardEdge;

  final double value;
  final double delaySamples;

  /// Median of the search window — a robust estimate of the correlation
  /// noise floor that real echoes in the window don't inflate.
  final double noiseFloor;

  /// Pulse-averaged |correlation| envelope; index = delay in samples after
  /// the breakthrough (t=0).
  final Float64List envelope;

  double distanceMeters(
    double speedOfSoundMps,
    int sampleRate,
    double speakerMicBaselineMeters,
  ) {
    final delaySeconds = delaySamples / sampleRate;
    // Round trip: the chirp travels to the surface and back. The breakthrough
    // that t=0 comes from already covered the speaker-to-mic baseline, so add
    // it back before halving (see ToFCalculator.speakerMicBaselineMeters).
    return (speedOfSoundMps * delaySeconds + speakerMicBaselineMeters) / 2;
  }
}
