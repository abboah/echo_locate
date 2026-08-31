import 'package:echo_locate/core/models/building.dart';
import 'package:echo_locate/data/repository_mixin.dart';
import 'package:echo_locate/features/buildings/building_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import 'dart:io';

/// Renaming and removing a building.
///
/// Both had the same shape of bug behind them: a bare PostgREST `update` or
/// `delete` that RLS filters away returns **success** having changed nothing,
/// so a rename the user was not allowed to make looked exactly like one that
/// worked. Both go through a function now that raises instead. These cover the
/// offline repository, which is the half that can be tested without a server.
void main() {
  late Directory directory;
  late MockBuildingRepository repository;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('building_actions');
    Hive.init(directory.path);
    await Hive.openBox(repoCacheBoxName);
  });

  tearDownAll(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  setUp(() async {
    await Hive.box(repoCacheBoxName).clear();
    RepositoryMixin.clearEphemeralCache();
    repository = MockBuildingRepository();
  });

  Future<Building> addOne() =>
      repository.create(name: 'Test Block', area: 'KNUST, Kumasi');

  group('renaming', () {
    test('the new name is what every list then reads', () async {
      final created = await addOne();

      await repository.rename(created.id, name: 'College of Science');

      // The bug this covers: the rename "succeeded" and the lists kept showing
      // the old name.
      expect((await repository.byId(created.id)).name, 'College of Science');
      expect(
        (await repository.nearby()).map((b) => b.name),
        contains('College of Science'),
      );
      expect(
        (await repository.recentlyMapped()).map((b) => b.name),
        contains('College of Science'),
      );
    });

    test('the id does not move, so the floors stay attached', () async {
      final created = await addOne();
      final before = await repository.floorsOf(created.id);

      final renamed = await repository.rename(
        created.id,
        name: 'Something Entirely Different',
      );

      // Re-slugging on rename would orphan every floor, traced plan and
      // bookmark pointing at the old id.
      expect(renamed.id, created.id);
      expect(await repository.floorsOf(created.id), hasLength(before.length));
    });

    test(
      'the area can be corrected too, and is left alone when blank',
      () async {
        final created = await addOne();

        final moved = await repository.rename(
          created.id,
          name: 'Test Block',
          area: 'Ayeduase',
        );
        expect(moved.area, 'Ayeduase');

        final untouched = await repository.rename(
          created.id,
          name: 'Test Block',
          area: '   ',
        );
        expect(untouched.area, 'Ayeduase');
      },
    );

    test('an empty name is refused', () async {
      final created = await addOne();

      expect(
        () => repository.rename(created.id, name: '  '),
        throwsA(isA<OperationFailure>()),
      );
    });
  });

  group('removing', () {
    test('a building you added disappears from every list', () async {
      final created = await addOne();
      expect(
        (await repository.nearby()).map((b) => b.id),
        contains(created.id),
      );

      await repository.delete(created.id);

      // The whole point: a test entry sitting in everybody's Explore list
      // forever was the alternative.
      expect(
        (await repository.nearby()).map((b) => b.id),
        isNot(contains(created.id)),
      );
      expect(
        () => repository.byId(created.id),
        throwsA(isA<OperationFailure>()),
      );
    });

    test('its floors go with it', () async {
      final created = await addOne();
      expect(await repository.floorsOf(created.id), isNotEmpty);

      await repository.delete(created.id);

      expect(
        () => repository.floorsOf(created.id),
        throwsA(isA<OperationFailure>()),
      );
    });

    test('a building somebody else added is refused, and says so', () async {
      // The offline stand-in for "you did not add this one". On the server the
      // same rule is `created_by = auth.uid()`.
      await expectLater(
        () => repository.delete('knust-library'),
        throwsA(
          isA<OperationFailure>().having(
            (e) => e.message,
            'message',
            contains('person who added'),
          ),
        ),
      );
      expect(
        (await repository.nearby()).map((b) => b.id),
        contains('knust-library'),
      );
    });

    test('a building that is already gone is reported, not ignored', () async {
      expect(
        () => repository.delete('never-existed'),
        throwsA(isA<OperationFailure>()),
      );
    });

    test('its bookmark goes too', () async {
      final created = await addOne();
      await repository.setSaved(created.id, true);
      expect(await repository.isSaved(created.id), isTrue);

      await repository.delete(created.id);

      expect(
        (await repository.savedMaps()).map((b) => b.id),
        isNot(contains(created.id)),
      );
    });
  });
}
