import 'reverb_features.dart';
import 'room_classification.dart';

/// Names a space type from its reverberation, for M5.
///
/// Deliberately a rule-based classifier over physically meaningful
/// quantities, not a learned model. The build plan flags the TFLite route's
/// cost — *"needs reverb training samples per room type; keep scope small"* —
/// and thresholds on RT60 buy most of the separation for none of that data
/// collection. It is also explicable: every decision here can be defended
/// from room acoustics, which a small neural net trained on a handful of
/// samples cannot be.
///
/// The thresholds below start from published typical values (Sabine's
/// relation ties RT60 to volume and absorption, so room classes really do
/// separate along it). They are constructor parameters precisely because they
/// are STARTING points: M10's evaluation should re-fit them against measured
/// rooms, and a learned classifier can replace this wholesale later without
/// disturbing anything upstream.
class RoomClassifier {
  const RoomClassifier({
    this.smallRoomMaxRt60 = 0.6,
    this.hallMinRt60 = 1.2,
    this.maxDiffuseRatio = 0.8,
    this.minCorridorRt60 = 0.4,
  });

  /// At or below this RT60, a space is small and well absorbing — a
  /// furnished office or classroom typically measures 0.3-0.6s.
  final double smallRoomMaxRt60;

  /// At or above this RT60, the volume is large and lightly absorbing — a
  /// lecture theatre or atrium typically measures 1.2-2.5s.
  final double hallMinRt60;

  /// EDT/RT60 below this marks a NON-DIFFUSE space, which is the acoustic
  /// signature of a corridor.
  ///
  /// In a diffuse room, energy arrives from all directions and decays at one
  /// rate throughout, so early and late decay agree and the ratio sits near
  /// 1.0. A corridor is not diffuse: its hard parallel walls return strong
  /// early reflections that die away quickly, while sound trapped along the
  /// length lingers. Early decay therefore outruns late decay and the ratio
  /// drops. This is what separates a corridor from a room of similar RT60 —
  /// the shape of the decay rather than its duration.
  final double maxDiffuseRatio;

  /// Below this RT60 a space is too dead to be a corridor whatever its decay
  /// shape, so the ratio test is not applied. Guards against a small, heavily
  /// furnished room being called a corridor on ratio alone.
  final double minCorridorRt60;

  /// Classifies [features], or returns [RoomType.unknown] when the evidence
  /// does not support a call.
  RoomClassification classify(ReverbFeatures? features) {
    if (features == null) {
      return const RoomClassification(
        type: RoomType.unknown,
        confidence: 0,
        features: null,
        reason: 'no usable reverberation measurement',
      );
    }
    if (!features.isReliable) {
      return RoomClassification(
        type: RoomType.unknown,
        confidence: 0,
        features: features,
        reason: 'measurement not reliable '
            '(fit ${features.fitQuality.toStringAsFixed(2)}, '
            '${features.decayRangeDb.toStringAsFixed(1)}dB of decay)',
      );
    }

    final rt60 = features.rt60Seconds;
    final ratio = rt60 <= 0 ? 1.0 : features.earlyDecayTimeSeconds / rt60;

    // Decay SHAPE is tested first. A corridor can share an RT60 with a room,
    // so duration alone cannot separate them; a markedly non-diffuse decay
    // can only come from strongly directional geometry.
    if (rt60 >= minCorridorRt60 && ratio < maxDiffuseRatio) {
      return RoomClassification(
        type: RoomType.corridor,
        confidence: _confidence(maxDiffuseRatio - ratio, maxDiffuseRatio),
        features: features,
        reason: 'non-diffuse decay (EDT/RT60 ${ratio.toStringAsFixed(2)}) — '
            'strong early reflections off parallel surfaces',
      );
    }

    if (rt60 <= smallRoomMaxRt60) {
      return RoomClassification(
        type: RoomType.smallRoom,
        confidence: _confidence(smallRoomMaxRt60 - rt60, smallRoomMaxRt60),
        features: features,
        reason: 'short decay (RT60 ${rt60.toStringAsFixed(2)}s) — '
            'small, absorbing space',
      );
    }

    if (rt60 >= hallMinRt60) {
      return RoomClassification(
        type: RoomType.hall,
        confidence: _confidence(rt60 - hallMinRt60, hallMinRt60),
        features: features,
        reason: 'long decay (RT60 ${rt60.toStringAsFixed(2)}s) — '
            'large, lightly absorbing volume',
      );
    }

    // Between the classes with a diffuse decay: a big room or a small hall.
    // Genuinely ambiguous, so say so.
    return RoomClassification(
      type: RoomType.unknown,
      confidence: 0,
      features: features,
      reason: 'RT60 ${rt60.toStringAsFixed(2)}s falls between '
          'small-room and hall, with no corridor signature',
    );
  }

  /// Maps distance past a threshold onto 0..1, saturating at [scale].
  ///
  /// Deliberately blunt: it conveys "just over the line" versus "well inside
  /// the class", and should not be read as a probability.
  double _confidence(double margin, double scale) {
    if (scale <= 0) return 0;
    return (margin / scale).clamp(0.0, 1.0) * 0.5 + 0.5;
  }
}
