// Undoing the angle a wall board was photographed at.
//
// ## The error this removes
//
// Nobody photographs a board square on. They stand where there is room to
// stand, hold the phone at chest height, and shoot at whatever angle the
// corridor allows. The result is **keystoned**: the far edge of the board is
// shorter than the near one, parallel corridors converge, and a rectangular
// room comes out as a trapezium.
//
// Tracing on that photo bakes the distortion into the plan. It is the largest
// systematic error in the whole tracing path and it is invisible — the traced
// rooms sit perfectly on the photo, because the photo is wrong in exactly the
// same way. Only comparing against the building reveals it.
//
// A homography undoes it. Four corners of the board, tapped once, define the
// projective map from photograph to plan, and every subsequent tap goes through
// it. No image processing: warping the *coordinates* is the same correction as
// warping the picture, for a fraction of the work.
//
// ## What it does not fix
//
// The aspect ratio is **estimated**, not recovered. Getting a rectangle's true
// proportions out of a perspective view needs the camera's focal length, which
// nothing here knows. The estimate below averages opposite edge lengths, which
// is close for a board shot roughly face-on and drifts as the angle grows.
//
// The residual is a uniform stretch along one axis — so a plan can come out
// slightly tall or slightly wide. Routing is unaffected (A* compares edges with
// each other) and so are door ordinals (they depend on order along a corridor,
// not on length). It shows up only in spoken distances, and then only if
// somebody has set a scale. For a prototype that is the right trade; the fix
// is calibrating the camera, which is a project of its own.

import 'dart:math' as math;
import 'dart:ui' show Offset;

/// A projective map between two planes, and its inverse.
///
/// Stored as the nine coefficients of a 3x3 matrix in row-major order, with
/// `h[8]` fixed at 1 — the scale of a homography is arbitrary, so eight numbers
/// determine it and the ninth is normalisation.
class Homography {
  const Homography(this._forward, this._inverse);

  final List<double> _forward;
  final List<double> _inverse;

  /// The identity — what to use before a board has been squared up.
  static const Homography identity = Homography(
    [1, 0, 0, 0, 1, 0, 0, 0, 1],
    [1, 0, 0, 0, 1, 0, 0, 0, 1],
  );

  bool get isIdentity =>
      _forward[0] == 1 && _forward[1] == 0 && _forward[2] == 0;

  /// Maps a point from the photograph into board space.
  Offset apply(Offset point) => _map(_forward, point);

  /// Maps a point from board space back onto the photograph — what the painter
  /// needs to draw a traced room over the picture it was traced from.
  Offset invert(Offset point) => _map(_inverse, point);

  static Offset _map(List<double> h, Offset p) {
    final w = h[6] * p.dx + h[7] * p.dy + h[8];
    // A point on the horizon maps to infinity. Returning it unchanged keeps a
    // pathological quad from producing NaN corners that poison every polygon
    // downstream.
    if (w.abs() < 1e-12) return p;
    return Offset(
      (h[0] * p.dx + h[1] * p.dy + h[2]) / w,
      (h[3] * p.dx + h[4] * p.dy + h[5]) / w,
    );
  }

  /// Builds the map that takes [quad] — the board's four corners as tapped on
  /// the photograph, clockwise from its top-left — onto an upright rectangle.
  ///
  /// Returns [identity] when the quad is degenerate: three corners in a line,
  /// or two tapped on top of each other. A bad quad is a mis-tap, and carrying
  /// on unrectified is far better than warping the plan through a singular
  /// matrix.
  static Homography? fromBoardCorners(List<Offset> quad) {
    if (quad.length != 4) return null;

    // Opposite edges averaged. See the header for why this is an estimate.
    final top = (quad[1] - quad[0]).distance;
    final bottom = (quad[2] - quad[3]).distance;
    final left = (quad[3] - quad[0]).distance;
    final right = (quad[2] - quad[1]).distance;

    final width = (top + bottom) / 2;
    final height = (left + right) / 2;
    if (width < 1e-6 || height < 1e-6) return null;

    // Board space: one unit wide, aspect tall, origin at the top-left corner.
    // Width rather than height, so the units stay comparable with the
    // fractions-of-image-width the rest of tracing already uses.
    final aspect = height / width;
    final target = [
      const Offset(0, 0),
      const Offset(1, 0),
      Offset(1, aspect),
      Offset(0, aspect),
    ];

    final forward = _solve(quad, target);
    if (forward == null) return null;
    final inverse = _solve(target, quad);
    if (inverse == null) return null;

    return Homography(forward, inverse);
  }

  /// Solves for the homography taking [from] to [to], four points each.
  ///
  /// Eight unknowns, eight equations — two per correspondence — by Gaussian
  /// elimination with partial pivoting. Small and direct: the alternative is a
  /// linear algebra dependency for one 8x8 solve.
  static List<double>? _solve(List<Offset> from, List<Offset> to) {
    final a = List.generate(8, (_) => List<double>.filled(9, 0));

    for (var i = 0; i < 4; i++) {
      final x = from[i].dx;
      final y = from[i].dy;
      final u = to[i].dx;
      final v = to[i].dy;

      a[i * 2] = [x, y, 1, 0, 0, 0, -u * x, -u * y, u];
      a[i * 2 + 1] = [0, 0, 0, x, y, 1, -v * x, -v * y, v];
    }

    for (var col = 0; col < 8; col++) {
      // Partial pivoting. Without it a quad with an axis-aligned edge — which
      // is most of them, since people square the phone up by instinct — puts a
      // zero on the diagonal and the solve divides by it.
      var pivot = col;
      for (var row = col + 1; row < 8; row++) {
        if (a[row][col].abs() > a[pivot][col].abs()) pivot = row;
      }
      if (a[pivot][col].abs() < 1e-12) return null;
      if (pivot != col) {
        final swap = a[pivot];
        a[pivot] = a[col];
        a[col] = swap;
      }

      final lead = a[col][col];
      for (var k = col; k < 9; k++) {
        a[col][k] /= lead;
      }
      for (var row = 0; row < 8; row++) {
        if (row == col) continue;
        final factor = a[row][col];
        if (factor == 0) continue;
        for (var k = col; k < 9; k++) {
          a[row][k] -= factor * a[col][k];
        }
      }
    }

    final h = [for (var i = 0; i < 8; i++) a[i][8], 1.0];
    return h.every((value) => value.isFinite) ? h : null;
  }

  /// Whether four tapped points make a sane board outline.
  ///
  /// Rejects a quad that crosses itself — tapping the corners in the wrong
  /// order is the common mis-tap, and it produces a map that folds the plan
  /// over on itself rather than one that merely distorts it.
  static bool isSaneQuad(List<Offset> quad) {
    if (quad.length != 4) return false;
    var sign = 0;
    for (var i = 0; i < 4; i++) {
      final a = quad[i];
      final b = quad[(i + 1) % 4];
      final c = quad[(i + 2) % 4];
      final cross =
          (b.dx - a.dx) * (c.dy - b.dy) - (b.dy - a.dy) * (c.dx - b.dx);
      if (cross.abs() < 1e-9) return false;
      final turn = cross > 0 ? 1 : -1;
      if (sign == 0) {
        sign = turn;
      } else if (turn != sign) {
        // A convex quadrilateral turns the same way at every corner.
        return false;
      }
    }
    return true;
  }

  /// How far from square the photograph was, in degrees, as a rough guide.
  ///
  /// Reported so a contributor can be told their photo is too oblique to
  /// rectify well — past about forty degrees the aspect estimate above stops
  /// being worth trusting and the honest advice is to take another picture.
  static double skewDegreesOf(List<Offset> quad) {
    if (quad.length != 4) return 0;

    // Both pairs. Shooting from the side converges the horizontal edges and
    // shooting from below converges the vertical ones — checking only one pair
    // reports a badly angled photo as perfectly square.
    final worst = math.max(
      _edgeRatio((quad[1] - quad[0]).distance, (quad[2] - quad[3]).distance),
      _edgeRatio((quad[3] - quad[0]).distance, (quad[2] - quad[1]).distance),
    );
    return math.min(90, (worst - 1) * 45);
  }

  /// Opposite edges of a rectangle photographed square on are equal; the ratio
  /// between them grows with the angle.
  static double _edgeRatio(double a, double b) {
    if (a < 1e-6 || b < 1e-6) return 1;
    return a > b ? a / b : b / a;
  }
}
