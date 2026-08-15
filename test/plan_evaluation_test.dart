import 'package:echo_locate/core/models/room_plan.dart';
import 'package:echo_locate/services/evaluation/plan_evaluation.dart';
import 'package:echo_locate/services/mapping/room_graph.dart';
import 'package:flutter_test/flutter_test.dart';

import 'room_directions_test.dart' show buildWing;

/// The wing's real adjacencies, as somebody would copy them off the board.
/// The corridor is `GF 0`; the rooms carry labels where they have them.
const trueAdjacencies = '''
# KNUST CS, ground floor — read off the board 14 Aug
GF 0, Lobby
GF 0, GF 2
GF 0, Digital Forensic Office
GF 0, GF 4
GF 0, GF 5
GF 0, GF 6
''';

void main() {
  group('parsing what a person types', () {
    test('accepts commas, pipes and spaced hyphens', () {
      final truth = PlanGroundTruth.parse('''
        A, B
        C | D
        E - F
      ''');

      expect(truth.adjacencies, hasLength(3));
      expect(truth.adjacencies, contains((a: 'A', b: 'B')));
      expect(truth.adjacencies, contains((a: 'C', b: 'D')));
      expect(truth.adjacencies, contains((a: 'E', b: 'F')));
    });

    test('a door written either way round is one door', () {
      final truth = PlanGroundTruth.parse('Corridor, Lobby\nLobby, Corridor');

      // Without ordering the ends, the same board scores differently depending
      // on which end of each corridor happened to be written first.
      expect(truth.adjacencies, hasLength(1));
    });

    test('skips comments, blanks and half-written lines', () {
      final truth = PlanGroundTruth.parse('''
# a note about which wing this is

A, B

GF 9
      ''');

      expect(truth.adjacencies, hasLength(1));
    });

    test('normalises case and runs of spaces', () {
      final truth = PlanGroundTruth.parse('  reading   hall ,  GF 0 ');

      expect(truth.adjacencies.single, (a: 'GF 0', b: 'READING HALL'));
    });

    test('a room joined to itself is not a door', () {
      expect(PlanGroundTruth.parse('A, A').adjacencies, isEmpty);
    });
  });

  group('topology against the board', () {
    test('a plan matching the board scores 100%', () {
      final score = PlanEvaluation.scoreTopology(
        buildWing(),
        PlanGroundTruth.parse(trueAdjacencies),
      );

      expect(score.truePositives, 6);
      expect(score.missing, isEmpty);
      expect(score.spurious, isEmpty);
      expect(score.precision, 1);
      expect(score.recall, 1);
      expect(score.f1, 1);
    });

    test('matches a room by its code or by its typed name', () {
      // The board calls it "Digital Forensic Office"; the plan's own code is
      // "GF 3". Either naming has to resolve to the same door.
      final byCode = PlanEvaluation.scoreTopology(
        buildWing(),
        PlanGroundTruth.parse('GF 0, GF 3'),
      );

      expect(byCode.truePositives, 1);
      expect(byCode.missing, isEmpty);
    });

    test('a door the plan missed costs recall and is named', () {
      final plan = buildWing();
      final withoutN3 = plan.copyWith(
        storedOpenings: [
          for (final opening in plan.openings)
            if (opening.id != 'd-n3') opening,
        ],
      );

      final score = PlanEvaluation.scoreTopology(
        withoutN3,
        PlanGroundTruth.parse(trueAdjacencies),
      );

      expect(score.recall, closeTo(5 / 6, 1e-9));
      expect(score.precision, 1);
      // The number is a grade; the pair is a fix.
      expect(score.missing.single, (a: 'GF 0', b: 'GF 4'));
    });

    test('a door the board does not show costs precision', () {
      final score = PlanEvaluation.scoreTopology(
        buildWing(),
        PlanGroundTruth.parse('''
GF 0, Lobby
GF 0, GF 2
GF 0, Digital Forensic Office
GF 0, GF 4
GF 0, GF 5
'''),
      );

      expect(score.recall, 1);
      expect(score.precision, closeTo(5 / 6, 1e-9));
      expect(score.spurious, hasLength(1));
    });

    test(
      'an exterior door is not scored — the board pairs nothing with it',
      () {
        final plan = buildWing();
        final withExit = plan.copyWith(
          storedOpenings: [
            ...plan.openings,
            const Opening(
              id: 'd-exit',
              roomAId: 'lobby',
              at: RoomCorner(x: -6, y: 0),
            ),
          ],
        );

        final score = PlanEvaluation.scoreTopology(
          withExit,
          PlanGroundTruth.parse(trueAdjacencies),
        );

        expect(score.precision, 1);
        expect(score.spurious, isEmpty);
      },
    );
  });

  group('the routes to walk', () {
    test('samples pairs spread across the floor, not all from one room', () {
      final routes = PlanEvaluation.auditRoutes(
        buildWing(),
        RoomNavGraph.build(buildWing()),
        sample: 6,
      );

      expect(routes, hasLength(6));
      // Taking the first six pairs of a sorted list would test one corridor
      // six times and the rest of the building never.
      expect(routes.map((r) => r.fromName).toSet().length, greaterThan(1));
    });

    test('never routes to a corridor — nobody navigates to one', () {
      final routes = PlanEvaluation.auditRoutes(
        buildWing(),
        RoomNavGraph.build(buildWing()),
      );

      expect(routes.every((r) => !r.toName.contains('corridor')), isTrue);
    });

    test('is deterministic, so a re-run is about the same routes', () {
      // Somebody walks the list, fixes a door, and runs it again. If the pairs
      // shuffled, the two reports would not be comparable.
      final first = PlanEvaluation.auditRoutes(
        buildWing(),
        RoomNavGraph.build(buildWing()),
        sample: 8,
      );
      final second = PlanEvaluation.auditRoutes(
        buildWing(),
        RoomNavGraph.build(buildWing()),
        sample: 8,
      );

      expect(
        first.map((r) => '${r.fromName}>${r.toName}'),
        second.map((r) => '${r.fromName}>${r.toName}'),
      );
    });

    test('carries the actual sentences that will be spoken', () {
      final routes = PlanEvaluation.auditRoutes(
        buildWing(),
        RoomNavGraph.build(buildWing()),
      );
      final withOrdinals = routes.where(
        (r) => r.instructions.any((i) => i.contains('door on your')),
      );

      // The failure being hunted is one wrong word inside one of these.
      expect(withOrdinals, isNotEmpty);
    });

    test('flags a route whose corridor has untagged doors', () {
      final routes = PlanEvaluation.auditRoutes(
        buildWing(declareDoors: false),
        RoomNavGraph.build(buildWing(declareDoors: false)),
      );

      expect(routes.every((r) => !r.ordinalsTrusted), isTrue);
    });

    test('an unreachable pair is recorded, not dropped', () {
      final plan = buildWing().copyWith(
        storedOpenings: const [],
        declaredDoorCounts: const {},
      );
      final routes = PlanEvaluation.auditRoutes(plan, RoomNavGraph.build(plan));

      expect(routes, isNotEmpty);
      expect(routes.every((r) => !r.reachable), isTrue);
    });
  });

  group('the report', () {
    test('refuses to print a figure with no ground truth', () {
      final report = PlanEvaluation.run(buildWing());

      expect(report.hasGroundTruth, isFalse);
      expect(report.topology, isNull);

      final markdown = report.toMarkdown();
      expect(markdown, contains('**Not measured.**'));
      expect(markdown, isNot(contains('Precision |')));
      // "not measured" and "measured as zero" are different claims.
      expect(markdown, isNot(contains('0.0%')));
    });

    test('prints the measured numbers when ground truth is supplied', () {
      final report = PlanEvaluation.run(
        buildWing(),
        groundTruth: PlanGroundTruth.parse(trueAdjacencies),
      );

      final markdown = report.toMarkdown();
      expect(markdown, contains('| Precision | 100.0% |'));
      expect(markdown, contains('| Recall | 100.0% |'));
      expect(markdown, isNot(contains('Not measured')));
    });

    test('leaves the walked-OK column blank for a human to fill in', () {
      final report = PlanEvaluation.run(
        buildWing(),
        groundTruth: PlanGroundTruth.parse(trueAdjacencies),
        routeSample: 4,
      );
      final markdown = report.toMarkdown();

      expect(markdown, contains('Walked OK?'));
      // Nothing pre-filled — a plausible guess here is exactly the failure
      // §10 warns about.
      expect(markdown, isNot(contains('| yes | yes |')));
      expect(markdown, contains('**Walk each route below and mark it.**'));
    });

    test('names rooms that are drawn but cannot be walked to', () {
      final plan = buildWing();
      final stranded = plan.copyWith(
        storedOpenings: [
          for (final opening in plan.openings)
            if (opening.id != 'd-n3') opening,
        ],
      );

      final report = PlanEvaluation.run(stranded);

      // 'laboratory GF 4' before rooms stopped being numbered.
      expect(report.unreachableRooms, contains('laboratory'));
      expect(report.toMarkdown(), contains('Rooms drawn but unreachable'));
    });

    test('says which units it is in, so nobody reads plan units as metres', () {
      expect(
        PlanEvaluation.run(buildWing()).toMarkdown(),
        contains('plan units (unitless)'),
      );
      expect(
        PlanEvaluation.run(buildWing().copyWith(metresPerUnit: 1)).toMarkdown(),
        contains('metres'),
      );
    });

    test('an empty plan produces a report rather than an exception', () {
      final report = PlanEvaluation.run(RoomPlan.empty);

      expect(report.routes, isEmpty);
      expect(report.toMarkdown(), contains('Floor plan evaluation'));
    });
  });
}
