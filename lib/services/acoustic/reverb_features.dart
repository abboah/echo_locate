import 'package:equatable/equatable.dart';

/// How long sound lingers in a space, measured from one impulse response.
///
/// These are the acoustic quantities that distinguish room types: a corridor,
/// a small office and a lecture hall differ far more in how long they ring
/// than in anything a single distance measurement can capture.
class ReverbFeatures extends Equatable {
  const ReverbFeatures({
    required this.rt60Seconds,
    required this.earlyDecayTimeSeconds,
    required this.fitQuality,
    required this.decayRangeDb,
  });

  /// Reverberation time: how long the sound field takes to fall by 60dB.
  ///
  /// Extrapolated from a shorter, more reliable stretch of the decay rather
  /// than measured over a full 60dB — see [ReverbAnalyzer]. Typical indoor
  /// values run from ~0.3s (small furnished room) to ~2s (bare hall).
  final double rt60Seconds;

  /// Early decay time: the same slope taken over only the first 10dB, scaled
  /// to 60dB.
  ///
  /// Carried alongside [rt60Seconds] because the two disagree in a
  /// diagnostic way. A corridor's early decay is dominated by strong parallel
  /// reflections and comes out much shorter than its late decay, whereas a
  /// diffuse room decays at one rate throughout. The RATIO is therefore a
  /// discriminator that neither value provides alone.
  final double earlyDecayTimeSeconds;

  /// r² of the straight-line fit to the decay curve, 0 to 1.
  ///
  /// A real decay in dB is close to linear in time. When this is low the
  /// "decay" was noise, a moving source, or a capture too short to contain
  /// one — so it gates whether the estimate is trustworthy at all.
  final double fitQuality;

  /// How many dB of genuine decay the fit actually spanned.
  ///
  /// An RT60 extrapolated from 8dB of usable decay is a far weaker claim than
  /// one from 25dB, and the two should not be presented alike.
  final double decayRangeDb;

  /// Whether this estimate is solid enough to classify a room from.
  ///
  /// Thresholds are deliberately loose: this separates "we measured a decay"
  /// from "we measured noise", and is not a quality grade.
  bool get isReliable => fitQuality >= 0.9 && decayRangeDb >= 10.0;

  @override
  List<Object?> get props => [
    rt60Seconds,
    earlyDecayTimeSeconds,
    fitQuality,
    decayRangeDb,
  ];

  @override
  String toString() =>
      'ReverbFeatures(rt60=${rt60Seconds.toStringAsFixed(3)}s '
      'edt=${earlyDecayTimeSeconds.toStringAsFixed(3)}s '
      'r2=${fitQuality.toStringAsFixed(3)} '
      'range=${decayRangeDb.toStringAsFixed(1)}dB)';
}
