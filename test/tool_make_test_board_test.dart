import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Generates a synthetic wall board to trace against.
///
/// Not a test — a generator, run as one because `flutter test` is the shortest
/// route to a canvas that can write a PNG. Produces a floor plan drawn as a
/// real board would be, then **deliberately keystoned**, so the perspective
/// correction has something genuine to undo and the tracing flow can be
/// exercised end to end without anybody's personal photos.
///
///     flutter test test/tool_make_test_board_test.dart
///
/// The floor it draws is known, which is the point: the traced result can be
/// checked against it rather than against a guess.
void main() {
  test('write a keystoned test board to the scratchpad', () async {
    const width = 1000.0;
    const height = 700.0;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // Paper.
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, width, height),
      Paint()..color = const Color(0xFFF7F4EC),
    );

    final wall = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..color = const Color(0xFF1A1A1A);
    final fill = Paint()..color = const Color(0xFFE3E0D8);

    // No text labels: `flutter test` has no font loaded, so every string
    // renders as a row of solid boxes. The geometry is what is being exercised.
    void room(double l, double t, double r, double b) {
      final rect = Rect.fromLTRB(l, t, r, b);
      canvas.drawRect(rect, fill);
      canvas.drawRect(rect, wall);
    }

    // A corridor across the middle with rooms either side — the shape door
    // counting is about. Four doors on the north wall, three on the south.
    room(80, 320, 920, 390);
    room(120, 120, 320, 320);
    room(340, 120, 540, 320);
    room(560, 120, 760, 320);
    room(780, 120, 920, 320);
    room(120, 390, 380, 600);
    room(400, 390, 660, 600);
    room(680, 390, 920, 600);

    // Door gaps, drawn as breaks in the corridor walls.
    final gap = Paint()
      ..color = const Color(0xFFF7F4EC)
      ..strokeWidth = 9
      ..style = PaintingStyle.stroke;
    for (final x in [220.0, 440.0, 660.0, 850.0]) {
      canvas.drawLine(Offset(x - 25, 320), Offset(x + 25, 320), gap);
    }
    for (final x in [250.0, 530.0, 800.0]) {
      canvas.drawLine(Offset(x - 25, 390), Offset(x + 25, 390), gap);
    }

    // A scale bar, so the scale step has something real to measure against:
    // this line is exactly 400 px on a 1000 px-wide plan, and stands for 10 m.
    canvas.drawLine(
      const Offset(120, 650),
      const Offset(520, 650),
      Paint()
        ..color = const Color(0xFF1A1A1A)
        ..strokeWidth = 5,
    );

    final plan = await recorder.endRecording().toImage(
      width.toInt(),
      height.toInt(),
    );

    // Now photograph it badly: paste the plan onto a larger canvas through a
    // keystone, the way a phone held below a wall board sees it.
    final outer = ui.PictureRecorder();
    final photo = Canvas(outer);
    const outW = 1600.0;
    const outH = 1200.0;
    photo.drawRect(
      const Rect.fromLTWH(0, 0, outW, outH),
      Paint()..color = const Color(0xFF2A2622),
    );

    // A gentle keystone — the top edge narrower than the bottom, as a phone
    // held below a wall board sees it. About 14% at the far edge, which is a
    // realistic hand-held angle rather than a caricature.
    photo.save();
    photo.translate(300, 250);
    photo.transform((Matrix4.identity()..setEntry(3, 1, -0.00018)).storage);
    photo.drawImage(plan, Offset.zero, Paint());
    photo.restore();

    final image = await outer.endRecording().toImage(
      outW.toInt(),
      outH.toInt(),
    );
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);

    final file = File('build/test_wall_board.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());

    expect(await file.length(), greaterThan(1000));
    // ignore: avoid_print
    print('wrote ${file.absolute.path}');
  });
}
