import 'dart:math' as math;

import 'package:echo_locate/services/mapping/room_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

/// A 6x4 rectangle, counter-clockwise in the y-north frame.
final square = [
  const Offset(0, 0),
  const Offset(6, 0),
  const Offset(6, 4),
  const Offset(0, 4),
];

/// A thin L. Chosen because its *area centroid lands outside it* — the case
/// the floorplan spec's §10 assumes cannot happen.
final lShape = [
  const Offset(0, 0),
  const Offset(6, 0),
  const Offset(6, 1),
  const Offset(1, 1),
  const Offset(1, 6),
  const Offset(0, 6),
];

void main() {
  group('winding', () {
    test('counter-clockwise input has positive signed area', () {
      expect(signedArea(square), greaterThan(0));
    });

    test('clockwise input has negative signed area', () {
      expect(signedArea(square.reversed.toList()), lessThan(0));
    });

    test('normaliseWinding leaves counter-clockwise input alone', () {
      expect(normaliseWinding(square), equals(square));
    });

    test('normaliseWinding flips clockwise input', () {
      final clockwise = square.reversed.toList();
      final fixed = normaliseWinding(clockwise);

      expect(signedArea(fixed), greaterThan(0));
      expect(fixed, equals(square));
    });

    test('area is winding-independent', () {
      expect(areaOf(square), closeTo(24, 1e-9));
      expect(areaOf(square.reversed.toList()), closeTo(24, 1e-9));
    });
  });

  group('selfIntersects', () {
    test('a rectangle does not', () {
      expect(selfIntersects(square), isFalse);
    });

    test('an L does not', () {
      expect(selfIntersects(lShape), isFalse);
    });

    test('a bowtie does', () {
      // Opposite corners swapped — the classic figure-of-eight.
      final bowtie = [
        const Offset(0, 0),
        const Offset(6, 4),
        const Offset(6, 0),
        const Offset(0, 4),
      ];

      expect(selfIntersects(bowtie), isTrue);
    });

    test('a triangle cannot self-intersect', () {
      expect(
        selfIntersects([
          const Offset(0, 0),
          const Offset(4, 0),
          const Offset(2, 3),
        ]),
        isFalse,
      );
    });
  });

  group('containsPoint', () {
    test('finds a point inside', () {
      expect(containsPoint(square, const Offset(3, 2)), isTrue);
    });

    test('rejects a point outside', () {
      expect(containsPoint(square, const Offset(9, 2)), isFalse);
    });

    test('rejects a point in the notch of an L', () {
      expect(containsPoint(lShape, const Offset(4, 4)), isFalse);
    });
  });

  group('centroid and label placement', () {
    test('a rectangle centroid is its middle', () {
      final centre = areaCentroid(square);

      expect(centre.dx, closeTo(3, 1e-9));
      expect(centre.dy, closeTo(2, 1e-9));
    });

    test('the area centroid of a thin L falls OUTSIDE it', () {
      // Pinned deliberately: this is the assumption the spec makes and it is
      // wrong. If a future change makes this pass, interiorPoint's fallback
      // has stopped being exercised and the test below is no longer proving
      // anything.
      expect(containsPoint(lShape, areaCentroid(lShape)), isFalse);
    });

    test('interiorPoint lands inside a thin L anyway', () {
      expect(containsPoint(lShape, interiorPoint(lShape)), isTrue);
    });

    test('interiorPoint uses the centroid when the centroid is interior', () {
      expect(interiorPoint(square), equals(areaCentroid(square)));
    });

    test('interiorPoint lands inside a U-shape', () {
      final u = [
        const Offset(0, 0),
        const Offset(6, 0),
        const Offset(6, 5),
        const Offset(4, 5),
        const Offset(4, 2),
        const Offset(2, 2),
        const Offset(2, 5),
        const Offset(0, 5),
      ];

      expect(containsPoint(u, interiorPoint(u)), isTrue);
    });
  });

  group('handedness — the fixture the whole directions layer rests on', () {
    // Frame: +x east, +y north. Facing north is heading (0, 1).
    const facingNorth = Offset(0, 1);

    test('west is to the LEFT when facing north', () {
      const west = Offset(-1, 0);

      // Positive radians = left, by this file's stated convention.
      expect(signedTurnRad(facingNorth, west), closeTo(math.pi / 2, 1e-9));
      // Negative degrees = left, by the repo's right-is-positive convention.
      expect(turnDegreesRight(facingNorth, west), closeTo(-90, 1e-9));
    });

    test('east is to the RIGHT when facing north', () {
      const east = Offset(1, 0);

      expect(signedTurnRad(facingNorth, east), closeTo(-math.pi / 2, 1e-9));
      expect(turnDegreesRight(facingNorth, east), closeTo(90, 1e-9));
    });

    test('straight ahead is no turn', () {
      expect(
        turnDegreesRight(facingNorth, const Offset(0, 5)),
        closeTo(0, 1e-9),
      );
    });

    test('behind is a half turn', () {
      expect(
        turnDegreesRight(facingNorth, const Offset(0, -1)).abs(),
        closeTo(180, 1e-9),
      );
    });

    test('the sign survives a heading that is not axis-aligned', () {
      // Facing north-east; due north is now a left turn of 45 degrees.
      const northEast = Offset(1, 1);

      expect(
        turnDegreesRight(northEast, const Offset(0, 1)),
        closeTo(-45, 1e-9),
      );
      expect(
        turnDegreesRight(northEast, const Offset(1, 0)),
        closeTo(45, 1e-9),
      );
    });

    test('a degenerate vector turns nobody', () {
      expect(signedTurnRad(Offset.zero, const Offset(1, 0)), 0);
      expect(signedTurnRad(const Offset(1, 0), Offset.zero), 0);
    });
  });

  group('sideOfLine', () {
    test('agrees with the turn convention: negative is left', () {
      // Walking north from the origin.
      const from = Offset(0, 0);
      const to = Offset(0, 10);

      expect(sideOfLine(from, to, const Offset(-2, 5)), -1); // west = left
      expect(sideOfLine(from, to, const Offset(2, 5)), 1); // east = right
      expect(sideOfLine(from, to, const Offset(0, 5)), 0); // on the line
    });
  });

  group('projectOntoSegment', () {
    test('measures perpendicular distance and position along', () {
      final result = projectOntoSegment(
        const Offset(0, 0),
        const Offset(10, 0),
        const Offset(3, 2),
      );

      expect(result.distance, closeTo(2, 1e-9));
      expect(result.t, closeTo(0.3, 1e-9));
    });

    test('clamps past the ends rather than running to the infinite line', () {
      final result = projectOntoSegment(
        const Offset(0, 0),
        const Offset(10, 0),
        const Offset(-5, 0),
      );

      expect(result.t, 0);
      expect(result.distance, closeTo(5, 1e-9));
    });

    test('a zero-length segment measures to its own point', () {
      final result = projectOntoSegment(
        const Offset(2, 2),
        const Offset(2, 2),
        const Offset(2, 5),
      );

      expect(result.distance, closeTo(3, 1e-9));
    });
  });

  group('bounds and perimeter', () {
    test('bounds cover the polygon', () {
      final box = boundsOf(lShape);

      expect(box.left, 0);
      expect(box.top, 0);
      expect(box.right, 6);
      expect(box.bottom, 6);
    });

    test('perimeter closes the ring', () {
      expect(perimeterOf(square), closeTo(20, 1e-9));
    });
  });

  group('nearestEdgeDirection', () {
    // A door is a gap *along* its wall. Every opening used to be drawn
    // horizontally regardless, so one on a vertical wall was drawn straight
    // through it. These pin the bearing per wall of the same room.
    test('a door on the bottom wall runs horizontally', () {
      final d = nearestEdgeDirection(square, const Offset(3, 0));
      expect(d.dy.abs(), closeTo(0, 1e-9));
      expect(d.dx.abs(), closeTo(1, 1e-9));
    });

    test('a door on the right wall runs vertically', () {
      final d = nearestEdgeDirection(square, const Offset(6, 2));
      expect(d.dx.abs(), closeTo(0, 1e-9));
      expect(d.dy.abs(), closeTo(1, 1e-9));
    });

    test('it is a unit vector', () {
      expect(nearestEdgeDirection(square, const Offset(0, 3)).distance,
          closeTo(1, 1e-9));
    });

    test('the nearest edge wins, not the longest', () {
      // The L's long bottom run is 6 across; the short wall at x=6 is 1 tall.
      // A door placed on that short wall must take its bearing, or an L-shaped
      // room draws every one of its doors along the same axis.
      final d = nearestEdgeDirection(lShape, const Offset(6, 0.5));
      expect(d.dx.abs(), closeTo(0, 1e-9));
    });

    test('a degenerate polygon falls back to horizontal', () {
      expect(nearestEdgeDirection(const [Offset(1, 1)], const Offset(0, 0)),
          const Offset(1, 0));
    });
  });
}
