import 'package:flutter_test/flutter_test.dart';

import 'package:echo_locate/services/acoustic/reverb_features.dart';
import 'package:echo_locate/services/acoustic/room_classification.dart';
import 'package:echo_locate/services/acoustic/room_classifier.dart';

void main() {
  const classifier = RoomClassifier();

  ReverbFeatures features({
    required double rt60,
    double? edt,
    double fitQuality = 0.99,
    double decayRangeDb = 20.0,
  }) => ReverbFeatures(
    rt60Seconds: rt60,
    // Diffuse by default: early and late decay agree.
    earlyDecayTimeSeconds: edt ?? rt60,
    fitQuality: fitQuality,
    decayRangeDb: decayRangeDb,
  );

  group('classes', () {
    test('short diffuse decay is a small room', () {
      final result = classifier.classify(features(rt60: 0.4));
      expect(result.type, RoomType.smallRoom);
      expect(result.confidence, greaterThan(0.5));
    });

    test('long diffuse decay is a hall', () {
      final result = classifier.classify(features(rt60: 1.8));
      expect(result.type, RoomType.hall);
      expect(result.confidence, greaterThan(0.5));
    });

    test('non-diffuse decay is a corridor', () {
      // EDT well below RT60: early reflections die fast while sound trapped
      // along the length lingers.
      final result = classifier.classify(features(rt60: 0.9, edt: 0.5));
      expect(result.type, RoomType.corridor);
    });

    test('decay SHAPE separates a corridor from a room of equal RT60', () {
      // The reason the classifier tests shape before duration: these two
      // spaces ring for the same length of time and are different rooms.
      const rt60 = 0.9;
      final corridor = classifier.classify(features(rt60: rt60, edt: 0.5));
      final room = classifier.classify(features(rt60: rt60, edt: rt60));

      expect(corridor.type, RoomType.corridor);
      expect(room.type, isNot(RoomType.corridor));
    });

    test('a dead but uneven space is not called a corridor', () {
      // Below minCorridorRt60 the shape test is not applied: a small heavily
      // furnished room can decay unevenly without being a corridor.
      final result = classifier.classify(features(rt60: 0.3, edt: 0.15));
      expect(result.type, RoomType.smallRoom);
    });
  });

  group('refuses to guess', () {
    test('no measurement gives unknown', () {
      final result = classifier.classify(null);
      expect(result.type, RoomType.unknown);
      expect(result.confidence, 0);
      expect(result.features, isNull);
    });

    test('an unreliable measurement gives unknown, not a class', () {
      // A poor fit means the "decay" may not have been one. Classifying it
      // would put a confident room label on noise.
      final result = classifier.classify(features(rt60: 0.4, fitQuality: 0.5));
      expect(result.type, RoomType.unknown);
      expect(result.reason, contains('not reliable'));
    });

    test('too little decay to fit gives unknown', () {
      final result = classifier.classify(features(rt60: 1.5, decayRangeDb: 6));
      expect(result.type, RoomType.unknown);
    });

    test('a diffuse decay between classes gives unknown', () {
      // 0.9s diffuse: too live for a small room, too dead for a hall, and no
      // corridor signature. Saying so beats forcing a class.
      final result = classifier.classify(features(rt60: 0.9));
      expect(result.type, RoomType.unknown);
      expect(result.reason, contains('between'));
    });
  });

  group('confidence', () {
    test('rises with distance from the class boundary', () {
      final justInside = classifier.classify(features(rt60: 0.58));
      final wellInside = classifier.classify(features(rt60: 0.15));

      expect(justInside.type, RoomType.smallRoom);
      expect(wellInside.type, RoomType.smallRoom);
      expect(wellInside.confidence, greaterThan(justInside.confidence));
    });

    test('always carries the evidence it judged', () {
      final measured = features(rt60: 1.8);
      final result = classifier.classify(measured);
      expect(result.features, measured);
      expect(result.reason, isNotEmpty);
    });
  });
}
