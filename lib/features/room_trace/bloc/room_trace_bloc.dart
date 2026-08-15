import 'dart:async';
import 'dart:ui' show Offset;

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

// `show BuildingFloor` on purpose: building.dart also exports a `Room`, which
// is a directory listing (name, distance, kind) rather than a shape. Importing
// it wholesale would collide with the geometric [Room] this file is built
// around, and the two are different enough that aliasing one would only move
// the confusion somewhere harder to see.
import '../../../core/models/building.dart' show BuildingFloor;
import '../../../core/models/room_plan.dart';
import '../../../core/utils/logger.dart';
import '../../../services/mapping/plan_photo_service.dart';
import '../../../services/mapping/board_rectification.dart';
import '../../../services/mapping/room_cleanup.dart';
import '../../../services/mapping/room_geometry.dart';
import '../../../services/mapping/room_graph.dart';
import '../../buildings/building_repository.dart';
import '../room_plan_repository.dart';

part 'room_trace_event.dart';
part 'room_trace_state.dart';

/// Tracing room *areas* off a photographed wall board — floorplan spec §9.
///
/// The counterpart to `PlanTraceBloc`, which traces landmark *points* onto the
/// same kind of photograph. Both exist because they answer different questions:
/// points are enough to route and to speak guidance, and that is the path that
/// already works end to end. Areas are what let the app draw a floor plan
/// somebody can read, and — the part that actually matters — what make it
/// possible to say "the second door on your left", because that sentence needs
/// to know which wall a door is in and what else is on that wall.
///
/// **No ARCore anywhere in here.** The spec's §11 puts native AR capture first
/// and this ninth, as a fallback. That order is inverted for this team: the
/// test device is not ARCore-certified, so the fallback is the only path that
/// runs, and it happens to reuse the entire renderer, graph and directions
/// layer unchanged. A building gets populated in about fifteen minutes on any
/// phone.
///
/// ## Units
///
/// Taps arrive as fractions of the plan photo's width and are stored as-is, so
/// the plan is **unitless** — see [RoomPlan.metresPerUnit]. Nobody is asked how
/// many metres apart two points on a wall board are, because nobody knows.
/// Routing is identical either way; only spoken distances are withheld.
class RoomTraceBloc extends Bloc<RoomTraceEvent, RoomTraceState> {
  RoomTraceBloc(this._plans, this._photos, this._buildings)
    : super(const RoomTraceState()) {
    on<RoomTraceStarted>(_onStarted);
    on<RoomPhotoTaken>(_onPhotoTaken);
    on<RoomPhotoSkipped>(_onPhotoSkipped);
    on<RoomPhotoPicked>(_onPhotoPicked);
    on<RoomCornerTapped>(_onCornerTapped);
    on<RoomCornerUndone>(_onCornerUndone);
    on<RoomClosed>(_onRoomClosed);
    on<HallPointTapped>(_onHallPointTapped);
    on<CorridorPathClosed>(_onCorridorPathClosed);
    on<StairsTapped>(_onStairsTapped);
    on<RoomDiscarded>(_onRoomDiscarded);
    on<RoomDeleted>(_onRoomDeleted);
    on<BoardCornerTapped>(_onBoardCornerTapped);
    on<BoardCornerUndone>(_onBoardCornerUndone);
    on<BoardRectificationCleared>(_onRectificationCleared);
    on<ScalePointTapped>(_onScalePointTapped);
    on<ScaleDeclared>(_onScaleDeclared);
    on<ScaleCleared>(_onScaleCleared);
    on<RoomTraceModeChanged>(_onModeChanged);
    on<RoomDoorTapped>(_onDoorTapped);
    on<RoomDoorRemoved>(_onDoorRemoved);
    on<CorridorDoorCountDeclared>(_onDoorCountDeclared);
    on<StubRoomAdded>(_onStubRoomAdded);
    on<TraceUndone>(_onUndone);
    on<RoomTraceSaved>(_onSaved);
  }

  final RoomPlanRepository _plans;
  final PlanPhotoService _photos;
  final BuildingRepository _buildings;

  PlanPhotoService get photos => _photos;

  /// How close, in plan units, a door tap must land to a room's wall to be
  /// taken as a door in that wall.
  ///
  /// Plan units are fractions of the image width, so 0.03 is 3% of the plan's
  /// width — a few millimetres on a printed board, and comfortably larger than
  /// the gap a finger leaves between two rooms drawn back to back.
  static const double doorSnapRadius = 0.03;

  /// Shortest edge kept when cleaning a traced room, **in plan units**.
  ///
  /// `cleanupPolygon`'s own default is 30 cm, which is right for a plan
  /// captured in AR and catastrophic here: a traced plan's coordinates are
  /// fractions of the image width, so 0.30 is a third of the entire building
  /// and every wall in every room is "too short". The first version of this
  /// bloc passed the default and quietly deleted rooms down to triangles.
  ///
  /// 1% of the plan's width is about a millimetre on a printed wall board —
  /// below what a finger can place deliberately, above the jitter of a tap.
  static const double minEdgeUnits = 0.01;

  /// Plan units left between a newly opened wing and everything already
  /// traced. See [_openWing].
  static const double parkingGapUnits = 0.5;

  /// How wide a corridor drawn as a path is made, in plan units.
  ///
  /// One plan unit is the width of the photographed board, which on a posted
  /// floor plan is very nearly the width of the floor. A teaching building's
  /// corridors run about 2 m on a 50 m frontage, so 0.02 of the board is close
  /// on the buildings this was written for and — the part that matters — is
  /// only ever the width it is *drawn*. Nothing routes on it: routing follows
  /// the centreline, and the centreline is where the contributor tapped.
  static const double corridorWidthUnits = 0.02;

  /// How near an existing hallway's centreline a tap must land to join it.
  ///
  /// Larger than [cornerSnapRadius], because a junction is judged by eye
  /// against a line drawn down the middle of a corridor rather than against a
  /// corner you can see on the board. Still under half a corridor's width, so
  /// two parallel halls cannot capture each other's taps.
  static const double hallSnapRadius = 0.02;

  /// Side of the square a stairs tap leaves behind, in plan units.
  ///
  /// Deliberately small. It is a marker saying "the stairs are here", not a
  /// traced stairwell, and drawing it larger than it is would have door
  /// inference snapping unrelated walls to it.
  static const double stairMarkerUnits = 0.025;

  /// How far from a stairs tap to look for something to connect it to.
  ///
  /// Generous compared with [doorSnapRadius], because a stairs tap lands in the
  /// middle of the stairwell rather than on a wall, and the wall of the corridor
  /// outside it is half a stairwell away.
  static const double stairLinkRadius = 0.06;

  /// How many changes to the floor can be taken back.
  ///
  /// Snapshots of a plan, not diffs — a floor is a few hundred small objects
  /// and the whole point of an immutable model is that keeping one costs a
  /// pointer. Thirty is far more than anybody reaches for and still nothing.
  static const int maxUndoSteps = 30;

  /// The floor before each of the last [maxUndoSteps] changes, oldest first.
  ///
  /// The draft rides along so undoing a room that closed wrongly gives back the
  /// corners that were tapped, rather than an empty canvas and the job to do
  /// again.
  final List<({RoomPlan plan, List<Offset> draft})> _history = [];

  /// Whether the event being handled is one whose result can be taken back.
  ///
  /// Set from the event itself in [onEvent] and read in [onChange], so it can
  /// never be left set by a handler that decided to refuse.
  bool _undoable = false;

  /// Whether there is anything to take back.
  ///
  /// On the bloc rather than in the state, because the alternative is threading
  /// a count through every `copyWith` in this file and losing it the first time
  /// somebody adds a tool and forgets. The history only ever changes alongside a
  /// state change, so a `context.watch` rebuild always reads a current answer.
  bool get canUndo => _history.isNotEmpty;

  int _nextId = 1;

  String? _wingId;

  String _id(String prefix) => '$prefix-${_nextId++}';

  /// Starts a new wing on [plan], parked clear of whatever is already there.
  ///
  /// Wings are not an AR-only idea. A floor with **two wall boards** — one per
  /// wing, which is how big buildings sign themselves — is exactly the same
  /// problem: two photographs, two coordinate frames, each internally
  /// consistent and saying nothing about where the other sits. Tracing the
  /// second onto the first's coordinates would overlay two unrelated
  /// buildings.
  ///
  /// So each tracing session gets its own wing and is parked beside the floor
  /// until somebody aligns it in the editor, exactly as a second AR session is.
  /// That also makes the alignment editor reachable on a phone with no ARCore,
  /// which until now it was not — the whole feature was unverifiable by anyone
  /// without certified hardware.
  ///
  /// The first wing on an empty floor is not parked: there is nothing to be
  /// clear of, and its own frame is as good an origin as any.
  RoomPlan _openWing(RoomPlan plan) {
    final wingId = 'wing-${plan.wingIds.length + 1}';
    _wingId = wingId;

    if (plan.drawableRooms.isEmpty) return plan;

    return plan.placeWing(
      wingId,
      WingPlacement(dx: plan.bounds.right + parkingGapUnits),
    );
  }

  /// Carries on in the frame the floor was already traced in.
  ///
  /// The counterpart to [_openWing], and the distinction is which *photograph*
  /// the coordinates belong to — not which visit to the screen.
  ///
  /// [_openWing] used to run on every start, so re-opening a finished floor to
  /// add one corridor minted a wing and parked it half a floor east. The
  /// corridor was then drawn into that parked frame and came out stranded in
  /// empty space beside the building, joined to nothing — which is exactly how
  /// a stray corridor ended up in the far east of the KNUST Library ground
  /// floor. The contributor had done nothing wrong.
  ///
  /// Resuming means the same board and the same coordinates, so new rooms join
  /// the frame the last ones were traced in and nothing is displaced.
  /// Resuming also drops placements belonging to wings that have no rooms —
  /// see [RoomPlan.withoutEmptyWings]. Load time is the safe moment for it:
  /// nothing has been traced yet, so the only such entries are leftovers, and
  /// the wing [_openWing] parks before its first room is closed cannot be
  /// caught by it.
  RoomPlan _continueWing(RoomPlan plan) {
    final pruned = plan.withoutEmptyWings;
    _wingId = _lastWingIn(pruned);
    return pruned;
  }

  /// Warns that what is traced next lands beside the floor, not on it.
  ///
  /// Only when there is already a floor to be parked beside. Somebody
  /// photographing a second board has no way to know their new rooms will
  /// appear in empty space until they see it happen, and the first time it
  /// happened it read as a bug rather than as a step.
  String? _parkedNotice() => state.plan.drawableRooms.isEmpty
      ? null
      : 'Second board: what you trace now is parked beside the floor. '
            'Line it up in the editor when you are done.';

  /// The frame the most recently traced room belongs to.
  String _lastWingIn(RoomPlan plan) {
    for (final room in plan.storedRooms.reversed) {
      final id = room.wingId;
      if (id != null && id.isNotEmpty) return id;
    }
    return plan.wingIds.isEmpty ? 'wing-1' : plan.wingIds.last;
  }

  /// How near an existing corner a tap must land to snap onto it, in plan
  /// units.
  ///
  /// About 1.5% of the plan's width. Adjacent rooms traced one after another
  /// otherwise end up with walls that *nearly* coincide, and near-shared walls
  /// are worse than either alternative: door inference has to guess which of
  /// two almost-touching rooms a tap meant, and the missing-connection check
  /// sees a gap where there is a wall.
  static const double cornerSnapRadius = 0.015;

  /// Photo coordinates to plan space.
  ///
  /// Two corrections, in order.
  ///
  /// **The perspective first.** A board photographed at an angle is keystoned,
  /// and tracing on it bakes the distortion in invisibly — the rooms sit
  /// perfectly on the photo because the photo is wrong the same way. The
  /// homography undoes it, and is the identity until somebody outlines the
  /// board.
  ///
  /// **Then the y flip.** Image v grows downward; the plan frame is y-north,
  /// and `PlanViewport` flips it back for the canvas. Skip it and every room is
  /// mirrored about the horizontal, which looks plausible on screen and inverts
  /// every left and right the directions layer generates.
  Offset _toPlan(double u, double v) {
    final board = state.rectification.apply(Offset(u, v));
    return Offset(board.dx, -board.dy);
  }

  /// Plan space back to photo coordinates, for drawing what was traced over
  /// the picture it was traced from.
  static Offset toImage(Offset plan, Homography rectification) =>
      rectification.invert(Offset(plan.dx, -plan.dy));

  /// Rooms traced in *this* session's frame — what a tap may snap or join to.
  ///
  /// Stored rather than placed, and this wing rather than the floor. A tap
  /// arrives from [_toPlan] in the current board's coordinates, so measuring it
  /// against [RoomPlan.drawableRooms] — which has every wing's placement applied
  /// — compares two different frames and quietly answers in whichever is
  /// nearer. It cannot bite while the wings are half a floor apart, since
  /// nothing is ever within a snapping radius of anything; it would bite the
  /// moment somebody aligned the wings and came back to trace more, which is a
  /// normal thing to do and a very hard thing to debug.
  ///
  /// Restricting it to one wing is also the right rule on its own terms: two
  /// boards say nothing about where each other's rooms are, so a corner on the
  /// other board is not a corner this one can share a wall with until a person
  /// has said where the two sit.
  Iterable<Room> get _wingRooms => [
    for (final room in state.plan.storedRooms)
      if (!room.isStub && room.wingId == _wingId) room,
  ];

  /// The floor as this session sees it: this wing's rooms, in this wing's own
  /// coordinates and with no placement left to apply.
  ///
  /// For handing to the shared geometry helpers, which take a whole [RoomPlan]
  /// and quite reasonably read the placed rooms out of it. See [_wingRooms] for
  /// why a tap must not be measured against those.
  RoomPlan get _wingPlan =>
      state.plan.copyWith(storedRooms: _wingRooms.toList(), wings: const {});

  /// A corner already on the plan within [cornerSnapRadius] of [point], or null.
  ///
  /// Searched across every room in the wing, not just the one being traced: the
  /// whole point is that a wall shared with the room next door ends up genuinely
  /// shared rather than two walls a millimetre apart.
  Offset? _nearbyCorner(Offset point) {
    Offset? best;
    var bestDistance = cornerSnapRadius;
    for (final room in _wingRooms) {
      for (final corner in room.corners) {
        final distance = (corner - point).distance;
        if (distance < bestDistance) {
          bestDistance = distance;
          best = corner;
        }
      }
    }
    // The room in progress too, so closing back onto the first corner is exact.
    for (final corner in state.draft) {
      final distance = (corner - point).distance;
      if (distance < bestDistance) {
        bestDistance = distance;
        best = corner;
      }
    }
    return best;
  }

  void _onBoardCornerTapped(
    BoardCornerTapped event,
    Emitter<RoomTraceState> emit,
  ) {
    if (state.boardCorners.length >= 4) return;
    final corners = [...state.boardCorners, Offset(event.u, event.v)];

    if (corners.length < 4) {
      emit(state.copyWith(boardCorners: corners));
      return;
    }

    if (!Homography.isSaneQuad(corners)) {
      emit(
        state.copyWith(
          boardCorners: const [],
          warning:
              'Those corners cross over. Tap them round the board in '
              'order, starting at the top left.',
        ),
      );
      return;
    }

    final rectification = Homography.fromBoardCorners(corners);
    if (rectification == null) {
      emit(
        state.copyWith(
          boardCorners: const [],
          warning:
              'Could not square that up. Try tapping the four corners '
              'again.',
        ),
      );
      return;
    }

    final skew = Homography.skewDegreesOf(corners);
    emit(
      state.copyWith(
        boardCorners: corners,
        rectification: rectification,
        mode: RoomTraceMode.rooms,
        warning: skew > 35
            // Past this the aspect estimate stops being worth trusting, and a
            // fresh photo costs a contributor ten seconds.
            ? 'Squared up, but that photo is very oblique. A straighter one '
                  'would trace more accurately.'
            : 'Squared up. Rooms traced from here will not be skewed.',
      ),
    );
  }

  void _onBoardCornerUndone(
    BoardCornerUndone event,
    Emitter<RoomTraceState> emit,
  ) {
    if (state.boardCorners.isEmpty) return;
    emit(
      state.copyWith(
        boardCorners: state.boardCorners.sublist(
          0,
          state.boardCorners.length - 1,
        ),
      ),
    );
  }

  /// Throws the correction away.
  ///
  /// Rooms already traced keep the coordinates they were given, so this is not
  /// an undo — it stops *further* rooms being corrected. Said plainly rather
  /// than silently re-projecting what is already placed, which would move rooms
  /// the contributor was happy with.
  void _onRectificationCleared(
    BoardRectificationCleared event,
    Emitter<RoomTraceState> emit,
  ) {
    emit(
      state.copyWith(
        boardCorners: const [],
        rectification: Homography.identity,
        warning: state.plan.drawableRooms.isEmpty
            ? null
            : 'Rooms already traced keep their shape. Only new ones change.',
      ),
    );
  }

  void _onScalePointTapped(
    ScalePointTapped event,
    Emitter<RoomTraceState> emit,
  ) {
    final points = state.scalePoints.length >= 2
        ? [_toPlan(event.u, event.v)]
        : [...state.scalePoints, _toPlan(event.u, event.v)];
    emit(state.copyWith(scalePoints: points));
  }

  /// Turns the plan metric — floorplan spec §9's scale step.
  ///
  /// Until this, a traced plan is unitless and guidance withholds every
  /// distance, because a number invented from fractions of a photograph is a
  /// confidently wrong number in a blind user's ear. Two taps and one real
  /// measurement fix that for the whole floor: a scale bar printed on the
  /// board, a corridor paced out, or a doorway, which is 0.9 m almost
  /// everywhere.
  void _onScaleDeclared(ScaleDeclared event, Emitter<RoomTraceState> emit) {
    if (state.scalePoints.length < 2) {
      emit(state.copyWith(warning: 'Tap both ends of the span first.'));
      return;
    }
    if (event.metres <= 0) {
      emit(state.copyWith(warning: 'That distance has to be more than zero.'));
      return;
    }

    final span = (state.scalePoints[1] - state.scalePoints[0]).distance;
    if (span < 1e-6) {
      emit(
        state.copyWith(
          scalePoints: const [],
          warning: 'Those two points are the same place. Tap further apart.',
        ),
      );
      return;
    }

    emit(
      state.copyWith(
        plan: state.plan.copyWith(metresPerUnit: event.metres / span),
        scalePoints: const [],
        mode: RoomTraceMode.rooms,
        warning: 'Scale set. Distances can be spoken now.',
      ),
    );
  }

  void _onScaleCleared(ScaleCleared event, Emitter<RoomTraceState> emit) {
    emit(
      state.copyWith(
        plan: state.plan.copyWith(metresPerUnit: null),
        scalePoints: const [],
      ),
    );
  }

  Future<void> _onStarted(
    RoomTraceStarted event,
    Emitter<RoomTraceState> emit,
  ) async {
    emit(
      state.copyWith(
        buildingId: event.buildingId,
        floorId: event.floorId,
        stage: RoomTraceStage.photo,
        plan: _blankPlan(event.buildingId, event.floorId, ''),
      ),
    );

    // Real floor ids, because a saved room references a floor by its database
    // id. Inventing one produces a plan the server rejects, and the contributor
    // finds out only after tracing the whole floor.
    try {
      final floors = await _buildings.floorsOf(event.buildingId);
      if (isClosed) return;
      if (floors.isNotEmpty) {
        final floor = floors.firstWhere(
          (f) => f.id == event.floorId,
          orElse: () => floors.first,
        );
        emit(
          state.copyWith(
            floors: floors,
            floorId: floor.id,
            plan: _blankPlan(
              event.buildingId,
              floor.id,
              _codePrefixFor(floor.label),
            ),
          ),
        );
      }
    } catch (error, stack) {
      AppLogger.warn('Floors unavailable for ${event.buildingId}: $error');
      AppLogger.error('Floor load failed', error, stack);
    }

    String? recovered;

    // What has already been traced, so re-opening a part-traced floor continues
    // it rather than silently starting again and saving over it.
    try {
      final existing = await _plans.planFor(state.buildingId, state.floorId);
      if (isClosed) return;
      if (existing != null && existing.rooms.isNotEmpty) {
        // Refused rather than merged, the mirror of the guard in AR capture.
        // A captured plan is metres and a traced one is fractions of a
        // photograph's width; tracing onto one would put two coordinate
        // systems about fifty times apart into the same space.
        if (existing.isMetric) {
          emit(
            state.copyWith(
              stage: RoomTraceStage.trace,
              error:
                  'This floor was scanned in AR, which is measured in '
                  'metres. Tracing onto it would mix two different '
                  'measurements — edit the scanned plan instead.',
            ),
          );
          return;
        }
        emit(
          state.copyWith(
            plan: _continueWing(existing),
            stage: RoomTraceStage.trace,
          ),
        );
        _nextId = _highestIdIn(existing) + 1;

        // A draft that holds more than what was published is work that never
        // made it out — a crash, a swipe-away, or a save that failed. Restored
        // only when it is *richer*, so a stale draft can never eat a floor
        // somebody has since published from another device.
        final draft = await _plans.draftFor(state.buildingId, state.floorId);
        if (isClosed) return;
        if (draft != null && draft.rooms.length > existing.rooms.length) {
          // Carried in a local rather than emitted here and forgotten:
          // `warning` is deliberately not sticky, so the photo emits below
          // would wipe it and the recovery would happen in silence.
          recovered =
              'Picked up where you left off — ${draft.rooms.length} rooms '
              'from a session that was not saved.';
          emit(state.copyWith(plan: _continueWing(draft), warning: recovered));
          _nextId = _highestIdIn(draft) + 1;
        }
      } else {
        emit(state.copyWith(plan: _continueWing(state.plan)));
      }
    } catch (error) {
      AppLogger.warn('Existing room plan unavailable: $error');
    }

    final photos = await _photos.storedPhotos(state.buildingId);
    if (isClosed) return;
    final stored = photos[state.floorId];
    if (stored != null) {
      emit(
        state.copyWith(
          photoPath: stored,
          photoAspect: await _aspectOf(stored),
          stage: RoomTraceStage.trace,
          warning: recovered,
        ),
      );
      return;
    }

    final ready = await _photos.start();
    if (isClosed) return;
    emit(state.copyWith(cameraReady: ready, warning: recovered));
  }

  /// An empty plan that already knows what it is.
  ///
  /// Identity is set up front rather than filled in at save time. Left to the
  /// save, a plan traced for twenty minutes went to the repository with an
  /// empty `buildingId` and no way to file it — and the room codes came out as
  /// `" 1"`, `" 2"`, because [RoomPlan.allocateCode] had no prefix to work
  /// from. Both only show up at the very end, on real data.
  static RoomPlan _blankPlan(
    String buildingId,
    String floorId,
    String codePrefix,
  ) => RoomPlan(
    buildingId: buildingId,
    floorId: floorId,
    codePrefix: codePrefix,
    // Deliberately left null: see [RoomPlan.metresPerUnit]. A traced plan
    // is unitless and nothing may speak distances from it.
  );

  /// Room-code prefix for a floor labelled [label] — `'G'` gives `'GF 1'`.
  ///
  /// Matches how the codes are painted on the boards being traced, which is
  /// the point: a contributor checking their work against the wall should see
  /// the same string.
  static String _codePrefixFor(String label) {
    final trimmed = label.trim();
    if (trimmed.isEmpty) return 'R';
    return '${trimmed.toUpperCase()}F';
  }

  /// Highest numeric suffix already used, so ids do not collide after a reload.
  static int _highestIdIn(RoomPlan plan) {
    var highest = 0;
    for (final id in [
      ...plan.storedRooms.map((r) => r.id),
      ...plan.openings.map((o) => o.id),
    ]) {
      final n = int.tryParse(id.split('-').last);
      if (n != null && n > highest) highest = n;
    }
    return highest;
  }

  /// The photo's shape, which the tracing surface is given so that the
  /// photograph and the rooms drawn on it cannot drift apart — see
  /// `PlanPhotoService.aspectOf` for the bug that motivates it.
  ///
  /// Null is a fine answer: the surface falls back to a default shape, and the
  /// coordinates stored are fractions of the width either way.
  Future<double?> _aspectOf(String? path) async {
    if (path == null) return null;
    try {
      return await _photos.aspectOf(path);
    } catch (error) {
      AppLogger.warn('Plan photo aspect unavailable: $error');
      return null;
    }
  }

  Future<void> _onPhotoTaken(
    RoomPhotoTaken event,
    Emitter<RoomTraceState> emit,
  ) async {
    final path = await _photos.capture(state.buildingId, state.floorId);
    if (isClosed) return;
    emit(
      state.copyWith(
        // A second board is a second coordinate frame — see [_openWing]. This
        // is the moment one begins, not the moment the screen opens, and only
        // when the contributor has said it is a different board.
        plan: event.newBoard ? _openWing(state.plan) : _continueWing(state.plan),
        photoPath: path,
        photoAspect: await _aspectOf(path),
        stage: RoomTraceStage.trace,
        // A failed shot is not a failed trace — the grid still works.
        warning: path == null
            ? 'Could not take the photo. Tracing on a grid.'
            : (event.newBoard ? _parkedNotice() : null),
      ),
    );
    await _photos.stop();
  }

  Future<void> _onPhotoPicked(
    RoomPhotoPicked event,
    Emitter<RoomTraceState> emit,
  ) async {
    final path = await _photos.pickFromGallery(state.buildingId, state.floorId);
    if (isClosed) return;

    if (path == null) {
      // Cancelling the picker is the common case and is not a failure — the
      // screen simply stays where it was.
      emit(state.copyWith(stage: state.stage));
      return;
    }

    emit(
      state.copyWith(
        // Same reason as [_onPhotoTaken]: a new board is a new frame, and only
        // the contributor knows whether this is one.
        plan: event.newBoard ? _openWing(state.plan) : _continueWing(state.plan),
        photoPath: path,
        photoAspect: await _aspectOf(path),
        stage: RoomTraceStage.trace,
        warning: event.newBoard ? _parkedNotice() : null,
      ),
    );
    // The camera is not needed once a photo is in hand, and holding it open
    // keeps the torch warm and the battery draining behind a tracing session
    // that can last twenty minutes.
    await _photos.stop();
  }

  Future<void> _onPhotoSkipped(
    RoomPhotoSkipped event,
    Emitter<RoomTraceState> emit,
  ) async {
    // Never a new frame — see [RoomPhotoSkipped].
    //
    // This used to park, on the reasoning that a blank grid is not the
    // photograph the existing rooms were traced against. True, and beside the
    // point: the grid is not a frame at all, and what somebody taps against is
    // the rooms drawn on it. Worse, a floor traced without a photo has no photo
    // stored, so [_onStarted] sends it back to this step on *every* visit — and
    // every visit minted another parked wing. Adding one corridor to join two
    // sections put it half a floor east of both, and doing it again would have
    // parked it again.
    emit(
      state.copyWith(
        plan: _continueWing(state.plan),
        stage: RoomTraceStage.trace,
      ),
    );
    await _photos.stop();
  }

  void _onCornerTapped(RoomCornerTapped event, Emitter<RoomTraceState> emit) {
    final tapped = _toPlan(event.u, event.v);
    // Snapped onto a corner already on the plan when there is one close by, so
    // a wall shared with the room next door is *actually* shared rather than
    // two walls a millimetre apart.
    final corner = _nearbyCorner(tapped) ?? tapped;

    emit(
      state.copyWith(
        draft: [...state.draft, corner],
        stage: RoomTraceStage.trace,
      ),
    );
  }

  void _onCornerUndone(RoomCornerUndone event, Emitter<RoomTraceState> emit) {
    if (state.draft.isEmpty) return;
    emit(state.copyWith(draft: state.draft.sublist(0, state.draft.length - 1)));
  }

  /// Closes the traced polygon into a room.
  ///
  /// Cleanup runs here and only here: short edges dropped, collinear runs
  /// merged, near-right angles snapped to the room's own grid, winding
  /// normalised. A self-intersecting trace is refused rather than stored —
  /// a bowtie has no meaningful centroid, cannot be wound consistently, and
  /// would put a room's label and its routing waypoint in unrelated places.
  void _onRoomClosed(RoomClosed event, Emitter<RoomTraceState> emit) {
    if (!state.canCloseRoom) {
      emit(state.copyWith(warning: 'A room needs at least three corners.'));
      return;
    }

    // Checked on the RAW trace, before cleanup. Snapping walls to a grid can
    // pull a crossed polygon straight, so a bowtie cleaned first comes out
    // looking like a valid room — the contributor's mistake silently accepted
    // and the wrong shape stored. What they drew is what gets judged.
    if (selfIntersects(state.draft)) {
      // Corners kept on screen deliberately: the contributor undoes the one
      // that crossed rather than retracing the whole room.
      emit(
        state.copyWith(
          warning: 'Those walls cross each other. Undo the last corner.',
        ),
      );
      return;
    }

    final cleaned = cleanupPolygon(state.draft, minEdgeMetres: minEdgeUnits);

    if (cleaned.length < 3 || selfIntersects(cleaned)) {
      emit(
        state.copyWith(
          draft: const [],
          warning: 'That shape did not come out as a room. Try again.',
        ),
      );
      return;
    }

    // The code is the id: rooms are not numbered any more, because a number
    // allocated in trace order is not the number on the door. What a room is
    // called comes from the name field or from nowhere — see
    // [Room.displayName].
    final roomId = _id('room');
    final room = Room(
      id: roomId,
      floorId: state.floorId,
      code: roomId,
      category: event.category,
      label: (event.label?.trim().isEmpty ?? true) ? null : event.label!.trim(),
      polygon: [for (final corner in cleaned) RoomCorner.of(corner)],
      // Which tracing session this came from, so a floor traced off two wall
      // boards can be aligned in the editor rather than overlaid.
      wingId: _wingId,
    );

    emit(
      state.copyWith(
        plan: state.plan.copyWith(storedRooms: [...state.plan.storedRooms, room]),
        draft: const [],
        selectedRoomId: room.id,
      ),
    );
  }

  /// Places one point on the hallway being drawn.
  ///
  /// Three things happen here that do not happen when tracing a room, and each
  /// is there because a hallway is a line *between* rooms rather than an
  /// outline *of* one.
  ///
  /// **No snapping to room corners.** Every point along a corridor has room
  /// corners within snapping distance on both sides, so the room rule dragged
  /// each tap sideways into whichever room it was passing — and the corridor
  /// came out threaded through the offices instead of down the middle.
  ///
  /// **Snapping to other hallways instead.** A floor's halls are a network:
  /// they meet at T-junctions and crossroads. Landing a tap on an existing
  /// hall's centreline joins the two exactly, which is what lets a route run
  /// from one hall into the next without anybody placing a door between them.
  ///
  /// **A warning when the new leg cuts through a room.** Said on the tap that
  /// causes it rather than at the end, because six taps later there is no way
  /// to tell which one went wrong.
  void _onHallPointTapped(HallPointTapped event, Emitter<RoomTraceState> emit) {
    final tapped = _toPlan(event.u, event.v);
    final junction = _nearestHallPoint(tapped, within: hallSnapRadius);
    final point = junction?.at ?? tapped;

    final crossed = state.draft.isEmpty
        ? null
        : _roomCrossedBetween(state.draft.last, point);

    emit(
      state.copyWith(
        draft: [...state.draft, point],
        stage: RoomTraceStage.trace,
        warning: crossed != null
            ? 'That leg runs through ${crossed.spokenName}. Undo it and tap '
                  'along the hallway itself — one tap per bend.'
            : junction != null
            ? 'Joined to ${junction.room.spokenName}.'
            : null,
      ),
    );
  }

  /// The point on another hallway's centreline nearest [at], within [within].
  ({Room room, Offset at})? _nearestHallPoint(
    Offset at, {
    required double within,
  }) {
    ({Room room, Offset at})? best;
    var bestDistance = within;

    for (final room in _wingRooms) {
      if (!room.hasSpine) continue;
      final hit = projectOntoPolyline(room.spine, at);
      if (hit.distance < bestDistance) {
        bestDistance = hit.distance;
        best = (room: room, at: hit.at);
      }
    }
    return best;
  }

  /// A traced room the segment a→b passes through, if any.
  ///
  /// Circulation is skipped: a hall legitimately runs into another hall, and a
  /// staircase marker sits in the corridor outside it by design.
  Room? _roomCrossedBetween(Offset a, Offset b) {
    for (final room in _wingRooms) {
      if (room.isCirculation) continue;
      if (segmentEntersPolygon(room.corners, a, b)) return room;
    }
    return null;
  }

  /// Finishes a hallway drawn as a path.
  ///
  /// The corners of a corridor are the least interesting thing about it and the
  /// most work to tap: a long L-shaped hallway is six or eight corners, placed
  /// on the thinnest lines on the board, and none of them is what a walker
  /// follows. The line down the middle is three or four taps, it is the thing
  /// routing wants, and the outline can be generated from it.
  ///
  /// So the polygon here is derived and the centreline is stored — see
  /// [Room.centreline] for what each is used for afterwards.
  void _onCorridorPathClosed(
    CorridorPathClosed event,
    Emitter<RoomTraceState> emit,
  ) {
    if (!state.canCloseCorridor) {
      emit(state.copyWith(warning: 'A corridor needs at least two points.'));
      return;
    }

    final path = _thinPath(state.draft);
    if (path.length < 2) {
      emit(
        state.copyWith(
          draft: const [],
          warning: 'Those points are all in the same place. Tap further apart.',
        ),
      );
      return;
    }

    final outline = ribbonAround(path, corridorWidthUnits / 2);
    if (outline.length < 3) {
      emit(
        state.copyWith(
          draft: const [],
          warning: 'That path did not come out as a corridor. Try again.',
        ),
      );
      return;
    }

    // The code is the id: rooms are not numbered any more, because a number
    // allocated in trace order is not the number on the door. What a room is
    // called comes from the name field or from nowhere — see
    // [Room.displayName].
    final roomId = _id('room');
    final room = Room(
      id: roomId,
      floorId: state.floorId,
      code: roomId,
      category: event.category,
      label: (event.label?.trim().isEmpty ?? true) ? null : event.label!.trim(),
      polygon: [for (final corner in outline) RoomCorner.of(corner)],
      centreline: [for (final point in path) RoomCorner.of(point)],
      wingId: _wingId,
    );

    // Junctions with halls already on the floor, one opening each.
    //
    // Without these a floor's hallways are a set of disconnected lines: two
    // corridors meeting at a T are two rooms whose polygons overlap and whose
    // graphs never touch, so a route from one to the other comes back null and
    // the floor reads "not joined up" with nothing on screen to say why. The
    // contributor already said where they meet — that is what the tap that
    // snapped onto the other hall's centreline meant.
    final joins = <String, Offset>{};
    for (final point in path) {
      final hit = _nearestHallPoint(point, within: hallSnapRadius);
      if (hit != null) joins.putIfAbsent(hit.room.id, () => point);
    }

    final openings = [
      ...state.plan.storedOpenings,
      for (final entry in joins.entries)
        Opening(
          id: _id('door'),
          roomAId: room.id,
          roomBId: entry.key,
          at: RoomCorner.of(entry.value),
          // A corridor running into a corridor is an opening, not a door;
          // the phrasing downstream says "through the archway" rather than
          // inventing a door nobody has to open.
          isDoor: false,
        ),
    ];

    emit(
      state.copyWith(
        plan: state.plan.copyWith(
          storedRooms: [...state.plan.storedRooms, room],
          storedOpenings: openings,
        ),
        draft: const [],
        selectedRoomId: room.id,
        warning: joins.isEmpty
            ? 'Corridor drawn. Routes will follow the line you tapped.'
            : 'Corridor drawn and joined to ${joins.length} other '
                  '${joins.length == 1 ? "hallway" : "hallways"}.',
      ),
    );
  }

  /// Drops points too close together to be separate corners of a path.
  ///
  /// The closed-polygon cleanup cannot be reused: `dropShortEdges` treats the
  /// list as a ring and would join the last point back to the first, which for
  /// a corridor is the two ends of the hallway.
  static List<Offset> _thinPath(List<Offset> points) {
    if (points.length < 2) return points;
    final out = <Offset>[points.first];
    for (final point in points.skip(1)) {
      if ((point - out.last).distance >= minEdgeUnits) out.add(point);
    }
    // The last tap is where the contributor meant the corridor to end, so it
    // survives even when it landed close to the one before it.
    if (out.length >= 2 && out.last != points.last) {
      out[out.length - 1] = points.last;
    }
    return out;
  }

  /// Marks a staircase or lift with one tap, and joins it to what is around it.
  ///
  /// The connection is the point. A staircase nobody joined to the corridor
  /// outside it is a picture of some stairs: it is drawn on the plan, it is
  /// unreachable in the graph, and the floor reads as "not joined up" for a
  /// reason nothing on screen explains. So the tap does both jobs — a marker,
  /// and a door to whatever it landed in or beside.
  void _onStairsTapped(StairsTapped event, Emitter<RoomTraceState> emit) {
    final at = _toPlan(event.u, event.v);
    const half = stairMarkerUnits / 2;

    // The code is the id: rooms are not numbered any more, because a number
    // allocated in trace order is not the number on the door. What a room is
    // called comes from the name field or from nowhere — see
    // [Room.displayName].
    final roomId = _id('room');
    final room = Room(
      id: roomId,
      floorId: state.floorId,
      code: roomId,
      category: event.category,
      polygon: [
        for (final corner in [
          Offset(at.dx - half, at.dy - half),
          Offset(at.dx + half, at.dy - half),
          Offset(at.dx + half, at.dy + half),
          Offset(at.dx - half, at.dy + half),
        ])
          RoomCorner.of(corner),
      ],
      wingId: _wingId,
    );

    // Looked up against the plan as it was, so the marker cannot connect to
    // itself — its own walls are the nearest thing to its own centre.
    final neighbour = _nearestRoomTo(at, within: stairLinkRadius);

    final openings = [...state.plan.storedOpenings];
    if (neighbour != null) {
      openings.add(
        Opening(
          id: _id('door'),
          roomAId: room.id,
          roomBId: neighbour.room.id,
          at: RoomCorner.of((at + neighbour.nearest) / 2),
        ),
      );
    }

    emit(
      state.copyWith(
        plan: state.plan.copyWith(
          storedRooms: [...state.plan.storedRooms, room],
          storedOpenings: openings,
        ),
        selectedRoomId: room.id,
        warning: neighbour == null
            ? 'Stairs marked, but nothing is next to them yet. Trace the '
                  'corridor outside and place a door.'
            : 'Stairs marked and joined to ${neighbour.room.spokenName}.',
      ),
    );
  }

  /// The traced room whose boundary is nearest [at], and the point on it.
  ({Room room, Offset nearest})? _nearestRoomTo(
    Offset at, {
    required double within,
  }) {
    ({Room room, Offset nearest})? best;
    var bestDistance = within;

    for (final room in _wingRooms) {
      final corners = room.corners;
      for (var i = 0; i < corners.length; i++) {
        final a = corners[i];
        final b = corners[(i + 1) % corners.length];
        final hit = projectOntoSegment(a, b, at);
        if (hit.distance < bestDistance) {
          bestDistance = hit.distance;
          best = (room: room, nearest: a + (b - a) * hit.t);
        }
      }
    }
    return best;
  }

  void _onRoomDiscarded(RoomDiscarded event, Emitter<RoomTraceState> emit) {
    emit(state.copyWith(draft: const []));
  }

  /// Removes a room and every door that led to it.
  ///
  /// Orphaned openings are the subtle half: an opening naming a room that no
  /// longer exists puts an unroutable id into the graph, and — worse — keeps
  /// counting towards a corridor's declared door total, so the ordinals stay
  /// wrong in a way nothing on screen explains.
  void _onRoomDeleted(RoomDeleted event, Emitter<RoomTraceState> emit) {
    emit(
      state.copyWith(
        plan: state.plan.copyWith(
          storedRooms: [
            for (final room in state.plan.storedRooms)
              if (room.id != event.roomId) room,
          ],
          storedOpenings: [
            for (final opening in state.plan.storedOpenings)
              if (!opening.touches(event.roomId)) opening,
          ],
        ),
        clearSelection: true,
      ),
    );
  }

  void _onModeChanged(
    RoomTraceModeChanged event,
    Emitter<RoomTraceState> emit,
  ) {
    // Leaving room mode abandons a half-traced polygon rather than leaving it
    // to reappear later over a different room.
    emit(state.copyWith(mode: event.mode, draft: const []));
  }

  /// Places a door where the contributor tapped, inferring which rooms it joins.
  ///
  /// The alternative — pick room A from a list, then room B — is three
  /// interactions for something the geometry already knows: a door is where two
  /// walls meet, and the tap says where. Rooms whose boundary passes within
  /// [doorSnapRadius] of the tap are candidates; the two nearest become the
  /// door's sides, and a single candidate makes an exterior door.
  void _onDoorTapped(RoomDoorTapped event, Emitter<RoomTraceState> emit) {
    final at = _toPlan(event.u, event.v);

    // Shared with the AR capture flow so the rule cannot drift between them —
    // see [RoomNavGraph.inferDoorAt]. The radius differs because the units do.
    final inferred = RoomNavGraph.inferDoorAt(
      // This wing only. The tap is in this board's coordinates, and a parked
      // wing's rooms are drawn half a floor from where they are stored — so
      // asking the placed floor which wall was tapped answered "none" for every
      // door on a second board.
      _wingPlan,
      at,
      radius: doorSnapRadius,
    );
    final roomA = inferred.roomA;
    final roomB = inferred.roomB;

    if (roomA == null) {
      emit(
        state.copyWith(
          warning: 'No wall there. Tap where a door opens onto the corridor.',
        ),
      );
      return;
    }

    if (roomB != null &&
        state.plan.storedOpenings.any(
          (o) => o.touches(roomA.id) && o.touches(roomB.id),
        )) {
      emit(state.copyWith(warning: 'Those rooms already have a door.'));
      return;
    }

    emit(
      state.copyWith(
        plan: state.plan.copyWith(
          storedOpenings: [
            ...state.plan.storedOpenings,
            Opening(
              id: _id('door'),
              roomAId: roomA.id,
              roomBId: roomB?.id,
              at: RoomCorner.of(at),
            ),
          ],
        ),
        warning: roomB == null
            ? 'Placed as an exterior door — only one room borders that point.'
            : null,
      ),
    );
  }

  void _onDoorRemoved(RoomDoorRemoved event, Emitter<RoomTraceState> emit) {
    emit(
      state.copyWith(
        plan: state.plan.copyWith(
          storedOpenings: [
            for (final opening in state.plan.storedOpenings)
              if (opening.id != event.openingId) opening,
          ],
        ),
      ),
    );
  }

  void _onDoorCountDeclared(
    CorridorDoorCountDeclared event,
    Emitter<RoomTraceState> emit,
  ) {
    emit(
      state.copyWith(
        plan: state.plan.copyWith(
          declaredDoorCounts: {
            ...state.plan.declaredDoorCounts,
            event.corridorId: event.count,
          },
        ),
      ),
    );
  }

  /// Adds a room behind a door nobody opened.
  ///
  /// Only useful in one situation, and it is the situation the whole
  /// door-counting guard exists for: a corridor has eight doors, five of them
  /// lead somewhere the contributor traced, and the other three lead to offices
  /// they could not get into. Those three still have to be *counted*, or every
  /// ordinal past them is wrong. A stub carries no polygon, so it is in the
  /// graph and absent from the drawing.
  void _onStubRoomAdded(StubRoomAdded event, Emitter<RoomTraceState> emit) {
    final room = Room.stub(
      id: _id('room'),
      floorId: state.floorId,
      code: state.plan.allocateCode(),
    );
    emit(
      state.copyWith(
        plan: state.plan.copyWith(storedRooms: [...state.plan.storedRooms, room]),
        selectedRoomId: room.id,
      ),
    );
  }

  Future<void> _onSaved(
    RoomTraceSaved event,
    Emitter<RoomTraceState> emit,
  ) async {
    if (!state.canSave) {
      emit(state.copyWith(error: 'Trace at least one room first.'));
      return;
    }

    emit(state.copyWith(stage: RoomTraceStage.saving));
    try {
      await _plans.save(state.plan);
      if (isClosed) return;
      // Published, so the draft has nothing left to protect. Failures here are
      // swallowed on purpose: a draft that outlives its save is harmless — it
      // is only restored when it holds more than what was published.
      unawaited(
        _plans
            .clearDraft(state.buildingId, state.floorId)
            .catchError((Object _) {}),
      );
      emit(state.copyWith(stage: RoomTraceStage.saved));
    } catch (error, stack) {
      AppLogger.error('Room plan save failed', error, stack);
      if (isClosed) return;
      emit(
        state.copyWith(
          stage: RoomTraceStage.trace,
          error: 'Could not save the plan. It is still here — try again.',
        ),
      );
    }
  }

  /// The plan as something routable, for the live preview.
  RoomNavGraph get graph => RoomNavGraph.build(state.plan);

  /// Takes back the last change to the floor.
  void _onUndone(TraceUndone event, Emitter<RoomTraceState> emit) {
    if (_history.isEmpty) {
      emit(state.copyWith(warning: 'Nothing to undo.'));
      return;
    }

    final previous = _history.removeLast();
    emit(
      state.copyWith(
        plan: previous.plan,
        draft: previous.draft,
        // The selection is an index into the floor that just changed under it.
        // Left alone, undoing the room that was selected leaves the controls
        // describing a room that is no longer there.
        clearSelection: true,
        warning: 'Undone.',
      ),
    );
  }

  /// Notes whether what is about to happen can be taken back.
  ///
  /// See [RoomTraceEvent.changesTheFloor]. Reset on every event, so a refusal
  /// cannot leave the flag standing for whatever comes next.
  @override
  void onEvent(RoomTraceEvent event) {
    super.onEvent(event);
    _undoable = event.changesTheFloor;
  }

  /// Writes a draft whenever the floor itself changes.
  ///
  /// Hooked here rather than into each handler so a new tool cannot be added
  /// without autosave — there are already a dozen events that mutate the plan
  /// and remembering all of them is not a thing that keeps working.
  ///
  /// Only when `plan` differs, which deliberately excludes the corners of the
  /// room being drawn: those live in `state.draft` and change on every tap. The
  /// promise is that a finished room survives, not a half-tapped polygon.
  @override
  void onChange(Change<RoomTraceState> change) {
    super.onChange(change);
    final plan = change.nextState.plan;
    if (plan == change.currentState.plan) return;

    // Paired with the flag rather than taken from it alone: an event that
    // declares itself an edit and then refuses one — a door tapped at no wall —
    // never reaches here, so it cannot leave behind an undo step that does
    // nothing when taken. Cleared immediately so a handler that emits twice
    // records one step, not two.
    if (_undoable) {
      _undoable = false;
      _history.add((
        plan: change.currentState.plan,
        draft: change.currentState.draft,
      ));
      if (_history.length > maxUndoSteps) _history.removeAt(0);
    }
    if (plan.buildingId.isEmpty || plan.floorId.isEmpty) return;
    if (plan.rooms.isEmpty) return;
    // Guarded, and the try matters as much as the catchError: `onChange` runs
    // inside `emit`, so anything thrown here — including synchronously, before
    // a Future exists to attach to — takes the state change down with it. A
    // storage failure would have stopped the room the contributor just closed
    // from appearing at all, which is the exact opposite of the point.
    try {
      unawaited(
        _plans.saveDraft(plan).catchError((Object error, StackTrace _) {
          AppLogger.warn('Room plan draft not kept: $error');
        }),
      );
    } catch (error) {
      AppLogger.warn('Room plan draft not kept: $error');
    }
  }

  @override
  Future<void> close() async {
    await _photos.stop();
    return super.close();
  }
}
