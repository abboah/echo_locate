// How far along a floor is, and what to do about it next.
//
// The piece that turns a pile of capable screens into a task somebody can
// finish. Everything below is derived from the plan itself — nothing is stored,
// nothing has to be kept in step — so a floor's state is always exactly what
// its geometry says it is, including after somebody else edits it.
//
// The stages are ordered by **what blocks navigation**, not by how much work
// each represents. A floor with forty rooms and no doors routes exactly as
// badly as a floor with two, so it sits at the same stage. That ordering is
// what makes "what should I do next" answerable.

import '../../core/models/building.dart' show BuildingFloor;
import '../../core/models/room_plan.dart';
import 'room_graph.dart';

/// What is standing between this floor and being navigable.
enum FloorMappingStage {
  /// Nobody has captured or traced it.
  notStarted,

  /// Rooms exist and nothing joins them. The most common half-finished state,
  /// because placing doors comes after the satisfying part.
  needsDoors,

  /// Doors exist but part of the floor cannot be reached from the rest —
  /// usually two wings sitting side by side with nothing between them.
  disconnected,

  /// A corridor's door count was declared and not met, so spoken directions
  /// are withholding "the second door on your left".
  countsPending,

  /// Routable, and every ordinal safe to speak.
  ready;

  /// Whether guidance can actually use this floor.
  bool get isNavigable => this == ready || this == countsPending;
}

/// One floor's state, and the single next thing worth doing to it.
class FloorMappingStatus {
  const FloorMappingStatus({
    required this.floor,
    required this.plan,
    required this.stage,
    required this.roomCount,
    required this.doorCount,
    required this.roomsWithoutDoors,
    required this.strandedRooms,
    required this.undeclaredDoors,
  });

  final BuildingFloor floor;

  /// Null when nothing has been captured.
  final RoomPlan? plan;

  final FloorMappingStage stage;
  final int roomCount;
  final int doorCount;

  /// Rooms with no door at all — the actionable count, and the one the hub
  /// leads with.
  final int roomsWithoutDoors;

  /// Rooms that have doors and still cannot be reached from the rest.
  final int strandedRooms;

  /// Doors declared on corridors and not yet placed.
  final int undeclaredDoors;

  static FloorMappingStatus of(BuildingFloor floor, RoomPlan? plan) {
    if (plan == null || plan.drawableRooms.isEmpty) {
      return FloorMappingStatus(
        floor: floor,
        plan: plan,
        stage: FloorMappingStage.notStarted,
        roomCount: 0,
        doorCount: 0,
        roomsWithoutDoors: 0,
        strandedRooms: 0,
        undeclaredDoors: 0,
      );
    }

    final rooms = plan.drawableRooms.toList();
    final doorless = [
      for (final room in rooms)
        if (plan.openingsOn(room.id).isEmpty) room,
    ].length;

    // Reachability only means anything once something is joined at all.
    var stranded = 0;
    if (plan.openings.isNotEmpty && rooms.length > 1) {
      final reachable = RoomNavGraph.build(plan).reachableRooms(rooms.first.id);
      stranded = [
        for (final room in rooms)
          if (!reachable.contains(room.id) &&
              plan.openingsOn(room.id).isNotEmpty)
            room,
      ].length;
    }

    final shortfall = plan.incompleteCorridors.values.fold<int>(
      0,
      (sum, missing) => sum + missing,
    );

    return FloorMappingStatus(
      floor: floor,
      plan: plan,
      // Ordered by what blocks navigation. Doors first because without them
      // there is no graph at all; disconnection next because half a building
      // is unreachable; counts last because the floor routes, it just will not
      // say which door.
      stage: switch (0) {
        _ when doorless > 0 => FloorMappingStage.needsDoors,
        _ when stranded > 0 => FloorMappingStage.disconnected,
        _ when shortfall != 0 => FloorMappingStage.countsPending,
        _ => FloorMappingStage.ready,
      },
      roomCount: rooms.length,
      doorCount: plan.openings.length,
      roomsWithoutDoors: doorless,
      strandedRooms: stranded,
      undeclaredDoors: shortfall,
    );
  }

  /// One line saying where this floor stands.
  String get summary => switch (stage) {
    FloorMappingStage.notStarted => 'Not mapped yet',
    FloorMappingStage.needsDoors =>
      '$roomCount room${roomCount == 1 ? "" : "s"} · '
          '$roomsWithoutDoors with no door yet',
    FloorMappingStage.disconnected =>
      '$roomCount rooms · $strandedRooms cut off from the rest',
    FloorMappingStage.countsPending =>
      '$roomCount rooms · $undeclaredDoors declared door'
          '${undeclaredDoors == 1 ? "" : "s"} not placed',
    FloorMappingStage.ready =>
      '$roomCount rooms · $doorCount doors · ready to navigate',
  };

  /// What the button says.
  String get nextActionLabel => switch (stage) {
    FloorMappingStage.notStarted => 'Start mapping',
    FloorMappingStage.needsDoors => 'Add doors',
    FloorMappingStage.disconnected => 'Join it up',
    FloorMappingStage.countsPending => 'Finish door counts',
    FloorMappingStage.ready => 'Check it',
  };

  /// Why that is the next thing, in the terms the person can act on.
  ///
  /// [canScan] keeps it honest on a phone that cannot: offering AR to somebody
  /// whose device Google never certified is advice they cannot take, and the
  /// screen has already told them so once.
  String get nextActionReason => switch (stage) {
    FloorMappingStage.notStarted =>
      'Trace the rooms off the plan posted on the wall.',
    FloorMappingStage.needsDoors =>
      'Rooms with no door are drawn on the map and cannot be walked to. '
          'Stand in each doorway and record it.',
    FloorMappingStage.disconnected =>
      'Part of this floor is an island. Usually it is a corridor that '
          'was never drawn: trace the hallway joining the two parts and '
          'end it on the corridor already there, so the two snap together.',
    FloorMappingStage.countsPending =>
      'Spoken directions will not say "the second door on your left" until '
          'the doors you counted are all placed.',
    FloorMappingStage.ready =>
      'Walk a few of the routes it generates and check they are right.',
  };

  /// Whether the plan is worth opening in the editor or the evaluator.
  bool get hasPlan => stage != FloorMappingStage.notStarted;
}

/// A building's floors and how far each has got.
class BuildingMappingProgress {
  const BuildingMappingProgress(this.floors);

  final List<FloorMappingStatus> floors;

  bool get isEmpty => floors.isEmpty;

  int get mappedFloors =>
      floors.where((f) => f.stage != FloorMappingStage.notStarted).length;

  int get navigableFloors => floors.where((f) => f.stage.isNavigable).length;

  /// The floor to point somebody at.
  ///
  /// A floor part-way through beats one not started: finishing something is
  /// worth more than beginning something, and a half-mapped floor is the one
  /// that will be forgotten. Among unfinished floors the earliest wins, so the
  /// building fills from the ground up the way a person walks it.
  FloorMappingStatus? get nextFloor {
    for (final floor in floors) {
      if (floor.stage != FloorMappingStage.notStarted &&
          floor.stage != FloorMappingStage.ready) {
        return floor;
      }
    }
    for (final floor in floors) {
      if (floor.stage == FloorMappingStage.notStarted) return floor;
    }
    return null;
  }

  /// Whether every floor is navigable — the thing being worked towards.
  bool get isComplete =>
      floors.isNotEmpty && floors.every((f) => f.stage.isNavigable);

  /// A sentence for the top of the screen.
  String get summary {
    if (floors.isEmpty) return 'This building has no floors listed.';
    if (isComplete) {
      return 'All ${floors.length} floor${floors.length == 1 ? "" : "s"} '
          'ready to navigate.';
    }
    if (mappedFloors == 0) {
      return '${floors.length} floor${floors.length == 1 ? "" : "s"} to map.';
    }
    return '$navigableFloors of ${floors.length} floors ready · '
        '${mappedFloors - navigableFloors} in progress';
  }
}
