import 'package:echo_locate/core/models/landmark.dart';
import 'package:echo_locate/services/sensing/landmark_matcher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Landmark landmark(
    String labelText, {
    String id = 'l1',
    List<String> aliases = const [],
  }) =>
      Landmark(
        id: id,
        buildingId: 'knust-library',
        floorId: 'f1',
        kind: LandmarkKind.door,
        labelText: labelText,
        displayName: 'Room $labelText',
        aliases: aliases,
      );

  const matcher = LandmarkMatcher();

  group('a clean read', () {
    test('exact text matches', () {
      expect(matcher.matches('204', landmark('204')), isTrue);
    });

    test('case and spacing from OCR do not matter', () {
      // ML Kit returns whatever the sign renders: padded, mixed case, and
      // sometimes broken across a line.
      expect(
        matcher.matches('  reading   hall  ', landmark('READING HALL')),
        isTrue,
      );
    });
  });

  group('known misreads', () {
    test('a recorded alias matches', () {
      expect(
        matcher.matches('2O4', landmark('204', aliases: ['2O4'])),
        isTrue,
      );
    });

    test('letter-for-digit confusion matches without being recorded', () {
      // The whole point of fuzzy matching: contributors cannot enumerate every
      // misread, and O-for-0 is the most common one on door plates.
      expect(matcher.matches('2O4', landmark('204')), isTrue);
      expect(matcher.matches('2Ol', landmark('201')), isTrue);
    });

    test('a spurious space matches', () {
      // '2 04' — OCR splitting one plate into two blocks.
      expect(matcher.matches('2 04', landmark('204')), isTrue);
    });
  });

  group('the room next door', () {
    test('a different number never matches, though it is one edit away', () {
      // THE safety case. '204' and '205' are Levenshtein distance 1, so the
      // spec's plain "distance <= 1" rule would walk a blind user to the wrong
      // door with full confidence. Digit substitutions are not confusions.
      expect(matcher.matches('205', landmark('204')), isFalse);
      expect(matcher.matches('209', landmark('204')), isFalse);
    });

    test('a dropped digit does not match', () {
      expect(matcher.matches('20', landmark('204')), isFalse);
    });

    test('unrelated signage does not match', () {
      expect(matcher.matches('FIRE EXIT', landmark('204')), isFalse);
    });
  });

  group('choosing among the landmarks on a floor', () {
    test('picks the one that matches', () {
      final candidates = [
        landmark('204', id: 'a'),
        landmark('205', id: 'b'),
        landmark('READING HALL', id: 'c'),
      ];

      expect(matcher.match('205', candidates)?.id, 'b');
      expect(matcher.match('reading hall', candidates)?.id, 'c');
    });

    test('an exact hit wins over a fuzzy one', () {
      // 'l0l' is a confusable read of '101', but '1O1' is also a recorded
      // alias of '101'. Whichever way it resolves, an exactly-matching
      // landmark must never lose to a merely plausible one.
      final candidates = [
        landmark('1O1', id: 'fuzzy'),
        landmark('101', id: 'exact'),
      ];

      expect(matcher.match('101', candidates)?.id, 'exact');
    });

    test('an ambiguous read is refused rather than guessed', () {
      // Two landmarks a single confusion apart. Saying nothing sends the user
      // into the recovery sweep; guessing sends them through the wrong door.
      final candidates = [
        landmark('1O1', id: 'a'),
        landmark('101', id: 'b'),
      ];

      expect(matcher.match('1Ol', candidates), isNull);
    });

    test('no candidate matches an unknown sign', () {
      expect(matcher.match('CANTEEN', [landmark('204')]), isNull);
    });
  });

  group('tolerance is a parameter', () {
    test('confusions can be switched off for evaluation', () {
      // §10 measures the read envelope; comparing strict against fuzzy needs
      // both to be reachable from a test.
      const strict = LandmarkMatcher(allowConfusions: false);

      expect(strict.matches('2O4', landmark('204')), isFalse);
      expect(strict.matches('204', landmark('204')), isTrue);
      expect(
        strict.matches('2O4', landmark('204', aliases: ['2O4'])),
        isTrue,
      );
    });
  });
}
