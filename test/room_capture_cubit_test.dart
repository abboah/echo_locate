import 'dart:async';

import 'package:echo_locate/core/models/building.dart' show BuildingFloor;
import 'package:echo_locate/core/models/room_plan.dart';
import 'package:echo_locate/features/buildings/building_repository.dart';
import 'package:echo_locate/features/room_capture/bloc/room_capture_cubit.dart';
import 'package:echo_locate/features/room_trace/room_plan_repository.dart';
import 'package:echo_locate/services/mapping/room_geometry.dart';
import 'package:echo_locate/services/mapping/room_graph.dart';
import 'package:echo_locate/services/mapping/room_plan_bridge.dart';
import 'package:echo_locate/services/vision/arcore_capture_service.dart';
import 'package:echo_locate/services/vision/depth_frame.dart'
    show ArCoreAvailability;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockPlans extends Mock implements RoomPlanRepository {}

class _MockBuildings extends Mock implements BuildingRepository {}

/// A capture service with no phone behind it.
///
/// The whole point: everything above the platform channel can be proven on a
/// desk, so when a certified device does arrive the only unknowns left are the
/// hit-test geometry and the preview's orientation.
class _FakeCapture implements ArCoreCaptureService {
  /// Mutable rather than a constructor argument: tests that need an
  /// uncertified device set it after construction, which reads better than
  /// threading it through every helper.
  ArCoreAvailability availability = ArCoreAvailability.supported;
  String? startFailure;

  final _controller = StreamController<CaptureFrame>.broadcast();

  /// Hits handed back in order; null means "the tap hit nothing".
  final List<CapturedCorner?> hits = [];
  int _hitIndex = 0;

  /// What ARCore was told it is drawing into — the thing that makes taps
  /// land where they were made. The display rotation is no longer part of it:
  /// native reads that from the activity, since Dart cannot.
  (int, int)? viewport;

  int planeResets = 0;
  bool stopped = false;
  final List<(double, double)> taps = [];

  /// Whether each tap asked to be held to the room's locked surface. Corners
  /// do; doors deliberately do not.
  final List<bool> tapLocks = [];

  bool _running = false;

  void emit(CaptureFrame frame) => _controller.add(frame);

  @override
  bool get isRunning => _running;

  @override
  int? get textureId => _running ? 7 : null;

  @override
  Future<ArCoreAvailability> checkAvailability() async => availability;

  @override
  Future<String?> start({
    required int viewWidth,
    required int viewHeight,
  }) async {
    viewport = (viewWidth, viewHeight);
    if (startFailure != null) return startFailure;
    _running = true;
    return null;
  }

  @override
  Future<void> stop() async {
    stopped = true;
    _running = false;
    await _controller.close();
  }

  @override
  Future<CapturedCorner?> hitTest(
    double u,
    double v, {
    bool lock = true,
  }) async {
    taps.add((u, v));
    tapLocks.add(lock);
    if (_hitIndex >= hits.length) return null;
    return hits[_hitIndex++];
  }

  @override
  Future<void> setViewport({
    required int viewWidth,
    required int viewHeight,
  }) async {
    viewport = (viewWidth, viewHeight);
  }

  /// Positions ARCore hands back at close, keyed by anchor id — how a
  /// relocalisation is simulated on a desk.
  final Map<String, Offset> corrected = {};
  final List<String> released = [];

  @override
  Future<List<CapturedCorner>> resolveCorners(
    List<CapturedCorner> corners,
  ) async => [
    for (final corner in corners)
      if (corrected[corner.anchorId] case final moved?)
        CapturedCorner(
          position: moved,
          confidence: corner.confidence,
          anchorId: corner.anchorId,
        )
      else
        corner,
  ];

  @override
  Future<void> releaseCorners(List<CapturedCorner> corners) => releaseAnchorIds([
    for (final corner in corners)
      if (corner.anchorId != null) corner.anchorId!,
  ]);

  @override
  Future<void> releaseAnchorIds(List<String> ids) async => released.addAll(ids);

  /// What the preview was last told to draw. Null until the first sync, which
  /// is how "never asked" is told from "asked for nothing".
  (List<String>, List<String>)? markers;

  @override
  Future<void> setMarkers({
    required List<String> cornerIds,
    required List<String> doorIds,
  }) async {
    markers = (cornerIds, doorIds);
  }

  @override
  Future<void> resetPlaneLock() async => planeResets++;

  @override
  Stream<CaptureFrame> get frames => _controller.stream;
}

var _anchorSeq = 0;

CapturedCorner corner(
  double x,
  double y, {
  double confidence = 1,
  String? id,
}) => CapturedCorner(
  position: Offset(x, y),
  confidence: confidence,
  anchorId: id ?? "anchor-${++_anchorSeq}",
);

Room rectRoomFor(String id, String wingId) => Room(
  id: id,
  floorId: 'floor-uuid-g',
  code: 'GF 1',
  category: RoomCategory.corridor,
  wingId: wingId,
  polygon: const [
    RoomCorner(x: 0, y: 0),
    RoomCorner(x: 20, y: 0),
    RoomCorner(x: 20, y: 2),
    RoomCorner(x: 0, y: 2),
  ],
);

CaptureFrame frame({
  CaptureTracking tracking = CaptureTracking.tracking,
  CaptureTrackingIssue issue = CaptureTrackingIssue.none,
  bool planeLocked = true,
  CaptureSurface surface = CaptureSurface.floor,
}) => CaptureFrame(
  tracking: tracking,
  issue: issue,
  planeLocked: planeLocked,
  surface: surface,
);

void main() {
  late _FakeCapture capture;
  late _MockPlans plans;
  late _MockBuildings buildings;

  setUpAll(() => registerFallbackValue(RoomPlan.empty));

  setUp(() {
    capture = _FakeCapture();
    plans = _MockPlans();
    buildings = _MockBuildings();

    when(() => buildings.floorsOf(any())).thenAnswer(
      (_) async => const [
        BuildingFloor(id: 'floor-uuid-g', label: 'G', rooms: []),
      ],
    );
    when(() => plans.save(any())).thenAnswer((_) async {});
    // Nothing captured on this floor before, unless a test says otherwise.
    when(() => plans.planFor(any(), any())).thenAnswer((_) async => null);
  });

  RoomCaptureCubit build() => RoomCaptureCubit(capture, plans, buildings);

  Future<RoomCaptureCubit> started() async {
    final cubit = build();
    await cubit.start(
      buildingId: 'knust-cs',
      viewWidth: 1080,
      viewHeight: 2400,
    );
    capture.emit(frame());
    await Future<void>.delayed(Duration.zero);
    return cubit;
  }

  /// Places a square room and closes it.
  Future<void> captureSquare(
    RoomCaptureCubit cubit, {
    RoomCategory category = RoomCategory.office,
    String? label,
    double origin = 0,
  }) async {
    capture.hits.addAll([
      corner(origin, origin),
      corner(origin + 4, origin),
      corner(origin + 4, origin + 3),
      corner(origin, origin + 3),
    ]);
    for (var i = 0; i < 4; i++) {
      await cubit.tapCorner(0.5, 0.8);
    }
    await cubit.closeRoom(category: category, label: label);
  }

  group('device capability', () {
    test(
      'an uncertified phone lands on unavailable, not on an error',
      () async {
        capture.availability = ArCoreAvailability.unsupported;

        final cubit = build();
        await cubit.start(
          buildingId: 'knust-cs',
          viewWidth: 1080,
          viewHeight: 2400,
        );

        // The honest outcome for most budget Android hardware, and the screen
        // offers photo tracing from here rather than reporting a fault.
        expect(cubit.state.stage, RoomCaptureStage.unavailable);
        expect(cubit.state.error, isNull);
        await cubit.close();
      },
    );

    test('a session that will not start says why', () async {
      capture.startFailure = 'Camera permission is needed to scan.';

      final cubit = build();
      await cubit.start(
        buildingId: 'knust-cs',
        viewWidth: 1080,
        viewHeight: 2400,
      );

      expect(cubit.state.stage, RoomCaptureStage.unavailable);
      expect(cubit.state.error, contains('Camera permission'));
      await cubit.close();
    });

    test('a certified phone starts capturing', () async {
      final cubit = await started();

      expect(cubit.state.stage, RoomCaptureStage.capturing);
      expect(cubit.state.availability, ArCoreAvailability.supported);
      await cubit.close();
    });

    test('files rooms under a real floor id and its code prefix', () async {
      final cubit = await started();

      expect(cubit.state.floorId, 'floor-uuid-g');
      await captureSquare(cubit);

      expect(cubit.state.plan.rooms.single.floorId, 'floor-uuid-g');
      expect(cubit.state.plan.rooms.single.code, 'GF 1');
      await cubit.close();
    });
  });

  group('placing corners', () {
    test(
      'a tap while tracking is lost places nothing and says what to do',
      () async {
        final cubit = await started();
        capture.emit(
          frame(
            tracking: CaptureTracking.paused,
            issue: CaptureTrackingIssue.insufficientLight,
          ),
        );
        await Future<void>.delayed(Duration.zero);

        await cubit.tapCorner(0.5, 0.5);

        expect(cubit.state.draft, isEmpty);
        expect(cubit.state.guidance, contains('light'));
        // The tap never reached the platform channel.
        expect(capture.taps, isEmpty);
        await cubit.close();
      },
    );

    test('a tap that hits no floor is guidance, not a failure', () async {
      final cubit = await started();

      await cubit.tapCorner(0.5, 0.5);

      expect(cubit.state.draft, isEmpty);
      expect(cubit.state.guidance, contains('Aim at the floor'));
      expect(cubit.state.error, isNull);
      await cubit.close();
    });

    test('a hit becomes a corner in the plan frame', () async {
      final cubit = await started();
      capture.hits.add(corner(1, 2));

      await cubit.tapCorner(0.25, 0.75);

      expect(cubit.state.draft.single.position, const Offset(1, 2));
      expect(capture.taps.single, (0.25, 0.75));
      await cubit.close();
    });

    test('undo removes the last corner only', () async {
      final cubit = await started();
      capture.hits.addAll([corner(0, 0), corner(1, 0)]);

      await cubit.tapCorner(0.5, 0.5);
      await cubit.tapCorner(0.5, 0.5);
      cubit.undoCorner();

      expect(cubit.state.draft.single.position, Offset.zero);
      await cubit.close();
    });

    test('counts corners captured while the plane was not tracked', () async {
      final cubit = await started();
      capture.hits.addAll([corner(0, 0), corner(4, 0, confidence: 0.5)]);

      await cubit.tapCorner(0.5, 0.5);
      await cubit.tapCorner(0.5, 0.5);

      // Reported rather than averaged away — a room built mostly from these is
      // worth recapturing, and the evaluation report should be able to say so.
      expect(cubit.state.lowConfidenceCorners, 1);
      await cubit.close();
    });
  });

  group('markers drawn over the camera', () {
    test('the outline is sent in tapped order, because order is the '
        'shape', () async {
      final cubit = await started();
      capture.hits.addAll([
        corner(0, 0, id: 'a1'),
        corner(4, 0, id: 'a2'),
        corner(4, 3, id: 'a3'),
      ]);

      for (var i = 0; i < 3; i++) {
        await cubit.tapCorner(0.5, 0.8);
      }

      // Native joins consecutive ids into walls, so a reordered list is a
      // different polygon rather than the same one drawn differently.
      expect(capture.markers?.$1, ['a1', 'a2', 'a3']);
      await cubit.close();
    });

    test('undo takes the marker with it', () async {
      final cubit = await started();
      capture.hits.addAll([corner(0, 0, id: 'a1'), corner(4, 0, id: 'a2')]);
      await cubit.tapCorner(0.5, 0.8);
      await cubit.tapCorner(0.5, 0.8);

      await cubit.undoCorner();

      expect(capture.markers?.$1, ['a1']);
      // And the anchor behind it is detached, not merely undrawn.
      expect(capture.released, contains('a2'));
      await cubit.close();
    });

    test('closing the room clears the outline it drew', () async {
      final cubit = await started();
      await captureSquare(cubit);

      // From here the room is in the plan preview. Left drawn, it would read as
      // the beginning of the next room.
      expect(capture.markers?.$1, isEmpty);
      await cubit.close();
    });

    test('a recorded door is marked, and removing it releases its '
        'anchor', () async {
      final cubit = await started();
      await captureSquare(cubit, label: 'Room A');
      capture.hits.addAll([
        corner(4, 0),
        corner(8, 0),
        corner(8, 3),
        corner(4, 3),
      ]);
      for (var i = 0; i < 4; i++) {
        await cubit.tapCorner(0.5, 0.8);
      }
      await cubit.closeRoom(category: RoomCategory.office, label: 'Room B');
      await cubit.setMode(RoomCaptureMode.doors);

      capture.hits.add(corner(4, 1.5, id: 'door-anchor'));
      await cubit.tapDoor(0.5, 0.8);

      // Marking tagged doorways is what stops the same one being tapped again
      // from the other side.
      expect(capture.markers?.$2, ['door-anchor']);

      await cubit.removeDoor(cubit.state.plan.openings.single.id);

      expect(capture.markers?.$2, isEmpty);
      expect(capture.released, contains('door-anchor'));
      await cubit.close();
    });

    test('a door tap that lands nowhere near a wall does not leak its '
        'anchor', () async {
      final cubit = await started();
      await captureSquare(cubit, label: 'Room A');
      capture.hits.addAll([
        corner(4, 0),
        corner(8, 0),
        corner(8, 3),
        corner(4, 3),
      ]);
      for (var i = 0; i < 4; i++) {
        await cubit.tapCorner(0.5, 0.8);
      }
      await cubit.closeRoom(category: RoomCategory.office, label: 'Room B');
      await cubit.setMode(RoomCaptureMode.doors);

      // Out in the middle of nowhere: rejected, but ARCore still created an
      // anchor for it, and an anchor nothing refers to costs tracking work for
      // the rest of the walk.
      capture.hits.add(corner(40, 40, id: 'stray'));
      await cubit.tapDoor(0.5, 0.8);

      expect(cubit.state.plan.openings, isEmpty);
      expect(capture.released, contains('stray'));
      await cubit.close();
    });
  });

  group('closing a room', () {
    test('cleans up and normalises winding, same as tracing', () async {
      final cubit = await started();
      await captureSquare(cubit);

      final room = cubit.state.plan.rooms.single;
      expect(room.polygon, hasLength(4));
      expect(signedArea(room.corners), greaterThan(0));
      expect(cubit.state.draft, isEmpty);
      await cubit.close();
    });

    test('refuses fewer than three corners', () async {
      final cubit = await started();
      capture.hits.addAll([corner(0, 0), corner(1, 0)]);
      await cubit.tapCorner(0.5, 0.5);
      await cubit.tapCorner(0.5, 0.5);

      await cubit.closeRoom(category: RoomCategory.office);

      expect(cubit.state.plan.rooms, isEmpty);
      expect(cubit.state.guidance, contains('three corners'));
      await cubit.close();
    });

    test('refuses a bowtie and keeps the corners for undo', () async {
      final cubit = await started();
      capture.hits.addAll([
        corner(0, 0),
        corner(4, 3),
        corner(4, 0),
        corner(0, 3),
      ]);
      for (var i = 0; i < 4; i++) {
        await cubit.tapCorner(0.5, 0.5);
      }

      await cubit.closeRoom(category: RoomCategory.office);

      expect(cubit.state.plan.rooms, isEmpty);
      expect(cubit.state.guidance, contains('cross'));
      expect(cubit.state.draft, hasLength(4));
      await cubit.close();
    });

    test(
      'releases the plane lock so the next room finds its own floor',
      () async {
        final cubit = await started();
        await captureSquare(cubit);

        expect(capture.planeResets, 1);
        await cubit.close();
      },
    );
  });

  group('leaving the app and coming back', () {
    test('backgrounding hands the camera back and drops the texture', () async {
      final cubit = await started();
      expect(cubit.state.textureId, isNotNull);

      await cubit.pauseSession();

      // ARCore holds the camera exclusively, so the session must go.
      expect(capture.stopped, isTrue);
      // And the texture id with it. Found on a device: `MainActivity.onPause`
      // tore the session down natively whether Dart asked or not, nothing
      // restarted it, and returning to the screen rendered a `Texture` pointing
      // at a released id — a blank rectangle where the camera was, no crash,
      // and nothing in the log to explain it.
      expect(cubit.state.textureId, isNull);
      expect(cubit.state.tracking, CaptureTracking.stopped);
      await cubit.close();
    });

    test('returning starts a fresh session and a new texture', () async {
      final cubit = await started();
      await cubit.pauseSession();

      await cubit.resumeSession(viewWidth: 1080, viewHeight: 1800);

      expect(capture.isRunning, isTrue);
      expect(cubit.state.textureId, isNotNull);
      // The camera area, not the whole screen — taps are normalised against it.
      expect(capture.viewport, (1080, 1800));
      await cubit.close();
    });

    test('a half-traced room is dropped, and said to be', () async {
      final cubit = await started();
      capture.hits.addAll([corner(0, 0), corner(3, 0)]);
      await cubit.tapCorner(0.5, 0.5);
      await cubit.tapCorner(0.5, 0.5);

      await cubit.pauseSession();
      await cubit.resumeSession(viewWidth: 1080, viewHeight: 1800);

      // ARCore's world origin is wherever the phone was when the session
      // started, so corners measured before the break are in a frame that no
      // longer exists. Keeping them silently is a deformed room with nothing to
      // say so.
      expect(cubit.state.draft, isEmpty);
      expect(cubit.state.guidance, contains('dropped'));
      await cubit.close();
    });

    test('resuming twice does not start two sessions', () async {
      final cubit = await started();
      await cubit.pauseSession();
      await cubit.resumeSession(viewWidth: 1080, viewHeight: 1800);

      await cubit.resumeSession(viewWidth: 999, viewHeight: 999);

      // The second is a no-op: `inactive` and `resumed` can arrive in quick
      // succession, and two sessions cannot both hold the camera.
      expect(capture.viewport, (1080, 1800));
      await cubit.close();
    });
  });

  group('floor or ceiling — spec §2, for rooms the furniture hides', () {
    test('says which surface the room is being traced on', () async {
      final cubit = await started();

      capture.emit(frame(surface: CaptureSurface.ceiling));
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.surface, CaptureSurface.ceiling);
      expect(cubit.state.isTracingCeiling, isTrue);
      // Nobody *chose* the ceiling — the first corner decided it — so it has
      // to be on screen, or a room that locked overhead by accident is
      // invisible until the plan comes out misshapen.
      expect(cubit.state.guidance, contains('ceiling'));
      await cubit.close();
    });

    test('a missed tap tells you to aim at the surface in use', () async {
      final cubit = await started();
      capture.emit(frame(surface: CaptureSurface.ceiling));
      await Future<void>.delayed(Duration.zero);

      // "Aim at the floor" is advice somebody tracing a cluttered store room's
      // ceiling cannot act on.
      await cubit.tapCorner(0.5, 0.5);

      expect(cubit.state.guidance, contains('Aim at the ceiling'));
      await cubit.close();
    });

    test('before anything is locked, both surfaces are offered', () async {
      final cubit = await started();
      capture.emit(frame(planeLocked: false, surface: CaptureSurface.none));
      await Future<void>.delayed(Duration.zero);

      // Offered up front rather than kept as a fix for a failure: the rooms it
      // helps with are recognisable on sight, and discovering it after ten
      // minutes of failing to tap a floor behind a filing cabinet is
      // discovering it too late.
      expect(cubit.state.guidance, contains('ceiling'));
      await cubit.close();
    });

    test('undoing back to no corners releases the surface lock', () async {
      final cubit = await started();
      capture.hits.addAll([corner(0, 0), corner(3, 0)]);
      await cubit.tapCorner(0.5, 0.5);
      await cubit.tapCorner(0.5, 0.5);

      await cubit.undoCorner();
      // Still one corner in, so the room keeps the surface it started on.
      expect(capture.planeResets, 0);

      await cubit.undoCorner();

      // **The whole recovery path for a room that locked to the wrong
      // surface.** Without it the only way out is to leave the screen, and the
      // lock is not something a contributor can see well enough to know that is
      // what went wrong.
      expect(capture.planeResets, 1);
      await cubit.close();
    });

    test('abandoning a half-traced room releases the lock too', () async {
      final cubit = await started();
      capture.hits.add(corner(0, 0));
      await cubit.tapCorner(0.5, 0.5);

      await cubit.setMode(RoomCaptureMode.doors);

      expect(cubit.state.draft, isEmpty);
      expect(capture.planeResets, 1);
      await cubit.close();
    });


    test('allocates sequential codes across rooms', () async {
      final cubit = await started();
      await captureSquare(cubit);
      await captureSquare(cubit, origin: 10);

      expect(cubit.state.plan.rooms.map((r) => r.code), ['GF 1', 'GF 2']);
      await cubit.close();
    });

    test('an empty label is stored as none', () async {
      final cubit = await started();
      await captureSquare(cubit, label: '  ');

      expect(cubit.state.plan.rooms.single.label, isNull);
      await cubit.close();
    });
  });

  group('saving', () {
    test('a captured plan is METRIC, unlike a traced one', () async {
      final cubit = await started();
      await captureSquare(cubit);

      await cubit.save();

      final saved =
          verify(() => plans.save(captureAny())).captured.single as RoomPlan;
      // The one real difference between the two capture paths: these
      // coordinates are genuinely metres, so guidance may speak distances.
      expect(saved.metresPerUnit, 1);
      expect(saved.isMetric, isTrue);
      expect(cubit.state.stage, RoomCaptureStage.saved);
      await cubit.close();
    });

    test('the captured room is the size it was captured at', () async {
      final cubit = await started();
      await captureSquare(cubit);

      // 4 m x 3 m, tapped as such — a scale error anywhere in the chain shows
      // up here and nowhere else.
      expect(cubit.state.plan.rooms.single.areaSqM, closeTo(12, 0.01));
      await cubit.close();
    });

    test('refuses to save nothing', () async {
      final cubit = await started();

      await cubit.save();

      verifyNever(() => plans.save(any()));
      expect(cubit.state.error, contains('at least one room'));
      await cubit.close();
    });

    test('a failed save keeps the rooms', () async {
      when(() => plans.save(any())).thenThrow(Exception('offline'));
      final cubit = await started();
      await captureSquare(cubit);

      await cubit.save();

      expect(cubit.state.stage, RoomCaptureStage.capturing);
      expect(cubit.state.error, contains('still here'));
      expect(cubit.state.plan.rooms, hasLength(1));
      await cubit.close();
    });
  });

  group('placing doors — what turns a picture into a map', () {
    /// Two rooms sharing the wall at x = 4, plus a corridor along the top.
    Future<RoomCaptureCubit> twoRooms() async {
      final cubit = await started();
      await captureSquare(cubit, label: 'Room A');
      // Butted against Room A's east wall.
      capture.hits.addAll([
        corner(4, 0),
        corner(8, 0),
        corner(8, 3),
        corner(4, 3),
      ]);
      for (var i = 0; i < 4; i++) {
        await cubit.tapCorner(0.5, 0.8);
      }
      await cubit.closeRoom(category: RoomCategory.office, label: 'Room B');
      cubit.setMode(RoomCaptureMode.doors);
      return cubit;
    }

    test(
      'without doors every room is unreachable — the gap this closes',
      () async {
        final cubit = await twoRooms();

        // Rooms positioned correctly relative to each other, joined by nothing.
        expect(cubit.state.plan.drawableRooms, hasLength(2));
        expect(cubit.state.plan.openings, isEmpty);
        expect(cubit.state.roomsWithoutDoors, hasLength(2));
        await cubit.close();
      },
    );

    test('a corner is held to the locked surface and a door is not', () async {
      final cubit = await twoRooms();
      // Every tap so far has been a corner, and every one asked to be held to
      // the room's surface — that is what rejects a corner placed on a desk.
      expect(capture.tapLocks, everyElement(isTrue));

      // A door is one independent point tapped in a doorway that may be a room
      // away from the last one traced, on a plane ARCore has never merged with
      // it. Holding doors to the lock rejected every doorway after the first —
      // and with ceilings it would reject a door at the contributor's feet in a
      // room traced overhead.
      capture.hits.add(corner(4, 1.5));
      await cubit.tapDoor(0.5, 0.8);

      expect(capture.tapLocks.last, isFalse);
      await cubit.close();
    });

    test('standing in the doorway joins the two rooms either side', () async {
      final cubit = await twoRooms();
      // On the shared wall at x = 4.
      capture.hits.add(corner(4, 1.5));

      await cubit.tapDoor(0.5, 0.8);

      final opening = cubit.state.plan.openings.single;
      final rooms = cubit.state.plan.rooms;
      expect({opening.roomAId, opening.roomBId}, {rooms[0].id, rooms[1].id});
      // And now they are a map.
      expect(cubit.state.roomsWithoutDoors, isEmpty);
      await cubit.close();
    });

    test('the joined rooms can actually be routed between', () async {
      final cubit = await twoRooms();
      capture.hits.add(corner(4, 1.5));
      await cubit.tapDoor(0.5, 0.8);

      final rooms = cubit.state.plan.rooms;
      final route = RoomNavGraph.build(
        cubit.state.plan,
      ).route(fromRoomId: rooms[0].id, toRoomId: rooms[1].id);

      expect(route, isNotNull);
      expect(route!.roomsPassed, hasLength(2));
      await cubit.close();
    });

    test('a door on an outside wall is recorded as a way out', () async {
      final cubit = await twoRooms();
      // Far west edge — only Room A borders it.
      capture.hits.add(corner(0, 1.5));

      await cubit.tapDoor(0.5, 0.8);

      expect(cubit.state.plan.openings.single.isExterior, isTrue);
      expect(cubit.state.guidance, contains('way out'));
      await cubit.close();
    });

    test('a tap nowhere near a wall places nothing', () async {
      final cubit = await twoRooms();
      capture.hits.add(corner(40, 40));

      await cubit.tapDoor(0.5, 0.8);

      expect(cubit.state.plan.openings, isEmpty);
      expect(cubit.state.guidance, contains('not near a wall'));
      await cubit.close();
    });

    test('refuses a second door between the same two rooms', () async {
      final cubit = await twoRooms();
      capture.hits.addAll([corner(4, 1.5), corner(4, 2.0)]);

      await cubit.tapDoor(0.5, 0.8);
      await cubit.tapDoor(0.5, 0.8);

      expect(cubit.state.plan.openings, hasLength(1));
      expect(cubit.state.guidance, contains('already have a door'));
      await cubit.close();
    });

    test('asks for rooms before doors', () async {
      final cubit = await started();
      cubit.setMode(RoomCaptureMode.doors);

      await cubit.tapDoor(0.5, 0.8);

      expect(cubit.state.guidance, contains('rooms either side'));
      await cubit.close();
    });

    test(
      'a door tap while tracking is lost never reaches the channel',
      () async {
        final cubit = await twoRooms();
        capture.emit(
          frame(
            tracking: CaptureTracking.paused,
            issue: CaptureTrackingIssue.excessiveMotion,
          ),
        );
        await Future<void>.delayed(Duration.zero);
        final tapsBefore = capture.taps.length;

        await cubit.tapDoor(0.5, 0.8);

        expect(capture.taps, hasLength(tapsBefore));
        expect(cubit.state.guidance, contains('slowly'));
        await cubit.close();
      },
    );

    test('switching to doors abandons a half-captured room', () async {
      final cubit = await started();
      capture.hits.addAll([corner(0, 0), corner(4, 0)]);
      await cubit.tapCorner(0.5, 0.8);
      await cubit.tapCorner(0.5, 0.8);

      cubit.setMode(RoomCaptureMode.doors);

      expect(cubit.state.draft, isEmpty);
      await cubit.close();
    });
  });

  group('the door count guard', () {
    test('ordinals stay unsafe until the declared doors are placed', () async {
      final cubit = await started();
      // A corridor and one room off it.
      await captureSquare(cubit, category: RoomCategory.corridor);
      capture.hits.addAll([
        corner(0, 3),
        corner(4, 3),
        corner(4, 7),
        corner(0, 7),
      ]);
      for (var i = 0; i < 4; i++) {
        await cubit.tapCorner(0.5, 0.8);
      }
      await cubit.closeRoom(category: RoomCategory.office);

      final corridor = cubit.state.plan.rooms.first;
      cubit.declareDoorCount(corridorId: corridor.id, count: 3);

      expect(cubit.state.ordinalsAreSafe, isFalse);
      expect(cubit.state.incompleteCorridors[corridor.id], 3);
      await cubit.close();
    });

    test('a stub stands in for a door nobody opened', () async {
      final cubit = await started();
      await captureSquare(cubit, category: RoomCategory.corridor);

      cubit.addStubRoom();

      final stub = cubit.state.plan.rooms.last;
      expect(stub.isStub, isTrue);
      expect(
        cubit.state.plan.drawableRooms.map((r) => r.id),
        isNot(contains(stub.id)),
      );
      await cubit.close();
    });
  });

  group('drift', () {
    test('a small session raises nothing', () async {
      final cubit = await started();
      await captureSquare(cubit);

      expect(cubit.state.capturedSpanMetres, closeTo(4, 0.01));
      expect(
        cubit.state.capturedSpanMetres,
        lessThan(RoomCaptureCubit.driftWarningSpanMetres),
      );
      await cubit.close();
    });

    test('a session spanning a whole wing is reported', () async {
      final cubit = await started();
      await captureSquare(cubit);
      // A second room fifty metres down the building.
      await captureSquare(cubit, origin: 50);

      // Spec §8: heading error compounds with distance, and heading error is
      // what ruins a plan rather than blurring it.
      expect(
        cubit.state.capturedSpanMetres,
        greaterThan(RoomCaptureCubit.driftWarningSpanMetres),
      );
      await cubit.close();
    });
  });

  group('the whole scenario: walk in, scan three rooms, get a map', () {
    /// Captures a corridor with three rooms off its north side and a door into
    /// each — one continuous AR session, exactly as it would be walked.
    ///
    ///        Room A        Room B        Room C
    ///      x 2..6        x 8..12       x 14..18      (all y 2..6)
    ///   ─────┬──────────────┬──────────────┬───────   y = 2, doors at x 4,10,16
    ///        corridor, x 0..20, y 0..2
    Future<RoomCaptureCubit> wing() async {
      final cubit = await started();

      Future<void> rect(
        double left,
        double right,
        double bottom,
        double top,
        RoomCategory category,
        String? label,
      ) async {
        capture.hits.addAll([
          corner(left, bottom),
          corner(right, bottom),
          corner(right, top),
          corner(left, top),
        ]);
        for (var i = 0; i < 4; i++) {
          await cubit.tapCorner(0.5, 0.8);
        }
        await cubit.closeRoom(category: category, label: label);
      }

      await rect(0, 20, 0, 2, RoomCategory.corridor, null);
      await rect(2, 6, 2, 6, RoomCategory.office, 'Room A');
      await rect(8, 12, 2, 6, RoomCategory.office, 'Room B');
      await rect(14, 18, 2, 6, RoomCategory.laboratory, 'Room C');

      cubit.setMode(RoomCaptureMode.doors);
      capture.hits.addAll([corner(4, 2), corner(10, 2), corner(16, 2)]);
      for (var i = 0; i < 3; i++) {
        await cubit.tapDoor(0.5, 0.8);
      }
      return cubit;
    }

    test('the rooms come out connected, not just adjacent', () async {
      final cubit = await wing();

      expect(cubit.state.plan.drawableRooms, hasLength(4));
      expect(cubit.state.plan.openings, hasLength(3));
      expect(cubit.state.roomsWithoutDoors, isEmpty);
      expect(cubit.state.strandedRooms, isEmpty);
      await cubit.close();
    });

    test(
      'a route runs from the first room to the third through the corridor',
      () async {
        final cubit = await wing();
        final plan = cubit.state.plan;
        final a = plan.rooms.firstWhere((r) => r.label == 'Room A');
        final c = plan.rooms.firstWhere((r) => r.label == 'Room C');

        final route = RoomNavGraph.build(
          plan,
        ).route(fromRoomId: a.id, toRoomId: c.id);

        expect(route, isNotNull);
        expect(route!.roomsPassed, hasLength(3));
        expect(plan.roomOf(route.roomsPassed[1])!.isCirculation, isTrue);
        await cubit.close();
      },
    );

    test('and it speaks the door count, in metres', () async {
      final cubit = await wing();
      final plan = cubit.state.plan;
      final corridor = plan.rooms.firstWhere(
        (r) => r.category == RoomCategory.corridor,
      );

      // The one number a contributor types, and the guard on the ordinals.
      cubit.declareDoorCount(corridorId: corridor.id, count: 3);
      expect(cubit.state.ordinalsAreSafe, isTrue);

      final a = plan.rooms.firstWhere((r) => r.label == 'Room A');
      final c = plan.rooms.firstWhere((r) => r.label == 'Room C');
      final planned = RoomPlanBridge.plannedRouteFrom(
        cubit.state.plan,
        fromRoomId: a.id,
        toRoomId: c.id,
        initialHeading: const Offset(1, 0),
      )!;

      final spoken = planned.legs.map((l) => l.instruction ?? '').join(' ');

      // Walking east, the north wall is on the left; Room B's door is passed
      // first, so Room C's is the second.
      expect(spoken, contains('second door on your left'));
      // Captured coordinates really are metres, unlike a traced plan, so
      // distances may be spoken.
      expect(spoken, contains('metres'));
      await cubit.close();
    });

    test('the captured floor is the size it was walked', () async {
      final cubit = await wing();

      // Corridor 20 x 2 plus three 4 x 4 rooms.
      expect(cubit.state.capturedSpanMetres, closeTo(20, 0.1));
      expect(
        cubit.state.plan.roomOf(cubit.state.plan.rooms.first.id)!.areaSqM,
        closeTo(40, 0.1),
      );
      await cubit.close();
    });
  });

  group('a large building: extending a floor across sessions', () {
    /// A wing somebody captured yesterday, occupying x 0..20.
    RoomPlan yesterday() => const RoomPlan(
      buildingId: 'knust-cs',
      floorId: 'floor-uuid-g',
      codePrefix: 'GF',
      metresPerUnit: 1,
      storedRooms: [
        Room(
          id: 'room-1',
          floorId: 'floor-uuid-g',
          code: 'GF 1',
          category: RoomCategory.corridor,
          wingId: 'wing-1',
          polygon: [
            RoomCorner(x: 0, y: 0),
            RoomCorner(x: 20, y: 0),
            RoomCorner(x: 20, y: 2),
            RoomCorner(x: 0, y: 2),
          ],
        ),
      ],
    );

    test(
      'a second session KEEPS the first wing rather than erasing it',
      () async {
        when(
          () => plans.planFor(any(), any()),
        ).thenAnswer((_) async => yesterday());

        final cubit = await started();
        await captureSquare(cubit);
        await cubit.save();

        final saved =
            verify(() => plans.save(captureAny())).captured.single as RoomPlan;

        // Before this, a second scan of the same floor started blank and saved
        // over the first — twenty minutes of somebody's walk, gone silently.
        expect(saved.storedRooms, hasLength(2));
        expect(saved.storedRooms.first.id, 'room-1');
        await cubit.close();
      },
    );

    test('the new wing gets its own id and does not reuse room ids', () async {
      when(
        () => plans.planFor(any(), any()),
      ).thenAnswer((_) async => yesterday());

      final cubit = await started();
      await captureSquare(cubit);

      final fresh = cubit.state.plan.storedRooms.last;
      expect(fresh.wingId, 'wing-2');
      // Restarting ids at 1 would collide with room-1 and the two would merge
      // into one node the moment the graph indexed them.
      expect(fresh.id, isNot('room-1'));
      expect(cubit.state.plan.wingIds, ['wing-1', 'wing-2']);
      await cubit.close();
    });

    test(
      'the new wing is parked clear, not dropped on top of the old',
      () async {
        when(
          () => plans.planFor(any(), any()),
        ).thenAnswer((_) async => yesterday());

        final cubit = await started();
        await captureSquare(cubit);

        // Captured at x 0..4 in this session's own ARCore frame, which says
        // nothing about where it is relative to yesterday's wing.
        final placement = cubit.state.plan.wings['wing-2']!;
        expect(placement.dx, 20 + RoomCaptureCubit.parkingGapMetres);

        // And once placed it sits beside the old wing rather than through it.
        final placed = cubit.state.plan.rooms.last;
        expect(placed.bounds.left, greaterThan(20));
        await cubit.close();
      },
    );

    test(
      'the screen can say this is an extension, not a fresh floor',
      () async {
        when(
          () => plans.planFor(any(), any()),
        ).thenAnswer((_) async => yesterday());

        final cubit = await started();
        await captureSquare(cubit);

        expect(cubit.state.isExtendingFloor, isTrue);
        expect(cubit.state.roomsFromEarlierSessions, 1);
        await cubit.close();
      },
    );

    test('the first wing on an empty floor is not parked', () async {
      final cubit = await started();
      await captureSquare(cubit);

      // Nothing to be clear of, and its own frame is as good an origin as any.
      expect(cubit.state.plan.hasWingPlacements, isFalse);
      expect(cubit.state.plan.rooms.single.bounds.left, 0);
      await cubit.close();
    });

    test('a plan saved before wings existed still loads', () async {
      // No wingId on the room, no wings map — the shape every captured plan
      // had until today, and the shape sitting in the repository right now.
      when(() => plans.planFor(any(), any())).thenAnswer(
        (_) async => const RoomPlan(
          buildingId: 'knust-cs',
          floorId: 'floor-uuid-g',
          codePrefix: 'GF',
          // Metric, because this stands in for a plan captured in AR. A
          // *traced* plan of the same vintage is refused instead — see the
          // units group.
          metresPerUnit: 1,
          storedRooms: [
            Room(
              id: 'room-1',
              floorId: 'floor-uuid-g',
              code: 'GF 1',
              category: RoomCategory.office,
              polygon: [
                RoomCorner(x: 0, y: 0),
                RoomCorner(x: 4, y: 0),
                RoomCorner(x: 4, y: 3),
              ],
            ),
          ],
        ),
      );

      final cubit = await started();

      expect(cubit.state.plan.storedRooms, hasLength(1));
      expect(cubit.state.plan.wingIds, isEmpty);
      expect(cubit.state.wingId, 'wing-1');
      await cubit.close();
    });
  });

  group('the viewport ARCore is told about', () {
    test(
      'is handed over at start, not guessed from the camera image',
      () async {
        final cubit = await started();

        // This is what makes a tap land where it was made: ARCore does the
        // camera-to-view mapping itself, given the view it is drawing into.
        // Passing the camera image's own size instead — which is what the
        // first version did — is right only on a square screen held sideways.
        expect(capture.viewport, (1080, 2400));
        await cubit.close();
      },
    );

    test('is updated when the view resizes or the device turns', () async {
      final cubit = await started();

      await cubit.setViewport(viewWidth: 2400, viewHeight: 1080);

      expect(capture.viewport, (2400, 1080));
      await cubit.close();
    });
  });

  group('units cannot be mixed', () {
    test('refuses to scan a floor that was traced from a photo', () async {
      // A traced plan is measured in fractions of the photo's width; AR
      // capture produces metres. Appending one to the other puts two
      // coordinate systems about fifty times apart into one space, and the
      // combined plan inherits the traced plan's null scale so guidance stops
      // speaking distances it now genuinely has.
      when(() => plans.planFor(any(), any())).thenAnswer(
        (_) async => const RoomPlan(
          buildingId: 'knust-cs',
          floorId: 'floor-uuid-g',
          codePrefix: 'GF',
          // Unitless — the ordinary case for a traced plan.
          storedRooms: [
            Room(
              id: 'room-1',
              floorId: 'floor-uuid-g',
              code: 'GF 1',
              category: RoomCategory.office,
              polygon: [
                RoomCorner(x: 0, y: 0),
                RoomCorner(x: 0.2, y: 0),
                RoomCorner(x: 0.2, y: 0.15),
              ],
            ),
          ],
        ),
      );

      final cubit = build();
      await cubit.start(
        buildingId: 'knust-cs',
        viewWidth: 1080,
        viewHeight: 2400,
      );

      expect(cubit.state.stage, RoomCaptureStage.unavailable);
      expect(cubit.state.error, contains('traced from a photo'));
      // And crucially it did not start a session and begin appending.
      expect(cubit.state.plan.storedRooms, isEmpty);
      await cubit.close();
    });

    test('extends a floor that was itself captured in metres', () async {
      when(() => plans.planFor(any(), any())).thenAnswer(
        (_) async => RoomPlan(
          buildingId: 'knust-cs',
          floorId: 'floor-uuid-g',
          codePrefix: 'GF',
          metresPerUnit: 1,
          storedRooms: [rectRoomFor('room-1', 'wing-1')],
        ),
      );

      final cubit = await started();

      expect(cubit.state.stage, RoomCaptureStage.capturing);
      expect(cubit.state.plan.isMetric, isTrue);
      await cubit.close();
    });
  });

  group('surviving a relocalisation', () {
    test('corners are re-read at close, in one frame', () async {
      final cubit = await started();
      capture.hits.addAll([
        corner(0, 0, id: 'a1'),
        corner(4, 0, id: 'a2'),
        corner(4, 3, id: 'a3'),
        corner(0, 3, id: 'a4'),
      ]);
      for (var i = 0; i < 4; i++) {
        await cubit.tapCorner(0.5, 0.8);
      }

      // Halfway through the room ARCore lost tracking, found itself again and
      // shifted where it thinks the world origin is. The last two corners were
      // recorded in the *old* frame; ARCore has since corrected their anchors
      // by half a metre east.
      capture.corrected['a3'] = const Offset(4.5, 3);
      capture.corrected['a4'] = const Offset(0.5, 3);

      await cubit.closeRoom(category: RoomCategory.office);

      // The stored room uses the corrected positions, so it is a coherent
      // shape rather than two half-rooms from two different frames.
      final box = cubit.state.plan.rooms.single.bounds;
      expect(box.right, closeTo(4.5, 0.01));
      await cubit.close();
    });

    test('a corner ARCore has lost keeps its tapped position', () async {
      final cubit = await started();
      await captureSquare(cubit);

      // Nothing in `corrected`, i.e. no anchor came back tracked. Best
      // available is what was tapped, and the room still closes.
      expect(cubit.state.plan.rooms, hasLength(1));
      expect(cubit.state.plan.rooms.single.areaSqM, closeTo(12, 0.01));
      await cubit.close();
    });

    test('anchors are released once the room is stored', () async {
      final cubit = await started();
      await captureSquare(cubit);

      // Anchors cost ARCore tracking work every frame; a session that never
      // lets go gets slower the longer a building is walked.
      expect(capture.released, hasLength(4));
      await cubit.close();
    });

    test('undo releases the anchor it discarded', () async {
      final cubit = await started();
      capture.hits.add(corner(0, 0, id: 'a9'));
      await cubit.tapCorner(0.5, 0.8);

      await cubit.undoCorner();

      expect(capture.released, contains('a9'));
      await cubit.close();
    });
  });

  group('lifecycle', () {
    test('closing stops the session so the camera is released', () async {
      final cubit = await started();

      await cubit.close();

      // ARCore holds the camera exclusively; a session left running is what
      // makes the next one fail to start.
      expect(capture.stopped, isTrue);
    });
  });
}
