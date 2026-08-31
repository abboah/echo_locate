import 'dart:io';

import 'package:echo_locate/core/models/room_plan.dart';
import 'package:echo_locate/data/repository_mixin.dart';
import 'package:echo_locate/features/room_trace/room_plan_repository.dart';
import 'package:echo_locate/features/room_trace/supabase_room_plan_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'room_directions_test.dart' show buildWing;

void main() {
  group('LocalRoomPlanRepository', () {
    late Directory directory;
    const repository = LocalRoomPlanRepository();

    setUpAll(() async {
      directory = await Directory.systemTemp.createTemp('room_plan_repo');
      Hive.init(directory.path);
      await Hive.openBox(repoCacheBoxName);
    });

    setUp(() => Hive.box(repoCacheBoxName).clear());

    tearDownAll(() async {
      await Hive.close();
      await directory.delete(recursive: true);
    });

    test('a floor nobody traced reads as null, not as an error', () async {
      expect(await repository.planFor('knust-cs', 'gf'), isNull);
    });

    test('a saved plan round-trips with its geometry intact', () async {
      final plan = buildWing();
      await repository.save(plan);

      final loaded = await repository.planFor('knust-cs', 'gf');

      expect(loaded, equals(plan));
      // The part that actually matters after a round trip: the polygons and
      // the door counts, since routing and ordinals both read them.
      expect(loaded!.roomOf('corridor')!.corners, hasLength(4));
      expect(loaded.corridorIsComplete('corridor'), isTrue);
    });

    test('saving a floor twice replaces it rather than appending', () async {
      await repository.save(buildWing());
      await repository.save(
        buildWing().copyWith(storedRooms: [buildWing().rooms.first]),
      );

      final loaded = await repository.planFor('knust-cs', 'gf');

      expect(loaded!.rooms, hasLength(1));
      expect(await repository.plansOf('knust-cs'), hasLength(1));
    });

    test('one floor is not another', () async {
      await repository.save(buildWing());
      await repository.save(buildWing().copyWith(floorId: 'first'));

      expect(await repository.plansOf('knust-cs'), hasLength(2));
      expect((await repository.planFor('knust-cs', 'first'))!.floorId, 'first');
    });

    test("one building's plans are not another's", () async {
      await repository.save(buildWing());
      await repository.save(buildWing().copyWith(buildingId: 'other'));

      expect(await repository.plansOf('knust-cs'), hasLength(1));
      expect(await repository.plansOf('other'), hasLength(1));
    });

    test(
      'allPlans crosses buildings, since the Maps tab is not about one',
      () async {
        await repository.save(buildWing());
        await repository.save(buildWing().copyWith(floorId: 'first'));
        await repository.save(buildWing().copyWith(buildingId: 'other'));

        final all = await repository.allPlans();

        expect(all, hasLength(3));
        expect(
          all.map((plan) => '${plan.buildingId}/${plan.floorId}'),
          containsAll(['knust-cs/gf', 'knust-cs/first', 'other/gf']),
        );
      },
    );

    test('allPlans leaves drafts out', () async {
      // A draft is by definition the work somebody has not finished. Listing
      // it as a walkable floor offers a walk over half a corridor.
      await repository.save(buildWing());
      await repository.saveDraft(buildWing().copyWith(floorId: 'first'));

      final all = await repository.allPlans();

      expect(all, hasLength(1));
      expect(all.single.floorId, 'gf');
    });

    test(
      'allPlans on a phone that has traced nothing is empty, not an error',
      () async {
        expect(await repository.allPlans(), isEmpty);
      },
    );

    test('deleting a floor leaves the rest alone', () async {
      await repository.save(buildWing());
      await repository.save(buildWing().copyWith(floorId: 'first'));

      await repository.delete('knust-cs', 'gf');

      expect(await repository.planFor('knust-cs', 'gf'), isNull);
      expect(await repository.plansOf('knust-cs'), hasLength(1));
    });

    test('an undecodable row reads as absent rather than throwing', () async {
      // Schema drift after an app update. Being asked to retrace a floor is a
      // cost; a building that cannot be opened at all is a bigger one.
      await Hive.box(
        repoCacheBoxName,
      ).put('room_plan:knust-cs:gf', '{not json at all');

      expect(await repository.planFor('knust-cs', 'gf'), isNull);
    });

    test('a plan is stored as a string, which is what Hive can hold', () async {
      // Hive throws "Cannot write, unknown type: _Room" on the nested freezed
      // models inside a plan. Encoding at the boundary keeps that impossible.
      await repository.save(buildWing());

      expect(
        Hive.box(repoCacheBoxName).get('room_plan:knust-cs:gf'),
        isA<String>(),
      );
    });
  });

  group('SupabaseRoomPlanRepository', () {
    test('refuses to save a plan with nothing traced in it', () async {
      final client = SupabaseClient('http://127.0.0.1:9', 'test-key');
      final repository = SupabaseRoomPlanRepository(client);

      try {
        await repository.save(RoomPlan.empty);
        fail('expected OperationFailure');
      } on OperationFailure catch (failure) {
        expect(failure.message, contains('at least one room'));
      } finally {
        await client.dispose();
      }
    });

    test('a plan of only stubs counts as nothing traced', () async {
      // Stubs exist to be counted, not to be drawn. A "plan" of nothing but
      // stubs would replace a real floor with an empty one on the server.
      final client = SupabaseClient('http://127.0.0.1:9', 'test-key');
      final repository = SupabaseRoomPlanRepository(client);

      try {
        await repository.save(
          RoomPlan(
            buildingId: 'knust-cs',
            floorId: 'gf',
            codePrefix: 'GF',
            storedRooms: [Room.stub(id: 'r1', floorId: 'gf', code: 'GF 1')],
          ),
        );
        fail('expected OperationFailure');
      } on OperationFailure catch (failure) {
        expect(failure.message, contains('at least one room'));
      } finally {
        await client.dispose();
      }
    });

    test('a network failure says so in words a user can read', () async {
      // Nothing listens on this port — the same as a phone with no route out,
      // which indoors is the normal case rather than the exceptional one.
      final client = SupabaseClient('http://127.0.0.1:9', 'test-key');
      final repository = SupabaseRoomPlanRepository(client);

      try {
        await repository.save(buildWing());
        fail('expected OperationFailure');
      } on OperationFailure catch (failure) {
        expect(failure.message.toLowerCase(), contains('connect'));
        expect(failure.message.toLowerCase(), isNot(contains('exception')));
        expect(failure.message.toLowerCase(), isNot(contains('socket')));
      } finally {
        await client.dispose();
      }
    });
  });
}
