// Measuring a traced plan against the building it was traced from — spec §10.
//
// ## Why this is cheap, and why that matters
//
// Evaluating an indoor navigation system normally means recruiting
// participants, getting ethics clearance, and running sessions. None of that
// is needed for the part that can actually be wrong: **the wall boards are
// already published floor plans for buildings you can walk into.** They are
// ground truth, they are free, and one person can gather the numbers in an
// afternoon.
//
// ## What can and cannot be computed
//
// The line between the two is the whole design of this file, and blurring it
// would be the easiest way to publish a false result.
//
//   * **Topology is computable.** Given the adjacencies read off the board,
//     precision and recall over the plan's edges are arithmetic. [scoreTopology]
//     returns them along with the specific pairs that were missed or invented,
//     because "recall 0.82" is a grade and "the door between GF 4 and the
//     corridor is missing" is a fix.
//
//   * **Instruction correctness is not.** A left/right swap survives every unit
//     test in this repository — the geometry is self-consistent, the sentence is
//     grammatical, and the answer is wrong. The only instrument that detects it
//     is a person walking the route. So [auditRoutes] does not score anything;
//     it produces the routes to walk and somewhere to record what happened.
//
// Nothing here invents a figure. A report with no ground truth supplied says it
// has no ground truth, rather than defaulting to a flattering number.

import 'dart:math' as math;

import '../../core/models/room_plan.dart';
import '../mapping/room_directions.dart';
import '../mapping/room_graph.dart';

/// Adjacencies read off a building's posted floor plan.
///
/// Rooms are named the way the *board* names them — "Reading Hall", "204" —
/// because that is what a person copying it down has in front of them. Matching
/// against the plan tries the room's label first and its auto-allocated code
/// second, so a contributor who typed the door names gets matched on those and
/// one who did not still gets matched on codes.
class PlanGroundTruth {
  const PlanGroundTruth(this.adjacencies);

  /// Unordered pairs of room names that the board shows a door between.
  final Set<({String a, String b})> adjacencies;

  static const PlanGroundTruth none = PlanGroundTruth({});

  bool get isEmpty => adjacencies.isEmpty;

  /// Parses the format a person can actually type on a phone while standing in
  /// a corridor: one pair per line, the two names separated by a comma, a
  /// hyphen, or a pipe.
  ///
  /// Blank lines and lines beginning `#` are skipped, so the list can carry
  /// notes about which wing is which.
  factory PlanGroundTruth.parse(String text) {
    final pairs = <({String a, String b})>{};
    for (final line in text.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;

      final parts = trimmed.split(RegExp(r'\s*[,|]\s*|\s+-\s+'));
      if (parts.length < 2) continue;
      final a = _normalise(parts[0]);
      final b = _normalise(parts[1]);
      if (a.isEmpty || b.isEmpty || a == b) continue;
      pairs.add(_ordered(a, b));
    }
    return PlanGroundTruth(pairs);
  }

  static String _normalise(String value) =>
      value.toUpperCase().replaceAll(RegExp(r'\s+'), ' ').trim();

  /// Pairs are stored with their ends sorted, so a door recorded one way round
  /// is the same door recorded the other. Without this the same board yields a
  /// different score depending on which end of each corridor was written first.
  static ({String a, String b}) _ordered(String x, String y) =>
      x.compareTo(y) <= 0 ? (a: x, b: y) : (a: y, b: x);
}

/// Precision and recall over the plan's doors, and the pairs behind them.
class TopologyScore {
  const TopologyScore({
    required this.matched,
    required this.missing,
    required this.spurious,
  });

  /// Doors the board shows and the plan has.
  final Set<({String a, String b})> matched;

  /// Doors the board shows and the plan **lacks**. These are what cost recall,
  /// and each one is a room the app may be unable to route to.
  final Set<({String a, String b})> missing;

  /// Doors the plan has and the board does **not** show. These cost precision.
  /// Worth reading rather than only counting: a "spurious" door is often a real
  /// one the board omits, and that is a finding about the board.
  final Set<({String a, String b})> spurious;

  int get truePositives => matched.length;

  /// Of the doors the plan claims, the fraction the board confirms.
  double get precision {
    final claimed = matched.length + spurious.length;
    return claimed == 0 ? 0 : matched.length / claimed;
  }

  /// Of the doors the board shows, the fraction the plan found.
  double get recall {
    final actual = matched.length + missing.length;
    return actual == 0 ? 0 : matched.length / actual;
  }

  double get f1 {
    final p = precision;
    final r = recall;
    return p + r == 0 ? 0 : 2 * p * r / (p + r);
  }
}

/// One origin–destination pair, its generated route, and room to record what
/// happened when somebody walked it.
class RouteAudit {
  const RouteAudit({
    required this.fromName,
    required this.toName,
    required this.instructions,
    required this.distance,
    required this.roomsPassed,
    required this.ordinalsTrusted,
    required this.reachable,
  });

  final String fromName;
  final String toName;

  /// Exactly what would be spoken. Printed in full, because the failure being
  /// hunted is a single wrong word inside one of these sentences.
  final List<String> instructions;

  /// Null when the plan is unitless, which is the normal case for a traced
  /// plan — see [RoomPlan.metresPerUnit].
  final double? distance;

  final int roomsPassed;

  /// Whether every corridor on this route had its declared door count met.
  ///
  /// False means the ordinals were deliberately withheld, so a walker will not
  /// hear "the second door on your left" — and the route is *not* evidence
  /// about ordinal correctness either way.
  final bool ordinalsTrusted;

  final bool reachable;
}

/// A measured result plus a walking checklist.
class EvaluationReport {
  const EvaluationReport({
    required this.plan,
    required this.topology,
    required this.routes,
    required this.hasGroundTruth,
    required this.unreachableRooms,
  });

  final RoomPlan plan;

  /// Null when no ground truth was supplied. Deliberately nullable rather than
  /// a zeroed score: "not measured" and "measured as zero" are different
  /// claims, and only one of them is honest to print.
  final TopologyScore? topology;

  final List<RouteAudit> routes;
  final bool hasGroundTruth;

  /// Rooms drawn on the plan that nothing can walk to. Almost always an
  /// untagged door, and a plan can score well on topology while still
  /// stranding one.
  final List<String> unreachableRooms;

  /// The report as Markdown, for pasting into the write-up.
  ///
  /// Blank cells are left blank on purpose. This is a form to be filled in
  /// while walking, and pre-filling any of it with a plausible guess is exactly
  /// the failure §10 warns about.
  String toMarkdown() {
    final out = StringBuffer()
      ..writeln('# Floor plan evaluation')
      ..writeln()
      ..writeln('- Building: `${plan.buildingId}`')
      ..writeln('- Floor: `${plan.floorId}`')
      ..writeln('- Rooms traced: ${plan.drawableRooms.length}')
      ..writeln('- Doors tagged: ${plan.openings.length}')
      ..writeln(
        '- Units: ${plan.isMetric ? "metres" : "plan units (unitless)"}',
      )
      ..writeln()
      ..writeln('## 1 · Topological accuracy')
      ..writeln();

    final score = topology;
    if (!hasGroundTruth || score == null) {
      out
        ..writeln('**Not measured.** No ground truth was supplied.')
        ..writeln()
        ..writeln(
          'Read the adjacencies off the posted floor plan — one pair of room '
          'names per line — and run this again. Do not report a figure '
          'without them.',
        );
    } else {
      out
        ..writeln('| Measure | Value |')
        ..writeln('| --- | --- |')
        ..writeln(
          '| Doors on the board | ${score.truePositives + score.missing.length} |',
        )
        ..writeln(
          '| Doors in the plan | ${score.truePositives + score.spurious.length} |',
        )
        ..writeln('| Matched | ${score.truePositives} |')
        ..writeln('| Precision | ${_pct(score.precision)} |')
        ..writeln('| Recall | ${_pct(score.recall)} |')
        ..writeln('| F1 | ${_pct(score.f1)} |')
        ..writeln();

      if (score.missing.isNotEmpty) {
        out
          ..writeln('### Missing from the plan (costs recall)')
          ..writeln();
        for (final pair in score.missing) {
          out.writeln('- ${pair.a} ↔ ${pair.b}');
        }
        out.writeln();
      }
      if (score.spurious.isNotEmpty) {
        out
          ..writeln('### In the plan, not on the board (costs precision)')
          ..writeln();
        out
          ..writeln(
            'Check each against the building itself before counting it as an '
            'error — boards omit real doors.',
          )
          ..writeln();
        for (final pair in score.spurious) {
          out.writeln('- ${pair.a} ↔ ${pair.b}');
        }
        out.writeln();
      }
    }

    if (unreachableRooms.isNotEmpty) {
      out
        ..writeln('### Rooms drawn but unreachable')
        ..writeln();
      for (final room in unreachableRooms) {
        out.writeln('- $room');
      }
      out.writeln();
    }

    out
      ..writeln('## 2 · Route and instruction correctness')
      ..writeln()
      ..writeln(
        'A left/right swap passes every automated test in this project: the '
        'geometry is self-consistent and the sentence is grammatical. **Walk '
        'each route below and mark it.** This section is evidence only once '
        'somebody has.',
      )
      ..writeln()
      ..writeln('| # | From | To | Rooms | Ordinals | Walked OK? | Notes |')
      ..writeln('| --- | --- | --- | --- | --- | --- | --- |');

    for (var i = 0; i < routes.length; i++) {
      final route = routes[i];
      out.writeln(
        '| ${i + 1} | ${route.fromName} | ${route.toName} | '
        '${route.reachable ? route.roomsPassed : "—"} | '
        '${route.ordinalsTrusted ? "yes" : "withheld"} |  |  |',
      );
    }

    out
      ..writeln()
      ..writeln('### The instructions, in full')
      ..writeln();

    for (var i = 0; i < routes.length; i++) {
      final route = routes[i];
      out
        ..writeln('**${i + 1}. ${route.fromName} → ${route.toName}**')
        ..writeln();
      if (!route.reachable) {
        out
          ..writeln('- _No route. The plan does not connect these._')
          ..writeln();
        continue;
      }
      for (final instruction in route.instructions) {
        out.writeln('- $instruction');
      }
      if (!route.ordinalsTrusted) {
        out.writeln(
          '- _Door ordinals withheld: a corridor on this route has doors '
          'declared but not tagged._',
        );
      }
      out.writeln();
    }

    out
      ..writeln('## 3 · Capture effort')
      ..writeln()
      ..writeln('Wall clock, filled in by hand.')
      ..writeln()
      ..writeln('| Wing | Rooms | Minutes to trace |')
      ..writeln('| --- | --- | --- |')
      ..writeln('|  |  |  |')
      ..writeln();

    return out.toString();
  }

  static String _pct(double value) => '${(value * 100).toStringAsFixed(1)}%';
}

/// Runs the §10 measurements over a traced plan.
class PlanEvaluation {
  const PlanEvaluation._();

  /// How many origin–destination pairs to put on the walking list.
  ///
  /// The spec asks for 20. It is a checklist somebody carries around a
  /// building, so the number is bounded by patience rather than by statistics.
  static const int defaultRouteSample = 20;

  static EvaluationReport run(
    RoomPlan plan, {
    PlanGroundTruth groundTruth = PlanGroundTruth.none,
    int routeSample = defaultRouteSample,
  }) {
    final graph = RoomNavGraph.build(plan);
    final rooms = plan.drawableRooms.toList()
      ..sort((a, b) => a.code.compareTo(b.code));

    return EvaluationReport(
      plan: plan,
      hasGroundTruth: !groundTruth.isEmpty,
      topology: groundTruth.isEmpty ? null : scoreTopology(plan, groundTruth),
      routes: auditRoutes(plan, graph, sample: routeSample),
      unreachableRooms: _unreachableNames(plan, graph, rooms),
    );
  }

  /// Named, sorted, and safe on an empty plan.
  ///
  /// Built in a function rather than inline: `cond ? const [] : [...]..sort()`
  /// parses as `(cond ? … : …)..sort()`, so the empty branch tried to sort a
  /// const list and threw.
  static List<String> _unreachableNames(
    RoomPlan plan,
    RoomNavGraph graph,
    List<Room> rooms,
  ) {
    if (rooms.isEmpty) return const [];
    final names = [
      for (final id in graph.unreachableFrom(rooms.first.id)) _nameOf(plan, id),
    ];
    names.sort();
    return names;
  }

  /// Precision and recall of the plan's doors against the board.
  static TopologyScore scoreTopology(
    RoomPlan plan,
    PlanGroundTruth groundTruth,
  ) {
    // Every name a room answers to, so a board naming rooms by number matches
    // a plan whose contributor typed the names, and vice versa.
    final namesOf = <String, Set<String>>{
      for (final room in plan.drawableRooms)
        room.id: {
          PlanGroundTruth._normalise(room.code),
          if (room.label != null) PlanGroundTruth._normalise(room.label!),
        },
    };

    final claimed = <({String a, String b})>{};
    for (final opening in plan.openings) {
      final b = opening.roomBId;
      // Exterior doors have nothing on the far side to pair with, and a door
      // to an untraced stub has no name the board could confirm.
      if (b == null) continue;
      final aNames = namesOf[opening.roomAId];
      final bNames = namesOf[b];
      if (aNames == null || bNames == null) continue;
      claimed.add(
        PlanGroundTruth._ordered(_preferred(aNames), _preferred(bNames)),
      );
    }

    // A claimed pair counts as matched if *any* naming of its two rooms
    // appears in the truth set — the plan may know a room by its code where
    // the board knows it by name.
    final matched = <({String a, String b})>{};
    final consumed = <({String a, String b})>{};

    for (final opening in plan.openings) {
      final b = opening.roomBId;
      if (b == null) continue;
      final aNames = namesOf[opening.roomAId];
      final bNames = namesOf[b];
      if (aNames == null || bNames == null) continue;

      ({String a, String b})? hit;
      for (final an in aNames) {
        for (final bn in bNames) {
          final candidate = PlanGroundTruth._ordered(an, bn);
          if (groundTruth.adjacencies.contains(candidate)) {
            hit = candidate;
            break;
          }
        }
        if (hit != null) break;
      }
      if (hit != null) {
        matched.add(hit);
        consumed.add(
          PlanGroundTruth._ordered(_preferred(aNames), _preferred(bNames)),
        );
      }
    }

    return TopologyScore(
      matched: matched,
      missing: {
        for (final pair in groundTruth.adjacencies)
          if (!matched.contains(pair)) pair,
      },
      spurious: {
        for (final pair in claimed)
          if (!consumed.contains(pair)) pair,
      },
    );
  }

  /// The routes to walk.
  ///
  /// Pairs are sampled **deterministically and spread across the floor**, not
  /// taken from the front of the list. The first twenty pairs of a sorted room
  /// list all start from the same room, which would test one corridor twenty
  /// times and the rest of the building never. Determinism matters separately:
  /// somebody walks this list, comes back, fixes a door, and re-runs — and the
  /// two reports have to be about the same routes.
  static List<RouteAudit> auditRoutes(
    RoomPlan plan,
    RoomNavGraph graph, {
    int sample = defaultRouteSample,
  }) {
    // Circulation is walked *through*, not *to*. Nobody navigates to a
    // corridor, so pairing them would spend the checklist on journeys no user
    // takes.
    final rooms = [
      for (final room in plan.drawableRooms)
        if (!room.isCirculation) room,
    ]..sort((a, b) => a.code.compareTo(b.code));

    if (rooms.length < 2) return const [];

    final pairs = <({Room from, Room to})>[];
    for (var i = 0; i < rooms.length; i++) {
      for (var j = 0; j < rooms.length; j++) {
        if (i != j) pairs.add((from: rooms[i], to: rooms[j]));
      }
    }

    final chosen = <({Room from, Room to})>[];
    if (pairs.length <= sample) {
      chosen.addAll(pairs);
    } else {
      // Even stride through the sorted pair list: spreads origins across the
      // whole floor without a random seed to remember.
      final stride = pairs.length / sample;
      for (var k = 0; k < sample; k++) {
        chosen.add(pairs[math.min((k * stride).floor(), pairs.length - 1)]);
      }
    }

    final directions = RoomDirections.forPlan(plan);

    return [
      for (final pair in chosen)
        _auditOne(plan, graph, directions, pair.from, pair.to),
    ];
  }

  static RouteAudit _auditOne(
    RoomPlan plan,
    RoomNavGraph graph,
    RoomDirections directions,
    Room from,
    Room to,
  ) {
    final route = graph.route(fromRoomId: from.id, toRoomId: to.id);
    if (route == null) {
      return RouteAudit(
        fromName: from.spokenName,
        toName: to.spokenName,
        instructions: const [],
        distance: null,
        roomsPassed: 0,
        ordinalsTrusted: false,
        reachable: false,
      );
    }

    final spoken = directions.describe(graph, route);

    return RouteAudit(
      fromName: from.spokenName,
      toName: to.spokenName,
      instructions: [for (final instruction in spoken) instruction.text],
      distance: plan.isMetric ? route.totalDistanceM : null,
      roomsPassed: route.roomsPassed.length,
      // Only corridors actually on this route matter. A plan with one
      // incomplete corridor in a far wing does not invalidate a route that
      // never enters it.
      ordinalsTrusted: route.roomsPassed
          .map(plan.roomOf)
          .whereType<Room>()
          .where((room) => room.isCirculation)
          .every((room) => plan.corridorIsComplete(room.id)),
      reachable: true,
    );
  }

  /// The name a room answers to on the board, preferring what a person reads.
  static String _preferred(Set<String> names) => names.length < 2
      ? names.first
      : names.reduce((a, b) => a.length >= b.length ? a : b);

  static String _nameOf(RoomPlan plan, String roomId) =>
      plan.roomOf(roomId)?.spokenName ?? roomId;
}
