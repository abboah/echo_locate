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

  /// Fits every node in [nodes] inside a [width] × [height] canvas.
  ///
  /// [maxScale] stops a two-node plan from being blown up until a 7 m corridor
  /// fills a phone screen — past a point, zooming in stops adding information
  /// and just looks broken.
  factory PlanViewport.fit(
    Iterable<MapNode> nodes, {
    required double width,
    required double height,
    double padding = 32,
    double maxScale = 22,
  }) {
    final usableWidth = width - padding * 2;
    final usableHeight = height - padding * 2;

    if (nodes.isEmpty || usableWidth <= 0 || usableHeight <= 0) {
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

    for (final node in nodes) {
      if (node.x < minX) minX = node.x;
      if (node.x > maxX) maxX = node.x;
      if (node.y < minY) minY = node.y;
      if (node.y > maxY) maxY = node.y;
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
