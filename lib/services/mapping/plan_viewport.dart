import 'package:equatable/equatable.dart';

import 'map_node.dart';

/// Maps metres on a floor plane onto pixels on a canvas.
///
/// Split out of the painter and kept free of `dart:ui` so it can be unit
/// tested: a graph carries arbitrary extent around an arbitrary origin, and
/// getting this wrong renders everything off-screen with nothing to see and no
/// clue why. It is the one part of the map worth testing without a device.
class PlanViewport extends Equatable {
  const PlanViewport({
    required this.scale,
    required this.originX,
    required this.originY,
  });

  /// The zoom cap for a plan whose coordinates are metres.
  ///
  /// It stops a two-node plan from being blown up until a 7 m corridor fills a
  /// phone screen — past a point, zooming in stops adding information and just
  /// looks broken.
  static const double maxPixelsPerMetre = 22;

  /// How wide a floor a plan with no declared scale is assumed to be.
  ///
  /// A traced plan is unitless: one unit is the width of the photographed
  /// board, and nobody was asked what that is in metres. Some figure is needed
  /// to turn [maxPixelsPerMetre] into a cap, and a board on a wall almost
  /// always shows a whole floor, so a floor's width is the honest guess. It
  /// only ever bounds the zoom — it never reaches a spoken distance, which
  /// stays suppressed until somebody sets a real scale.
  static const double assumedFloorMetres = 50;

  /// The zoom cap in **plan units**, which is what [fitPoints] wants.
  ///
  /// Pass a plan's `metresPerUnit`, or null when it has no scale.
  ///
  /// This exists because the cap used to be a bare `maxScale = 22` default,
  /// which is pixels per *metre* — correct for a captured plan and wrong by a
  /// factor of about fifty for a traced one. A traced floor rendered as a
  /// nine-pixel smudge in the middle of an empty sheet, with no error and
  /// nothing to suggest the scale was the problem.
  static double maxScaleFor(double? metresPerUnit) =>
      maxPixelsPerMetre * (metresPerUnit ?? assumedFloorMetres);

  /// Fits every node in [nodes] inside a [width] × [height] canvas.
  ///
  /// [maxScale] is in pixels per plan unit and is required, not defaulted:
  /// see [maxScaleFor].
  factory PlanViewport.fit(
    Iterable<MapNode> nodes, {
    required double width,
    required double height,
    required double maxScale,
    double padding = 32,
  }) => PlanViewport.fitPoints(
    [for (final node in nodes) (x: node.x, y: node.y)],
    width: width,
    height: height,
    padding: padding,
    maxScale: maxScale,
  );

  /// [fit] for any plan coordinates, not only landmarks.
  ///
  /// Room polygons are fitted by their corners rather than their centres — a
  /// plan scaled to fit the middles of its rooms crops half of every room at
  /// the edge of the floor. Kept as a record rather than an `Offset` so this
  /// file stays free of `dart:ui` and unit-testable, which is the whole reason
  /// it was split out of the painter.
  factory PlanViewport.fitPoints(
    Iterable<({double x, double y})> points, {
    required double width,
    required double height,
    required double maxScale,
    double padding = 32,
  }) {
    final usableWidth = width - padding * 2;
    final usableHeight = height - padding * 2;

    if (points.isEmpty || usableWidth <= 0 || usableHeight <= 0) {
      return PlanViewport(
        scale: maxScale,
        originX: width / 2,
        originY: height / 2,
      );
    }

    var minX = double.infinity;
    var maxX = double.negativeInfinity;
    var minY = double.infinity;
    var maxY = double.negativeInfinity;

    for (final point in points) {
      if (point.x < minX) minX = point.x;
      if (point.x > maxX) maxX = point.x;
      if (point.y < minY) minY = point.y;
      if (point.y > maxY) maxY = point.y;
    }

    final spanX = maxX - minX;
    final spanY = maxY - minY;

    // A corridor is often a straight line — zero extent across. Whichever axis
    // has extent decides the scale; a single node falls through to maxScale.
    var scale = maxScale;
    if (spanX > 0.001 && spanY > 0.001) {
      scale = _min(usableWidth / spanX, usableHeight / spanY);
    } else if (spanX > 0.001) {
      scale = usableWidth / spanX;
    } else if (spanY > 0.001) {
      scale = usableHeight / spanY;
    }
    if (scale > maxScale) scale = maxScale;

    final centreX = (minX + maxX) / 2;
    final centreY = (minY + maxY) / 2;

    return PlanViewport(
      scale: scale,
      originX: width / 2 - centreX * scale,
      originY: height / 2 + centreY * scale,
    );
  }

  /// Pixels per metre.
  final double scale;

  /// Canvas position, in pixels, of the metre origin.
  final double originX;
  final double originY;

  double toCanvasX(double metresX) => originX + metresX * scale;

  /// Flipped: +y is north in metres and downwards in pixels. Without this the
  /// plan renders mirrored, which is subtle enough to ship unnoticed and
  /// useless to anybody comparing it against the building.
  double toCanvasY(double metresY) => originY - metresY * scale;

  @override
  List<Object?> get props => [scale, originX, originY];

  static double _min(double a, double b) => a < b ? a : b;
}
