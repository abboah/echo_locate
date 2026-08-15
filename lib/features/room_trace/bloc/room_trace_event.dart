part of 'room_trace_bloc.dart';

sealed class RoomTraceEvent extends Equatable {
  const RoomTraceEvent();

  /// Whether this event changes the saved floor, and so whether the state
  /// before it is worth keeping for [TraceUndone].
  ///
  /// Declared on the event rather than decided in the handler for two reasons.
  /// A handler that refuses — a door tapped at no wall, a room that cleaned up
  /// below three corners — must not leave an undo step behind that appears to do
  /// nothing when taken, and pairing this with "did the plan actually change"
  /// gets that for free. And a tool added later has to answer the question in
  /// its own declaration instead of remembering to call something.
  ///
  /// False for the ones that only move the *drawing*: tapping corners into a
  /// draft has its own undo in [RoomCornerUndone], and loading a floor or
  /// opening a wing is not an edit somebody made.
  bool get changesTheFloor => false;

  @override
  List<Object?> get props => const [];
}

/// Take back the last change to the floor.
///
/// One step per finished act — a room closed, a door placed, a room deleted —
/// not per tap. Restores the half-traced polygon that was on screen at the time
/// as well, so undoing a room that closed badly hands the corners back rather
/// than making them be tapped again.
class TraceUndone extends RoomTraceEvent {
  const TraceUndone();
}

class RoomTraceStarted extends RoomTraceEvent {
  const RoomTraceStarted({required this.buildingId, this.floorId = ''});

  final String buildingId;
  final String floorId;

  @override
  List<Object?> get props => [buildingId, floorId];
}

/// The contributor photographed the wall board, or chose to trace on a blank
/// grid because there is no camera.
///
/// [newBoard] is the one fact that decides which coordinate frame everything
/// traced next belongs to, and the app cannot work it out: two photographs of
/// the same board and photographs of two different boards are the same bytes as
/// far as it is concerned. So it is asked, and only when there is already a
/// floor for the answer to matter to — see `RoomTraceBloc._openWing`.
class RoomPhotoTaken extends RoomTraceEvent {
  const RoomPhotoTaken({this.newBoard = false});

  final bool newBoard;

  @override
  List<Object?> get props => [newBoard];
}

/// Trace on a blank grid.
///
/// Never a new frame. A blank grid has no coordinates of its own to be in, and
/// the rooms already traced are drawn on it — so somebody tapping here is
/// placing points against geometry they can see, in the frame they can see it
/// in. Parking a wing here put a corridor drawn down the middle of the board
/// half a floor to the east of the building it was meant to join.
class RoomPhotoSkipped extends RoomTraceEvent {
  const RoomPhotoSkipped();
}

/// The contributor chose a board photo already in their gallery.
class RoomPhotoPicked extends RoomTraceEvent {
  const RoomPhotoPicked({this.newBoard = false});

  final bool newBoard;

  @override
  List<Object?> get props => [newBoard];
}

/// A tap on the plan, in **image coordinates**: fractions of the displayed
/// image's width, v growing downward. Converted to plan space by the bloc —
/// see `RoomTraceBloc._toPlan`, which is where the y flip lives.
class RoomCornerTapped extends RoomTraceEvent {
  const RoomCornerTapped(this.u, this.v);

  final double u;
  final double v;

  @override
  List<Object?> get props => [u, v];
}

/// Undo the last corner of the room being traced.
class RoomCornerUndone extends RoomTraceEvent {
  const RoomCornerUndone();
}

/// Close the polygon and keep it as a room.
class RoomClosed extends RoomTraceEvent {
  const RoomClosed({required this.category, this.label});

  final RoomCategory category;
  final String? label;

  @override
  bool get changesTheFloor => true;

  @override
  List<Object?> get props => [category, label];
}

/// A tap while drawing a hallway: one point on its centreline.
///
/// Deliberately **not** [RoomCornerTapped]. That one snaps onto the nearest
/// traced room corner so that adjacent rooms end up sharing a wall, which is
/// right for a room and exactly wrong here: a hallway runs *between* rooms, so
/// every tap along it has room corners within snapping distance on both sides,
/// and the line being drawn gets pulled into the rooms it is supposed to run
/// past. See `RoomTraceBloc._onHallPointTapped`.
class HallPointTapped extends RoomTraceEvent {
  const HallPointTapped(this.u, this.v);

  final double u;
  final double v;

  @override
  List<Object?> get props => [u, v];
}

/// Finish the path being drawn and keep it as a corridor.
///
/// The counterpart to [RoomClosed] for circulation space: the taps are the line
/// down the middle of the hallway rather than its corners, and the polygon is
/// generated around them. See [Room.centreline].
class CorridorPathClosed extends RoomTraceEvent {
  const CorridorPathClosed({this.label, this.category = RoomCategory.corridor});

  final String? label;

  /// Corridor unless the contributor says otherwise — a covered walkway or a
  /// balcony run is the same shape and the same kind of thing to walk down.
  final RoomCategory category;

  @override
  bool get changesTheFloor => true;

  @override
  List<Object?> get props => [label, category];
}

/// A tap in stairs mode: mark where a staircase or lift is.
class StairsTapped extends RoomTraceEvent {
  const StairsTapped(this.u, this.v, {this.category = RoomCategory.staircase});

  final double u;
  final double v;
  final RoomCategory category;

  @override
  bool get changesTheFloor => true;

  @override
  List<Object?> get props => [u, v, category];
}

/// Abandon the room being traced without keeping it.
class RoomDiscarded extends RoomTraceEvent {
  const RoomDiscarded();
}

class RoomDeleted extends RoomTraceEvent {
  const RoomDeleted(this.roomId);

  final String roomId;

  @override
  bool get changesTheFloor => true;

  @override
  List<Object?> get props => [roomId];
}

/// A tap while squaring the board up: one of its four corners.
class BoardCornerTapped extends RoomTraceEvent {
  const BoardCornerTapped(this.u, this.v);

  final double u;
  final double v;

  @override
  List<Object?> get props => [u, v];
}

class BoardCornerUndone extends RoomTraceEvent {
  const BoardCornerUndone();
}

/// Throw away the perspective correction and trace on the raw photo.
class BoardRectificationCleared extends RoomTraceEvent {
  const BoardRectificationCleared();
}

/// A tap while setting the scale: one end of a span of known length.
class ScalePointTapped extends RoomTraceEvent {
  const ScalePointTapped(this.u, this.v);

  final double u;
  final double v;

  @override
  List<Object?> get props => [u, v];
}

/// How many metres the two tapped points are really apart.
class ScaleDeclared extends RoomTraceEvent {
  const ScaleDeclared(this.metres);

  final double metres;

  @override
  bool get changesTheFloor => true;

  @override
  List<Object?> get props => [metres];
}

class ScaleCleared extends RoomTraceEvent {
  const ScaleCleared();

  @override
  bool get changesTheFloor => true;
}

/// Switch between tracing rooms and placing doors.
class RoomTraceModeChanged extends RoomTraceEvent {
  const RoomTraceModeChanged(this.mode);

  final RoomTraceMode mode;

  @override
  List<Object?> get props => [mode];
}

/// A tap in door mode: the bloc works out which rooms' walls it fell between.
class RoomDoorTapped extends RoomTraceEvent {
  const RoomDoorTapped(this.u, this.v);

  final double u;
  final double v;

  @override
  bool get changesTheFloor => true;

  @override
  List<Object?> get props => [u, v];
}

class RoomDoorRemoved extends RoomTraceEvent {
  const RoomDoorRemoved(this.openingId);

  final String openingId;

  @override
  bool get changesTheFloor => true;

  @override
  List<Object?> get props => [openingId];
}

/// The number of doors the contributor counted by eye on a corridor's walls.
///
/// The guard on the door-ordinal failure — see [RoomPlan.corridorIsComplete].
class CorridorDoorCountDeclared extends RoomTraceEvent {
  const CorridorDoorCountDeclared({
    required this.corridorId,
    required this.count,
  });

  final String corridorId;
  final int count;

  @override
  bool get changesTheFloor => true;

  @override
  List<Object?> get props => [corridorId, count];
}

/// Add a room nobody traced, for a door on a corridor wall that was counted but
/// never opened — floorplan spec §6.3.
class StubRoomAdded extends RoomTraceEvent {
  const StubRoomAdded();

  @override
  bool get changesTheFloor => true;
}

class RoomTraceSaved extends RoomTraceEvent {
  const RoomTraceSaved();
}
