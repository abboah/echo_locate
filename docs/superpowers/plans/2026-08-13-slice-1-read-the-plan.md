# Slice 1 — Read the Plan Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Photograph a posted floor plan and get back every piece of text on it, positioned in plan space, with a warning about any region glare has destroyed.

**Architecture:** Four small units, each testable on its own. `PlanHomography` is pure maths that maps a point in the photograph onto the deskewed unit square — we transform *coordinates*, never pixels, so there is no image warp to write or wait for. `GlareDetector` decodes the photo and reports which grid cells are blown out. `PlanOcrService` runs ML Kit over the still and returns text with bounding boxes. `PlanReadBloc` sequences them and a dev-only screen shows the result. Nothing touches the existing trace or navigation flows.

**Tech Stack:** Flutter, flutter_bloc, get_it, `google_mlkit_text_recognition` (already installed), `image` (new, pure Dart), `camera` via the existing `PlanPhotoService`.

**Spec:** `docs/superpowers/specs/2026-08-13-plan-reading-navigation-design.md`

**Fixture:** `test/fixtures/plans/college_of_science_ff.jpg` — a real board, photographed through gloss with window glare over the legend.

---

## Before you start

Work on a branch, not `main`:

```bash
git checkout -b slice-1-read-the-plan
```

## File structure

| File | Responsibility |
|---|---|
| `lib/services/mapping/plan_homography.dart` | Pure maths. Four photo corners → a transform from photo pixels to unit-square plan coordinates. No Flutter imports. |
| `lib/services/mapping/glare_detector.dart` | Decoded image → which grid cells are blown out. No Flutter imports. |
| `lib/services/mapping/plan_read.dart` | One piece of text found on a plan: its content, centre and size. Plain data. |
| `lib/services/mapping/plan_ocr_service.dart` | ML Kit wrapper. Still image file → `List<PlanRead>`. The only unit here that needs a device. |
| `lib/features/plan_read/bloc/plan_read_bloc.dart` | Sequences capture → glare → OCR. Owns screen state. |
| `lib/ui/pages/plan_read/plan_read_page.dart` | Dev screen: camera, then the list of what was read. |

`PlanHomography` and `GlareDetector` deliberately avoid `dart:ui` and Flutter so they can be unit tested against the committed fixture with no device — the same reason `PlanViewport` is written that way.

---

## Task 1: Add the `image` dependency

**Files:**
- Modify: `pubspec.yaml`

- [ ] **Step 1: Add the package**

In `pubspec.yaml`, directly after the `path_provider` entry in `dependencies:`:

```yaml
  # Pixel access for reading a photographed plan: glare detection now, room
  # fill-colour sampling in slice 2. Pure Dart, so it runs in `flutter test`
  # against the committed fixture rather than only on a device.
  image: ^4.2.0
```

- [ ] **Step 2: Fetch it**

Run: `flutter pub get`
Expected: `Got dependencies!` and `image` moves from transitive to direct.

- [ ] **Step 3: Commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "build: add image package for reading photographed plans"
```

---

## Task 2: `PlanHomography` — photo pixels to plan coordinates

A photograph of a wall-mounted board is always a trapezoid. This maps the four tapped corners onto the unit square, so a read's position is independent of where the photographer stood.

**Files:**
- Create: `lib/services/mapping/plan_homography.dart`
- Test: `test/plan_homography_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/plan_homography_test.dart`:

```dart
import 'package:echo_locate/services/mapping/plan_homography.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('mapping a photographed plan onto the unit square', () {
    test('the four tapped corners become the corners of the square', () {
      // A trapezoid: the board is wider at the bottom because the phone was
      // held below its centre and tilted up. This is the normal case, not a
      // pathological one.
      final homography = PlanHomography.fromCorners(
        topLeft: const PlanCorner(120, 100),
        topRight: const PlanCorner(880, 140),
        bottomRight: const PlanCorner(980, 700),
        bottomLeft: const PlanCorner(40, 640),
      );

      expect(homography.toPlan(120, 100).u, closeTo(0, 0.0001));
      expect(homography.toPlan(120, 100).v, closeTo(0, 0.0001));
      expect(homography.toPlan(880, 140).u, closeTo(1, 0.0001));
      expect(homography.toPlan(880, 140).v, closeTo(0, 0.0001));
      expect(homography.toPlan(980, 700).u, closeTo(1, 0.0001));
      expect(homography.toPlan(980, 700).v, closeTo(1, 0.0001));
      expect(homography.toPlan(40, 640).u, closeTo(0, 0.0001));
      expect(homography.toPlan(40, 640).v, closeTo(1, 0.0001));
    });

    test('a square photographed square is left alone', () {
      final homography = PlanHomography.fromCorners(
        topLeft: const PlanCorner(0, 0),
        topRight: const PlanCorner(100, 0),
        bottomRight: const PlanCorner(100, 100),
        bottomLeft: const PlanCorner(0, 100),
      );

      // Straight-on shots must not be distorted by the correction meant to
      // fix angled ones.
      final centre = homography.toPlan(50, 50);
      expect(centre.u, closeTo(0.5, 0.0001));
      expect(centre.v, closeTo(0.5, 0.0001));
    });

    test('perspective is actually undone, not just scaled', () {
      // The top edge is much shorter than the bottom, so the midpoint of the
      // photographed top edge must still land at u = 0.5. An affine fit would
      // get the corners right and this wrong, which is the whole difference.
      final homography = PlanHomography.fromCorners(
        topLeft: const PlanCorner(400, 100),
        topRight: const PlanCorner(600, 100),
        bottomRight: const PlanCorner(900, 700),
        bottomLeft: const PlanCorner(100, 700),
      );

      final topMiddle = homography.toPlan(500, 100);
      expect(topMiddle.u, closeTo(0.5, 0.0001));
      expect(topMiddle.v, closeTo(0, 0.0001));
    });

    test('a degenerate quad reports itself rather than returning nonsense', () {
      // Three taps in a line. Returning silently-wrong coordinates here would
      // put every landmark in the wrong place with nothing to show why.
      final homography = PlanHomography.fromCorners(
        topLeft: const PlanCorner(0, 0),
        topRight: const PlanCorner(100, 0),
        bottomRight: const PlanCorner(200, 0),
        bottomLeft: const PlanCorner(300, 0),
      );

      expect(homography.isUsable, isFalse);
    });
  });
}
```

- [ ] **Step 2: Run it and watch it fail**

Run: `flutter test test/plan_homography_test.dart`
Expected: FAIL — `Error: Not found: 'package:echo_locate/services/mapping/plan_homography.dart'`

- [ ] **Step 3: Write the implementation**

Create `lib/services/mapping/plan_homography.dart`:

```dart
import 'package:equatable/equatable.dart';

/// A point on the photograph, in pixels.
class PlanCorner extends Equatable {
  const PlanCorner(this.x, this.y);

  final double x;
  final double y;

  @override
  List<Object?> get props => [x, y];
}

/// A point on the plan itself: 0..1 across, 0..1 down, whatever the photograph
/// happened to look like.
class PlanCoordinate extends Equatable {
  const PlanCoordinate(this.u, this.v);

  final double u;
  final double v;

  @override
  List<Object?> get props => [u, v];
}

/// Undoes the perspective in a photograph of a flat plan.
///
/// A board on a wall is never photographed square — the phone is held below
/// its centre and tilted up, so the plan arrives as a trapezoid and everything
/// read off it is stretched more at one end than the other. Correcting that is
/// what makes a room's position a property of the *building* rather than of
/// where the contributor was standing.
///
/// **Coordinates are transformed, not pixels.** Warping the image would mean
/// decoding, resampling and re-encoding several megapixels for no gain: ML Kit
/// reads a moderately angled plan perfectly well, and only the positions it
/// reports need correcting. So this maps points, and the photograph is left
/// exactly as it was taken.
///
/// Free of Flutter and `dart:ui` so it can be unit tested without a device,
/// for the same reason [PlanViewport] is.
class PlanHomography {
  const PlanHomography._(this._m, this.isUsable);

  /// Builds the transform from the four corners of the plan as tapped on the
  /// photograph, clockwise from the top left.
  factory PlanHomography.fromCorners({
    required PlanCorner topLeft,
    required PlanCorner topRight,
    required PlanCorner bottomRight,
    required PlanCorner bottomLeft,
  }) {
    // Heckbert's square-to-quad, mapping unit-square (0,0) (1,0) (1,1) (0,1)
    // onto the tapped quad. We want the opposite direction, so this is
    // inverted below.
    final x0 = topLeft.x, y0 = topLeft.y;
    final x1 = topRight.x, y1 = topRight.y;
    final x2 = bottomRight.x, y2 = bottomRight.y;
    final x3 = bottomLeft.x, y3 = bottomLeft.y;

    final sx = (x0 - x1) + (x2 - x3);
    final sy = (y0 - y1) + (y2 - y3);

    double a, b, c, d, e, f, g, h;

    // Opposite edges parallel — the shot was square on, and the projective
    // terms vanish. Solving the general case here would divide by zero.
    if (sx.abs() < 1e-9 && sy.abs() < 1e-9) {
      a = x1 - x0;
      b = x2 - x1;
      c = x0;
      d = y1 - y0;
      e = y2 - y1;
      f = y0;
      g = 0;
      h = 0;
    } else {
      final dx1 = x1 - x2, dx2 = x3 - x2;
      final dy1 = y1 - y2, dy2 = y3 - y2;
      final denominator = dx1 * dy2 - dx2 * dy1;
      if (denominator.abs() < 1e-9) {
        return const PlanHomography._(<double>[], false);
      }
      g = (sx * dy2 - dx2 * sy) / denominator;
      h = (dx1 * sy - sx * dy1) / denominator;
      a = x1 - x0 + g * x1;
      b = x3 - x0 + h * x3;
      c = x0;
      d = y1 - y0 + g * y1;
      e = y3 - y0 + h * y3;
      f = y0;
    }

    // Invert, so the transform runs photograph → plan. The adjugate is enough:
    // the determinant is a common factor of numerator and denominator in the
    // projective divide below and cancels, so it is never formed.
    final ia = e * 1 - f * h;
    final ib = c * h - b * 1;
    final ic = b * f - c * e;
    final id = f * g - d * 1;
    final ie = a * 1 - c * g;
    final if_ = c * d - a * f;
    final ig = d * h - e * g;
    final ih = b * g - a * h;
    final ii = a * e - b * d;

    final determinant = a * ia + b * id + c * ig;
    if (determinant.abs() < 1e-9) {
      return const PlanHomography._(<double>[], false);
    }

    return PlanHomography._([ia, ib, ic, id, ie, if_, ig, ih, ii], true);
  }

  final List<double> _m;

  /// False when the four taps do not form a quadrilateral — three in a line,
  /// or two on top of each other.
  ///
  /// Worth reporting rather than clamping: every position derived from a
  /// degenerate transform is wrong, and wrong positions look exactly like
  /// correct ones on screen.
  final bool isUsable;

  /// Where a point on the photograph sits on the plan.
  PlanCoordinate toPlan(double x, double y) {
    if (!isUsable) return const PlanCoordinate(0, 0);
    final w = _m[6] * x + _m[7] * y + _m[8];
    if (w.abs() < 1e-12) return const PlanCoordinate(0, 0);
    return PlanCoordinate(
      (_m[0] * x + _m[1] * y + _m[2]) / w,
      (_m[3] * x + _m[4] * y + _m[5]) / w,
    );
  }
}
```

- [ ] **Step 4: Run it and watch it pass**

Run: `flutter test test/plan_homography_test.dart`
Expected: PASS, 4 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/services/mapping/plan_homography.dart test/plan_homography_test.dart
git commit -m "feat: map photographed plan coordinates onto the plan itself"
```

---

## Task 3: `GlareDetector` — find the parts of the photo that were destroyed

The fixture's legend — the most valuable text on the board — is the worst lit thing in the frame. This is the unit that lets the app say so instead of silently reading nothing.

**Files:**
- Create: `lib/services/mapping/glare_detector.dart`
- Test: `test/glare_detector_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/glare_detector_test.dart`:

```dart
import 'dart:io';

import 'package:echo_locate/services/mapping/glare_detector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  /// The real board, photographed through gloss with a window behind the
  /// photographer. Committed so this heuristic is fitted against the thing it
  /// has to survive rather than against synthetic gradients.
  img.Image loadFixture() {
    final bytes =
        File('test/fixtures/plans/college_of_science_ff.jpg').readAsBytesSync();
    final decoded = img.decodeJpg(bytes);
    expect(decoded, isNotNull, reason: 'fixture must decode');
    return decoded!;
  }

  group('finding blown-out regions', () {
    test('an evenly lit image is reported clean', () {
      final flat = img.Image(width: 400, height: 300);
      img.fill(flat, color: img.ColorRgb8(128, 128, 128));

      expect(const GlareDetector().analyse(flat).isClean, isTrue);
    });

    test('a fully blown image is not reported clean', () {
      final blown = img.Image(width: 400, height: 300);
      img.fill(blown, color: img.ColorRgb8(255, 255, 255));

      final report = const GlareDetector().analyse(blown);
      expect(report.isClean, isFalse);
      expect(report.blown, hasLength(GlareDetector.columns * GlareDetector.rows));
    });

    test('the real board reports glare on the side the window was on', () {
      final report = const GlareDetector().analyse(loadFixture());

      // The reflection falls on the right-hand third, over the legend. If this
      // stops holding, the fixture was replaced — not the detector broken.
      expect(report.isClean, isFalse);
      expect(
        report.blown.every((cell) => cell.column >= GlareDetector.columns ~/ 2),
        isTrue,
        reason: 'glare is on the right of this photograph: ${report.blown}',
      );
    });

    test('a report names the worst cell so the screen can point at it', () {
      final report = const GlareDetector().analyse(loadFixture());

      expect(report.worst, isNotNull);
      expect(report.worst!.blownFraction, greaterThan(0));
    });
  });
}
```

- [ ] **Step 2: Run it and watch it fail**

Run: `flutter test test/glare_detector_test.dart`
Expected: FAIL — `Error: Not found: 'package:echo_locate/services/mapping/glare_detector.dart'`

- [ ] **Step 3: Write the implementation**

Create `lib/services/mapping/glare_detector.dart`:

```dart
import 'package:equatable/equatable.dart';
import 'package:image/image.dart' as img;

/// One cell of the photograph that light has destroyed.
class GlareRegion extends Equatable {
  const GlareRegion({
    required this.column,
    required this.row,
    required this.blownFraction,
  });

  final int column;
  final int row;

  /// How much of the cell is at or near full white, 0..1.
  final double blownFraction;

  @override
  List<Object?> get props => [column, row, blownFraction];

  @override
  String toString() =>
      'GlareRegion(c$column r$row ${(blownFraction * 100).round()}%)';
}

/// What a photograph's lighting will cost the read.
class GlareReport extends Equatable {
  const GlareReport(this.blown);

  final List<GlareRegion> blown;

  bool get isClean => blown.isEmpty;

  /// The cell to point the contributor at when asking for another shot.
  GlareRegion? get worst {
    if (blown.isEmpty) return null;
    var worst = blown.first;
    for (final region in blown) {
      if (region.blownFraction > worst.blownFraction) worst = region;
    }
    return worst;
  }

  @override
  List<Object?> get props => [blown];
}

/// Finds the parts of a photographed plan that are too bright to read.
///
/// Posted plans live behind gloss or glass, so a window opposite puts a
/// reflection on the board. On the fixture this lands squarely over the
/// legend — the one block of text that gives every room its meaning — and OCR
/// returns nothing there while appearing to have worked perfectly.
///
/// Telling the contributor *where* to re-shoot is the whole point. "Take
/// another photo" is not actionable; "the top right is washed out" is.
class GlareDetector {
  const GlareDetector();

  /// A coarse grid: enough to say "the right-hand side" without pretending to
  /// a precision the advice does not need.
  static const int columns = 4;
  static const int rows = 3;

  /// Luminance at which detail is gone. Not 255 — JPEG ringing and the
  /// sensor's own noise mean a blown highlight arrives as *nearly* white.
  static const int blownLuminance = 245;

  /// How much of a cell must be blown before it is worth mentioning. Below
  /// this a cell has a specular fleck in it, which costs a character at worst.
  static const double blownFraction = 0.18;

  /// Width the image is reduced to before measuring.
  ///
  /// Glare is a large, soft feature; measuring it at full resolution reads
  /// several megapixels to compute the same answer. This keeps the whole
  /// analysis well under a second on the phones this targets.
  static const int sampleWidth = 320;

  GlareReport analyse(img.Image image) {
    final sample = image.width > sampleWidth
        ? img.copyResize(image, width: sampleWidth)
        : image;

    final cellWidth = sample.width / columns;
    final cellHeight = sample.height / rows;

    final blown = <GlareRegion>[];

    for (var row = 0; row < rows; row++) {
      for (var column = 0; column < columns; column++) {
        final startX = (column * cellWidth).floor();
        final endX = ((column + 1) * cellWidth).floor().clamp(0, sample.width);
        final startY = (row * cellHeight).floor();
        final endY = ((row + 1) * cellHeight).floor().clamp(0, sample.height);

        var total = 0;
        var over = 0;
        for (var y = startY; y < endY; y++) {
          for (var x = startX; x < endX; x++) {
            final pixel = sample.getPixel(x, y);
            // Rec. 601 luma, written out rather than taken from the package so
            // the threshold above means the same thing across版本 changes.
            final luminance = 0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b;
            if (luminance >= blownLuminance) over++;
            total++;
          }
        }

        if (total == 0) continue;
        final fraction = over / total;
        if (fraction >= blownFraction) {
          blown.add(
            GlareRegion(column: column, row: row, blownFraction: fraction),
          );
        }
      }
    }

    return GlareReport(blown);
  }
}
```

- [ ] **Step 4: Run it**

Run: `flutter test test/glare_detector_test.dart`
Expected: PASS, 4 tests.

**If the real-board test fails**, do not weaken the assertion to make it green. Print the report first:

```bash
flutter test test/glare_detector_test.dart --plain-name 'the real board reports glare'
```

The failure message includes every flagged cell. Two legitimate outcomes: the reflection is milder than `blownFraction` expects, in which case lower it until the right-hand cells are caught and the centre is not — record the measured number in a comment; or glare has spread further left than the right half, in which case relax the assertion to "the worst cell is on the right" and note it. Either way the threshold must end up *measured against this photograph*, not guessed.

- [ ] **Step 5: Fix the stray non-ASCII in the comment**

The comment in `analyse` contains `版本`, which must read `version`. Correct it, then:

Run: `flutter analyze lib/services/mapping/glare_detector.dart`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add lib/services/mapping/glare_detector.dart test/glare_detector_test.dart
git commit -m "feat: report which part of a plan photo glare destroyed"
```

---

## Task 4: `PlanRead` — one piece of text found on a plan

**Files:**
- Create: `lib/services/mapping/plan_read.dart`
- Test: `test/plan_read_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/plan_read_test.dart`:

```dart
import 'package:echo_locate/services/mapping/plan_homography.dart';
import 'package:echo_locate/services/mapping/plan_read.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('a piece of text found on a plan', () {
    test('its position on the plan is its centre, not its corner', () {
      const read = PlanRead(
        text: 'FF 12',
        left: 100,
        top: 200,
        width: 60,
        height: 20,
      );

      expect(read.centreX, 130);
      expect(read.centreY, 210);
    });

    test('it can be placed on the plan through the homography', () {
      final homography = PlanHomography.fromCorners(
        topLeft: const PlanCorner(0, 0),
        topRight: const PlanCorner(100, 0),
        bottomRight: const PlanCorner(100, 100),
        bottomLeft: const PlanCorner(0, 100),
      );
      const read =
          PlanRead(text: 'FF 12', left: 40, top: 40, width: 20, height: 20);

      final placed = read.placedOn(homography);

      expect(placed.u, closeTo(0.5, 0.0001));
      expect(placed.v, closeTo(0.5, 0.0001));
    });

    test('text is normalised the way landmark labels are', () {
      const read =
          PlanRead(text: '  ff  12 ', left: 0, top: 0, width: 1, height: 1);

      // The door plate this must eventually match against is stored upper-case
      // and single-spaced, so the read has to arrive in the same shape or
      // nothing will ever match.
      expect(read.normalisedText, 'FF 12');
    });
  });
}
```

- [ ] **Step 2: Run it and watch it fail**

Run: `flutter test test/plan_read_test.dart`
Expected: FAIL — `Error: Not found: 'package:echo_locate/services/mapping/plan_read.dart'`

- [ ] **Step 3: Write the implementation**

Create `lib/services/mapping/plan_read.dart`:

```dart
import 'package:equatable/equatable.dart';

import '../../core/models/landmark.dart';
import 'plan_homography.dart';

/// One line of text OCR found on a photographed plan, with where it sat.
///
/// Position is the whole point. A plan's text is not a list — `FF 12` means a
/// room *there*, and the legend means what it does because it sits in the
/// corner rather than in the drawing. Text without its box is unusable for
/// everything after this slice.
///
/// Held in photograph pixels. [placedOn] converts to plan coordinates once the
/// contributor has tapped the corners; keeping both would let them disagree.
class PlanRead extends Equatable {
  const PlanRead({
    required this.text,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final String text;
  final double left;
  final double top;
  final double width;
  final double height;

  double get centreX => left + width / 2;
  double get centreY => top + height / 2;

  /// Upper-case and single-spaced, exactly as `landmarks.label_text` is
  /// stored — so a read off the plan and a read off the door are comparable
  /// without either side re-deciding what normalisation means.
  String get normalisedText => Landmark.normalise(text);

  /// Where this sits on the plan itself, once perspective is undone.
  PlanCoordinate placedOn(PlanHomography homography) =>
      homography.toPlan(centreX, centreY);

  @override
  List<Object?> get props => [text, left, top, width, height];

  @override
  String toString() => 'PlanRead("$text" @ $centreX,$centreY)';
}
```

- [ ] **Step 4: Run it**

Run: `flutter test test/plan_read_test.dart`
Expected: PASS, 3 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/services/mapping/plan_read.dart test/plan_read_test.dart
git commit -m "feat: model a positioned piece of text read off a plan"
```

---

## Task 5: `PlanOcrService` — ML Kit over a still

This is the one unit that cannot be unit tested; it needs a real device. It stays deliberately thin for that reason — everything with a decision in it lives in the units above.

**Files:**
- Create: `lib/services/mapping/plan_ocr_service.dart`

- [ ] **Step 1: Write the implementation**

Create `lib/services/mapping/plan_ocr_service.dart`:

```dart
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../../core/utils/logger.dart';
import 'plan_read.dart';

/// Reads every line of text off a photographed plan.
///
/// Separate from [TextRecognitionService], which streams live camera frames
/// for guidance and holds a long-lived recogniser. This runs once over one
/// still and closes, because a plan is read at the moment it is photographed
/// and never again.
///
/// **Lines, not blocks.** A block glues a whole legend into a single string
/// that matches nothing; a line is one legend entry or one room code, which is
/// the unit everything downstream works in.
///
/// Deliberately thin, because it is the one piece here that cannot be tested
/// without a device. Every judgement — where a read sits on the plan, whether
/// the light was good enough — lives in units that can be.
class PlanOcrService {
  const PlanOcrService();

  /// Every line found in the photograph at [imagePath].
  ///
  /// Returns empty rather than throwing when the recogniser fails: a plan that
  /// will not read is a reason to re-shoot, which the screen already has to
  /// handle for glare.
  Future<List<PlanRead>> read(String imagePath) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final recognised =
          await recognizer.processImage(InputImage.fromFilePath(imagePath));

      final reads = <PlanRead>[];
      for (final block in recognised.blocks) {
        for (final line in block.lines) {
          if (line.text.trim().isEmpty) continue;
          reads.add(
            PlanRead(
              text: line.text.trim(),
              left: line.boundingBox.left,
              top: line.boundingBox.top,
              width: line.boundingBox.width,
              height: line.boundingBox.height,
            ),
          );
        }
      }

      // Evidence for the slice-1 device check: grep PLAN-OCR.
      AppLogger.info('PLAN-OCR read ${reads.length} lines from $imagePath');
      return reads;
    } catch (error, stack) {
      AppLogger.error('Plan OCR failed: $error', error, stack);
      return const [];
    } finally {
      await recognizer.close();
    }
  }
}
```

- [ ] **Step 2: Check it compiles**

Run: `flutter analyze lib/services/mapping/plan_ocr_service.dart`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/services/mapping/plan_ocr_service.dart
git commit -m "feat: read every line of text off a photographed plan"
```

---

## Task 6: `PlanReadBloc` — sequence capture, glare and OCR

**Files:**
- Create: `lib/features/plan_read/bloc/plan_read_bloc.dart`
- Create: `lib/features/plan_read/bloc/plan_read_event.dart`
- Create: `lib/features/plan_read/bloc/plan_read_state.dart`
- Test: `test/plan_read_bloc_test.dart`

- [ ] **Step 1: Write the state and event**

Create `lib/features/plan_read/bloc/plan_read_event.dart`:

```dart
part of 'plan_read_bloc.dart';

sealed class PlanReadEvent extends Equatable {
  const PlanReadEvent();

  @override
  List<Object?> get props => const [];
}

/// Opens the camera.
class PlanReadStarted extends PlanReadEvent {
  const PlanReadStarted(this.buildingId);

  final String buildingId;

  @override
  List<Object?> get props => [buildingId];
}

/// Takes the photo, then reads it.
class PlanReadCaptured extends PlanReadEvent {
  const PlanReadCaptured();
}

/// Throws the photo away and re-opens the camera — the answer to a glare
/// warning.
class PlanReadRetaken extends PlanReadEvent {
  const PlanReadRetaken();
}
```

Create `lib/features/plan_read/bloc/plan_read_state.dart`:

```dart
part of 'plan_read_bloc.dart';

enum PlanReadStage { photo, reading, results }

class PlanReadState extends Equatable {
  const PlanReadState({
    this.stage = PlanReadStage.photo,
    this.buildingId = '',
    this.photoPath,
    this.cameraReady = false,
    this.reads = const [],
    this.glare = const GlareReport(<GlareRegion>[]),
    this.error,
  });

  final PlanReadStage stage;
  final String buildingId;
  final String? photoPath;
  final bool cameraReady;
  final List<PlanRead> reads;
  final GlareReport glare;
  final String? error;

  PlanReadState copyWith({
    PlanReadStage? stage,
    String? buildingId,
    String? photoPath,
    bool clearPhoto = false,
    bool? cameraReady,
    List<PlanRead>? reads,
    GlareReport? glare,
    String? error,
  }) =>
      PlanReadState(
        stage: stage ?? this.stage,
        buildingId: buildingId ?? this.buildingId,
        photoPath: clearPhoto ? null : (photoPath ?? this.photoPath),
        cameraReady: cameraReady ?? this.cameraReady,
        reads: reads ?? this.reads,
        glare: glare ?? this.glare,
        // Never sticky: a warning from a refused read must not outlive the
        // read that worked.
        error: error,
      );

  @override
  List<Object?> get props =>
      [stage, buildingId, photoPath, cameraReady, reads, glare, error];
}
```

- [ ] **Step 2: Write the failing test**

Create `test/plan_read_bloc_test.dart`:

```dart
import 'dart:io';

import 'package:echo_locate/features/plan_read/bloc/plan_read_bloc.dart';
import 'package:echo_locate/services/mapping/plan_ocr_service.dart';
import 'package:echo_locate/services/mapping/plan_photo_service.dart';
import 'package:echo_locate/services/mapping/plan_read.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockPhotos extends Mock implements PlanPhotoService {}

class _MockOcr extends Mock implements PlanOcrService {}

void main() {
  late _MockPhotos photos;
  late _MockOcr ocr;

  /// The committed board, so the glare step runs on a real photograph rather
  /// than a stub that can never be blown out.
  const fixture = 'test/fixtures/plans/college_of_science_ff.jpg';

  setUp(() {
    photos = _MockPhotos();
    ocr = _MockOcr();
    when(() => photos.start()).thenAnswer((_) async => true);
    when(() => photos.stop()).thenAnswer((_) async {});
    when(() => photos.capture(any(), any())).thenAnswer((_) async => fixture);
    when(() => ocr.read(any())).thenAnswer(
      (_) async => const [
        PlanRead(text: 'FF 12', left: 10, top: 10, width: 40, height: 12),
        PlanRead(text: 'LIBRARY', left: 300, top: 200, width: 60, height: 12),
      ],
    );
  });

  Future<void> pump() async {
    for (var i = 0; i < 8; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test('the fixture is present', () {
    expect(File(fixture).existsSync(), isTrue);
  });

  test('capturing reads the plan and shows what it found', () async {
    final bloc = PlanReadBloc(photos, ocr);
    bloc.add(const PlanReadStarted('b1'));
    await pump();

    bloc.add(const PlanReadCaptured());
    await pump();

    expect(bloc.state.stage, PlanReadStage.results);
    expect(bloc.state.reads.map((r) => r.text), ['FF 12', 'LIBRARY']);
    await bloc.close();
  });

  test('glare in the photograph is reported alongside the reads', () async {
    final bloc = PlanReadBloc(photos, ocr);
    bloc.add(const PlanReadStarted('b1'));
    await pump();

    bloc.add(const PlanReadCaptured());
    await pump();

    // The fixture is genuinely blown out on one side. Reporting the reads
    // without saying so is how a half-read plan looks like a complete one.
    expect(bloc.state.glare.isClean, isFalse);
    await bloc.close();
  });

  test('a photo that will not read says so instead of showing nothing',
      () async {
    when(() => ocr.read(any())).thenAnswer((_) async => const []);
    final bloc = PlanReadBloc(photos, ocr);
    bloc.add(const PlanReadStarted('b1'));
    await pump();

    bloc.add(const PlanReadCaptured());
    await pump();

    expect(bloc.state.error, isNotNull);
    await bloc.close();
  });

  test('re-shooting clears the previous read', () async {
    final bloc = PlanReadBloc(photos, ocr);
    bloc.add(const PlanReadStarted('b1'));
    await pump();
    bloc.add(const PlanReadCaptured());
    await pump();

    bloc.add(const PlanReadRetaken());
    await pump();

    // Leaving the old list up while the camera is open invites reading the
    // previous plan's results as this one's.
    expect(bloc.state.stage, PlanReadStage.photo);
    expect(bloc.state.reads, isEmpty);
    await bloc.close();
  });
}
```

- [ ] **Step 3: Run it and watch it fail**

Run: `flutter test test/plan_read_bloc_test.dart`
Expected: FAIL — `Error: Not found: 'package:echo_locate/features/plan_read/bloc/plan_read_bloc.dart'`

- [ ] **Step 4: Write the bloc**

Create `lib/features/plan_read/bloc/plan_read_bloc.dart`:

```dart
import 'dart:io';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:image/image.dart' as img;

import '../../../core/utils/logger.dart';
import '../../../services/mapping/glare_detector.dart';
import '../../../services/mapping/plan_ocr_service.dart';
import '../../../services/mapping/plan_photo_service.dart';
import '../../../services/mapping/plan_read.dart';

part 'plan_read_event.dart';
part 'plan_read_state.dart';

/// Photograph a posted plan, then say what is on it.
///
/// Slice 1 of reading plans: no classification, no key parsing, no landmarks
/// — just the raw text and an honest account of what the light cost. It exists
/// as its own screen so the read can be thrown at real boards without
/// disturbing the trace flow, which is the thing that has to keep working.
class PlanReadBloc extends Bloc<PlanReadEvent, PlanReadState> {
  PlanReadBloc(
    this._photos,
    this._ocr, {
    GlareDetector glare = const GlareDetector(),
  })  : _glare = glare,
        super(const PlanReadState()) {
    on<PlanReadStarted>(_onStarted);
    on<PlanReadCaptured>(_onCaptured);
    on<PlanReadRetaken>(_onRetaken);
  }

  final PlanPhotoService _photos;
  final PlanOcrService _ocr;
  final GlareDetector _glare;

  /// The floor a slice-1 read is filed under.
  ///
  /// Slice 2 takes the floor from the label prefix — `FF 12` is first floor —
  /// so nothing here needs to ask. Until then the photo has to be stored
  /// somewhere, and one slot per building is enough to re-shoot into.
  static const String scratchFloorId = 'plan-read-scratch';

  PlanPhotoService get photos => _photos;

  Future<void> _onStarted(
    PlanReadStarted event,
    Emitter<PlanReadState> emit,
  ) async {
    emit(
      state.copyWith(
        buildingId: event.buildingId,
        stage: PlanReadStage.photo,
      ),
    );
    final ready = await _photos.start();
    if (isClosed) return;
    emit(state.copyWith(cameraReady: ready));
  }

  Future<void> _onCaptured(
    PlanReadCaptured event,
    Emitter<PlanReadState> emit,
  ) async {
    final path = await _photos.capture(state.buildingId, scratchFloorId);
    if (isClosed) return;
    if (path == null) {
      emit(state.copyWith(error: 'Could not take that photo. Try again.'));
      return;
    }

    await _photos.stop();
    if (isClosed) return;
    emit(
      state.copyWith(
        photoPath: path,
        cameraReady: false,
        stage: PlanReadStage.reading,
      ),
    );

    final glare = await _glareOf(path);
    final reads = await _ocr.read(path);
    if (isClosed) return;

    // Nothing read at all is a failed capture, not an empty plan. Showing an
    // empty list would read as "this board has no text on it".
    if (reads.isEmpty) {
      emit(
        state.copyWith(
          stage: PlanReadStage.results,
          glare: glare,
          reads: const [],
          error: glare.isClean
              ? 'Nothing readable in that photo. Move closer and try again.'
              : 'Nothing readable — the photo is washed out. Try again from '
                  'an angle that keeps the light off the plan.',
        ),
      );
      return;
    }

    emit(
      state.copyWith(
        stage: PlanReadStage.results,
        reads: reads,
        glare: glare,
      ),
    );
  }

  Future<void> _onRetaken(
    PlanReadRetaken event,
    Emitter<PlanReadState> emit,
  ) async {
    await _photos.discard(state.buildingId, scratchFloorId);
    if (isClosed) return;
    emit(
      state.copyWith(
        stage: PlanReadStage.photo,
        clearPhoto: true,
        reads: const [],
        glare: const GlareReport(<GlareRegion>[]),
      ),
    );
    final ready = await _photos.start();
    if (isClosed) return;
    emit(state.copyWith(cameraReady: ready));
  }

  /// Decoding is several megapixels of work, so it happens off the UI isolate.
  /// A failure here costs the warning, never the read.
  ///
  /// Decode and measure in **one** hop. Two would send a whole decoded bitmap
  /// back across the isolate boundary just to send it out again, and the
  /// detector is lifted into a local first because a closure over the field
  /// would capture the bloc — which is not sendable, and fails at runtime
  /// rather than at compile time.
  Future<GlareReport> _glareOf(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      final detector = _glare;
      return await Isolate.run(() {
        final decoded = img.decodeJpg(bytes);
        if (decoded == null) return const GlareReport(<GlareRegion>[]);
        return detector.analyse(decoded);
      });
    } catch (error, stack) {
      AppLogger.error('Glare analysis failed: $error', error, stack);
      return const GlareReport(<GlareRegion>[]);
    }
  }

  @override
  Future<void> close() async {
    await _photos.stop();
    return super.close();
  }
}
```

- [ ] **Step 5: Fix the missing import**

`Isolate.run` needs `dart:isolate`. Add to the top of the file, above `dart:io`:

```dart
import 'dart:isolate';
```

Run: `flutter analyze lib/features/plan_read/bloc/plan_read_bloc.dart`
Expected: `No issues found!`

- [ ] **Step 6: Run the tests**

Run: `flutter test test/plan_read_bloc_test.dart`
Expected: PASS, 5 tests.

- [ ] **Step 7: Commit**

```bash
git add lib/features/plan_read test/plan_read_bloc_test.dart
git commit -m "feat: sequence capture, glare check and OCR for a posted plan"
```

---

## Task 7: The screen, its route and its wiring

**Files:**
- Create: `lib/ui/pages/plan_read/plan_read_page.dart`
- Modify: `lib/core/routes/app_routes.dart`
- Modify: `lib/router/app_router.dart`
- Modify: `lib/services/injection_container.dart`
- Modify: `lib/ui/pages/profile/profile_page.dart`

- [ ] **Step 1: Write the page**

Create `lib/ui/pages/plan_read/plan_read_page.dart`:

```dart
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimens.dart';
import '../../../features/plan_read/bloc/plan_read_bloc.dart';
import '../../../services/injection_container.dart';

/// Slice 1: photograph a posted plan and see everything it says.
///
/// A dev screen on purpose. The read has to be thrown at real boards in real
/// corridors before any of it is trusted enough to build the map on, and doing
/// that inside the trace flow would put the one feature that currently works
/// at risk of every experiment.
class PlanReadPage extends StatelessWidget {
  const PlanReadPage({super.key, required this.buildingId});

  final String buildingId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<PlanReadBloc>()..add(PlanReadStarted(buildingId)),
      child: const _PlanReadView(),
    );
  }
}

class _PlanReadView extends StatelessWidget {
  const _PlanReadView();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PlanReadBloc, PlanReadState>(
      builder: (context, state) {
        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(PhosphorIconsRegular.x),
              onPressed: () => context.pop(),
            ),
            title: Text(switch (state.stage) {
              PlanReadStage.photo => 'Photograph the plan',
              PlanReadStage.reading => 'Reading…',
              PlanReadStage.results => '${state.reads.length} lines read',
            }),
            actions: [
              if (state.stage == PlanReadStage.results)
                TextButton(
                  onPressed: () =>
                      context.read<PlanReadBloc>().add(const PlanReadRetaken()),
                  child: const Text('Re-shoot'),
                ),
            ],
          ),
          body: SafeArea(
            child: switch (state.stage) {
              PlanReadStage.photo => const _CameraStep(),
              PlanReadStage.reading =>
                const Center(child: CircularProgressIndicator()),
              PlanReadStage.results => const _ResultsStep(),
            },
          ),
        );
      },
    );
  }
}

class _CameraStep extends StatelessWidget {
  const _CameraStep();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bloc = context.read<PlanReadBloc>();
    final state = context.watch<PlanReadBloc>().state;
    final controller = bloc.photos.camera;

    return Column(
      children: [
        Expanded(
          child: state.cameraReady && controller != null
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(AppDimens.radiusLg),
                  child: CameraPreview(controller),
                )
              : Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppDimens.space32),
                    child: Text(
                      'No camera available.',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ),
        ),
        Padding(
          padding: const EdgeInsets.all(AppDimens.space16),
          child: Column(
            children: [
              Text(
                'Fill the frame with the plan, straight on. If a window is '
                'behind you, stand to one side — the reflection lands on the '
                'legend.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: AppDimens.space12),
              if (state.cameraReady)
                ElevatedButton.icon(
                  onPressed: () => bloc.add(const PlanReadCaptured()),
                  icon: const Icon(PhosphorIconsFill.camera, size: 18),
                  label: const Text('Read this plan'),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ResultsStep extends StatelessWidget {
  const _ResultsStep();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = context.watch<PlanReadBloc>().state;
    final worst = state.glare.worst;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.error != null)
          Container(
            width: double.infinity,
            color: AppColors.error.withValues(alpha: 0.12),
            padding: const EdgeInsets.all(AppDimens.space12),
            child: Text(state.error!, style: theme.textTheme.bodySmall),
          ),
        if (worst != null)
          Container(
            width: double.infinity,
            color: AppColors.coral.withValues(alpha: 0.12),
            padding: const EdgeInsets.all(AppDimens.space12),
            child: Text(
              'Glare over the ${_where(worst)} of the plan — '
              '${(worst.blownFraction * 100).round()}% washed out. Anything '
              'printed there was probably missed.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        if (state.photoPath != null)
          SizedBox(
            height: 180,
            child: Image.file(File(state.photoPath!), fit: BoxFit.contain),
          ),
        Expanded(
          child: ListView.separated(
            itemCount: state.reads.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final read = state.reads[index];
              return ListTile(
                dense: true,
                title: Text(read.text, style: theme.textTheme.bodyMedium),
                subtitle: Text(
                  '${read.centreX.round()}, ${read.centreY.round()}',
                  style: theme.textTheme.bodySmall,
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  static String _where(GlareRegion region) {
    final vertical = switch (region.row) {
      0 => 'top',
      1 => 'middle',
      _ => 'bottom',
    };
    final horizontal = region.column < GlareDetector.columns / 2
        ? 'left'
        : 'right';
    return '$vertical $horizontal';
  }
}
```

- [ ] **Step 2: Add the missing import**

`_where` uses `GlareRegion` and `GlareDetector`. Add below the `app_dimens` import:

```dart
import '../../../services/mapping/glare_detector.dart';
```

- [ ] **Step 3: Add the route constants**

In `lib/core/routes/app_routes.dart`, beside the `planTrace` path constant:

```dart
  /// Slice 1 of plan reading: photograph a plan and list what it says (dev).
  static const String planRead = '/building/:id/read';
```

and beside the `planTrace` name constant:

```dart
  static const String planRead = 'planRead';
```

- [ ] **Step 4: Register the route**

In `lib/router/app_router.dart`, directly after the `planTrace` `GoRoute`:

```dart
    GoRoute(
      path: AppRoutes.planRead,
      name: RouteNames.planRead,
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => PlanReadPage(
        buildingId: state.pathParameters['id']!,
      ),
    ),
```

Add the import at the top of the file:

```dart
import '../ui/pages/plan_read/plan_read_page.dart';
```

- [ ] **Step 5: Register the bloc and service**

In `lib/services/injection_container.dart`, directly after the `PlanTraceBloc` registration that ends at line 200:

```dart
  // Its own PlanPhotoService instance, exactly as PlanTraceBloc above gets
  // one: the service owns a camera, and two screens sharing one controller
  // is how the second one to open finds it already disposed.
  getIt.registerLazySingleton<PlanOcrService>(() => const PlanOcrService());
  getIt.registerFactory<PlanReadBloc>(
    () => PlanReadBloc(PlanPhotoService(), getIt<PlanOcrService>()),
  );
```

Add the imports:

```dart
import '../features/plan_read/bloc/plan_read_bloc.dart';
import 'mapping/plan_ocr_service.dart';
```

`PlanPhotoService` is constructed inline rather than resolved from `getIt` — that is deliberate and matches `PlanTraceBloc` at line 197, which does the same.

- [ ] **Step 6: Add the Profile entry**

In `lib/ui/pages/profile/profile_page.dart`, immediately after the existing "Trace a floor plan (dev)" `Card`:

```dart
                const SizedBox(height: AppDimens.space8),
                Card(
                  child: ListTile(
                    title: Text('Read a plan (dev)',
                        style: theme.textTheme.titleMedium),
                    subtitle: Text(
                      'Photograph a posted plan and list every line of text '
                      'on it, with a glare warning',
                      style: theme.textTheme.bodyMedium,
                    ),
                    trailing: Icon(
                      PhosphorIconsRegular.caretRight,
                      size: 18,
                      color: theme.textTheme.bodyMedium?.color,
                    ),
                    onTap: () => context.pushNamed(
                      RouteNames.planRead,
                      pathParameters: {'id': _demoBuildingId},
                    ),
                  ),
                ),
```

- [ ] **Step 7: Analyze and test**

Run: `flutter analyze lib test`
Expected: `No issues found!`

Run: `flutter test`
Expected: `All tests passed!` — 363 existing plus 16 new.

- [ ] **Step 8: Commit**

```bash
git add lib/ui/pages/plan_read lib/core/routes/app_routes.dart lib/router/app_router.dart lib/services/injection_container.dart lib/ui/pages/profile/profile_page.dart
git commit -m "feat: dev screen for reading a posted plan"
```

---

## Task 8: The device check

This is the task that decides whether slice 1 worked. It is not passed by the test suite.

**Files:** none — this is run, not written.

- [ ] **Step 1: Install on the phone**

```bash
flutter build apk --debug
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

If `adb devices` shows `unauthorized`, accept the USB debugging prompt on the phone.

- [ ] **Step 2: Watch the log**

In a second terminal:

```bash
adb logcat -c && adb logcat | grep -E "PLAN-OCR|flutter"
```

- [ ] **Step 3: Read the real board**

Go to the College of Science first-floor board — the one in `test/fixtures/plans/college_of_science_ff.jpg`. Open the app → Profile → **Read a plan (dev)** → photograph it.

- [ ] **Step 4: Check the acceptance criteria**

Against the board itself, confirm:

1. **Room codes.** Every `FF 1` … `FF 24` that is on the board is in the list. Note any that are missing.
2. **Legend entries.** `STAIRCASE`, `LECTURE HALL`, `OFFICE`, `LABORATORY`, `AUDITORIUM`, `CONTROL ROOM`, `COMMON ROOM`, `LIBRARY`, `IBISTEK BOARDROOM`, `WASHROOM`, `ELEVATOR`, `LOCATION`, `OPTOMETRY CLINIC`. Note which are missing — this is the glare-prone block and the result decides how much slice 2 can rely on it.
3. **`WC` labels.** All of them, or a count of how many of the six were found.
4. **The glare banner.** Does it appear, and does it name the side the window was actually on?
5. **Positions.** Do the coordinates beside each read increase left-to-right and top-to-bottom in the order you would expect?

- [ ] **Step 5: Write down what happened**

Append the results to the spec under a new "Slice 1 field results" heading in
`docs/superpowers/specs/2026-08-13-plan-reading-navigation-design.md`: how many of the 24 room codes came back, how many of the 13 legend entries, whether glare was flagged correctly, and anything read that was not expected.

This is the input to slice 2. If the legend reads poorly even with a close-up, the palette-confirmation step has to let the contributor **type** a category name rather than only correct a misread one — a design change that is much cheaper to make now than after it is built.

- [ ] **Step 6: Commit the findings**

```bash
git add docs/superpowers/specs/2026-08-13-plan-reading-navigation-design.md
git commit -m "docs: slice 1 field results from the College of Science board"
```

---

## Definition of done

- `flutter analyze lib test` clean.
- `flutter test` green, 379 tests.
- The dev screen photographs the real board and lists its text.
- Slice 1 field results written into the spec.

## Deliberately not in this slice

No key parsing, no colour sampling, no classification, no waypoints, no corridor spine, no changes to `traced_plans`, `floor_graph.dart`, `route_planner.dart` or the painter. Those land in slices 2–5, and each depends on what the field results say.

The four-corner tap is **not** wired into the screen either — `PlanHomography` is built and tested here because slice 2 needs it and it is pure maths worth having under test early, but nothing calls it until there are corners to feed it.

The spec's slice 1 also mentioned a **separate close-up of the legend**. That is deliberately dropped to slice 2. Here the whole-plan re-shoot is the mitigation, and step 4 of the device check is what decides whether a dedicated legend capture is needed at all — if a normal re-shoot recovers all 13 entries, a second capture mode is code nobody needs. Storing a legend shot *separately* only earns its keep once something parses it, which is slice 2.
