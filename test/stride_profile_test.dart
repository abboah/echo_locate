import 'package:echo_locate/services/motion/stride_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('calibration walk', () {
    test('a measured walk gives the step length', () {
      // The spec's calibration: pace out 10 m, count the steps.
      final stride = StrideProfile.fromWalk(distanceM: 10, steps: 14);

      expect(stride.metres, closeTo(0.714, 0.001));
      expect(stride.source, StrideSource.calibrated);
      expect(stride.isPlausible, isTrue);
    });

    test('a walk nobody actually did is not believed', () {
      // Tapping "done" without walking, or the counter never starting.
      expect(StrideProfile.fromWalk(distanceM: 10, steps: 0).isPlausible,
          isFalse);
      expect(StrideProfile.fromWalk(distanceM: 0, steps: 14).isPlausible,
          isFalse);
    });

    test('an implausible result is rejected rather than stored', () {
      // Two steps over 10 m means the counter missed most of them. Adopting
      // 5 m per step would tell the user to take 3 steps down a corridor.
      expect(
        StrideProfile.fromWalk(distanceM: 10, steps: 2).isPlausible,
        isFalse,
      );
    });
  });

  group('height fallback', () {
    test('estimates from height when calibration is skipped', () {
      final stride = StrideProfile.fromHeight(1.7);

      expect(stride.metres, closeTo(0.7055, 0.0001));
      expect(stride.source, StrideSource.height);
      expect(stride.isPlausible, isTrue);
    });

    test('the last-resort default is itself usable', () {
      // Used when the user gives neither a walk nor a height. It must never be
      // the thing that makes guidance implausible.
      expect(StrideProfile.fallback.isPlausible, isTrue);
      expect(StrideProfile.fallback.source, StrideSource.assumed);
    });
  });

  group('converting a leg for this user', () {
    test('metres become the number of steps to expect', () {
      const stride = StrideProfile(metres: 0.7, source: StrideSource.calibrated);

      // 25 m of corridor at 0.7 m per step.
      expect(stride.stepsFor(25), 36);
    });

    test('a contributor and a user do not share a step count', () {
      // The one modelling rule in the spec, made executable: the same stored
      // 20 m leg is a different number of steps for different people.
      const tall = StrideProfile(metres: 0.78, source: StrideSource.calibrated);
      const short = StrideProfile(metres: 0.65, source: StrideSource.calibrated);

      expect(tall.stepsFor(20), isNot(short.stepsFor(20)));
      expect(tall.stepsFor(20), 26);
      expect(short.stepsFor(20), 31);
    });
  });

  group('persistence', () {
    test('round-trips through json', () {
      final stride = StrideProfile.fromWalk(distanceM: 10, steps: 14);

      expect(StrideProfile.fromJson(stride.toJson()), stride);
    });

    test('a malformed or implausible stored value is discarded', () {
      expect(StrideProfile.fromJson(null), isNull);
      expect(StrideProfile.fromJson('0.7'), isNull);
      expect(StrideProfile.fromJson({'metres': 5.0, 'source': 'calibrated'}),
          isNull);
      expect(StrideProfile.fromJson({'metres': -0.7, 'source': 'calibrated'}),
          isNull);
    });

    test('an unknown source does not lose the measurement', () {
      // Forward compatibility: a newer build writing a source this one does
      // not know should not throw away a perfectly good stride.
      final restored =
          StrideProfile.fromJson({'metres': 0.72, 'source': 'lidar'});

      expect(restored?.metres, 0.72);
      expect(restored?.source, StrideSource.assumed);
    });
  });
}
