import 'package:echo_locate/services/mapping/board_rectification.dart';
import 'package:flutter_test/flutter_test.dart';

/// A board photographed square on: the quad is already a rectangle.
const square = [
  Offset(0.1, 0.1),
  Offset(0.9, 0.1),
  Offset(0.9, 0.7),
  Offset(0.1, 0.7),
];

/// The same board shot from below, so its far edge is shorter — the keystone
/// every hand-held photo of a wall has.
const keystoned = [
  Offset(0.25, 0.1),
  Offset(0.75, 0.1),
  Offset(0.90, 0.7),
  Offset(0.10, 0.7),
];

void main() {
  group('building the map', () {
    test('four corners give a homography', () {
      expect(Homography.fromBoardCorners(square), isNotNull);
      expect(Homography.fromBoardCorners(keystoned), isNotNull);
    });

    test('the board corners land on the rectangle corners', () {
      final h = Homography.fromBoardCorners(keystoned)!;

      // Top-left to the origin, top-right to x = 1. Whatever the photograph
      // did to them.
      expect(h.apply(keystoned[0]).dx, closeTo(0, 1e-6));
      expect(h.apply(keystoned[0]).dy, closeTo(0, 1e-6));
      expect(h.apply(keystoned[1]).dx, closeTo(1, 1e-6));
      expect(h.apply(keystoned[1]).dy, closeTo(0, 1e-6));
    });

    test('the inverse puts them back where they were tapped', () {
      final h = Homography.fromBoardCorners(keystoned)!;

      // What the painter needs to draw a traced room over the photograph it
      // was traced from.
      for (final corner in keystoned) {
        final round = h.invert(h.apply(corner));
        expect((round - corner).distance, lessThan(1e-6));
      }
    });

    test('a degenerate quad is refused rather than inverted', () {
      // Three corners in a line. The matrix is singular and the only safe
      // answer is to carry on unrectified.
      expect(
        Homography.fromBoardCorners(const [
          Offset(0, 0),
          Offset(1, 0),
          Offset(2, 0),
          Offset(0, 1),
        ]),
        isNull,
      );
    });

    test('two corners tapped on the same point is refused', () {
      expect(
        Homography.fromBoardCorners(const [
          Offset(0.1, 0.1),
          Offset(0.1, 0.1),
          Offset(0.9, 0.7),
          Offset(0.1, 0.7),
        ]),
        isNull,
      );
    });

    test('the wrong number of corners is refused', () {
      expect(Homography.fromBoardCorners(const [Offset.zero]), isNull);
    });
  });

  group('what the correction actually buys', () {
    test('a keystoned rectangle comes out rectangular', () {
      final h = Homography.fromBoardCorners(keystoned)!;

      // Start from a room that really is a rectangle on the board, project it
      // onto the photograph the way the camera did, and correct it back. Going
      // this way round exercises the actual projective model — laying points
      // out by interpolating inside the quad would be testing bilinear
      // interpolation, which is not what a lens does.
      const roomOnBoard = [
        Offset(0.2, 0.15),
        Offset(0.6, 0.15),
        Offset(0.6, 0.45),
        Offset(0.2, 0.45),
      ];

      final asPhotographed = [for (final p in roomOnBoard) h.invert(p)];
      final corrected = [for (final p in asPhotographed) h.apply(p)];

      for (var i = 0; i < 4; i++) {
        expect((corrected[i] - roomOnBoard[i]).distance, lessThan(1e-9));
      }

      // And the photographed version was genuinely not a rectangle, so the
      // correction is doing something rather than nothing.
      final photoTop = (asPhotographed[1] - asPhotographed[0]).distance;
      final photoBottom = (asPhotographed[2] - asPhotographed[3]).distance;
      expect(photoTop, isNot(closeTo(photoBottom, 1e-3)));
    });

    test('a square-on photo is very nearly a no-op', () {
      final h = Homography.fromBoardCorners(square)!;
      final centre = h.apply(const Offset(0.5, 0.4));

      // Dead centre of the board maps to the middle of board space.
      expect(centre.dx, closeTo(0.5, 1e-6));
    });
  });

  group('rejecting a mis-tap', () {
    test('corners tapped in order are sane', () {
      expect(Homography.isSaneQuad(square), isTrue);
      expect(Homography.isSaneQuad(keystoned), isTrue);
    });

    test('a bowtie is not', () {
      // Tapping the corners in the wrong order is the common mistake, and it
      // folds the plan over rather than merely distorting it.
      expect(
        Homography.isSaneQuad(const [
          Offset(0.1, 0.1),
          Offset(0.9, 0.7),
          Offset(0.9, 0.1),
          Offset(0.1, 0.7),
        ]),
        isFalse,
      );
    });

    test('three collinear corners are not', () {
      expect(
        Homography.isSaneQuad(const [
          Offset(0, 0),
          Offset(1, 0),
          Offset(2, 0),
          Offset(0, 1),
        ]),
        isFalse,
      );
    });
  });

  group('warning about an oblique photo', () {
    test('a square-on shot reports no skew', () {
      expect(Homography.skewDegreesOf(square), closeTo(0, 0.1));
    });

    test('a keystoned shot reports some', () {
      expect(Homography.skewDegreesOf(keystoned), greaterThan(0));
    });

    test('a badly oblique shot reports a lot', () {
      // Far edge half the length of the near one.
      const oblique = [
        Offset(0.1, 0.1),
        Offset(0.5, 0.1),
        Offset(0.9, 0.7),
        Offset(0.1, 0.7),
      ];

      expect(Homography.skewDegreesOf(oblique), greaterThan(20));
    });
  });

  group('the identity', () {
    test('changes nothing, for a plan with no board squared up', () {
      const point = Offset(0.3, 0.4);

      expect(Homography.identity.apply(point), point);
      expect(Homography.identity.invert(point), point);
      expect(Homography.identity.isIdentity, isTrue);
    });
  });
}
