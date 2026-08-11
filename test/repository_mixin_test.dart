import 'dart:async';
import 'dart:io';

import 'package:echo_locate/data/repository_mixin.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';

class _Repo with RepositoryMixin {}

void main() {
  late Directory directory;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('repo_cache_test');
    Hive.init(directory.path);
    await Hive.openBox(repoCacheBoxName);
  });

  tearDownAll(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  setUp(() => Hive.box(repoCacheBoxName).clear());

  final repo = _Repo();

  group('raw errors never reach the UI', () {
    // Every bloc catches OperationFailure and nothing else, on the strength of
    // this mixin's promise that "UI layers never see raw exceptions". It did
    // not keep that promise: a PostgrestException, a SocketException or a
    // HiveError escaped the handler, the bloc never emitted again, and the
    // screen sat on its spinner forever. That is what the user saw.

    test('a failing persisted query fails as an OperationFailure', () async {
      expect(
        () => repo.runPersistedQuery<int>('k', () => throw StateError('boom')),
        throwsA(isA<OperationFailure>()),
      );
    });

    test('a failing ephemeral query fails as an OperationFailure', () async {
      expect(
        () => repo.runEphemeralQuery<int>('k', () => throw StateError('boom')),
        throwsA(isA<OperationFailure>()),
      );
    });

    test('an uncached offline-first query fails as an OperationFailure',
        () async {
      expect(
        () => repo.runOfflineFirstQuery<int>(
          'k',
          () => throw const SocketException('no route to host'),
          encode: (v) => v,
          decode: (c) => c as int,
        ),
        throwsA(isA<OperationFailure>()),
      );
    });

    test('a connection failure says so, rather than "something went wrong"',
        () async {
      try {
        await repo.runOfflineFirstQuery<int>(
          'k',
          () => throw const SocketException('Failed host lookup'),
          encode: (v) => v,
          decode: (c) => c as int,
        );
        fail('should have thrown');
      } on OperationFailure catch (failure) {
        expect(failure.message.toLowerCase(), contains('connect'));
      }
    });

    test('the original error is kept for the log', () async {
      try {
        await repo.runEphemeralQuery<int>('k', () => throw StateError('boom'));
        fail('should have thrown');
      } on OperationFailure catch (failure) {
        expect(failure.cause, isA<StateError>());
      }
    });

    test('an OperationFailure from the fetch is passed through unchanged',
        () async {
      try {
        await repo.runEphemeralQuery<int>(
          'k',
          () => throw const OperationFailure('Not signed in'),
        );
        fail('should have thrown');
      } on OperationFailure catch (failure) {
        expect(failure.message, 'Not signed in');
      }
    });
  });

  group('a hung request gives up', () {
    // Measured on a device with no DNS: sign-in sat on its spinner for about
    // forty seconds before Android's resolver gave up. The error did arrive,
    // but nobody waits that long — to the user it is indistinguishable from
    // the app being broken, which is exactly the complaint.
    setUp(() => RepositoryMixin.requestTimeout =
        const Duration(milliseconds: 50));
    tearDown(() =>
        RepositoryMixin.requestTimeout = RepositoryMixin.defaultTimeout);

    test('a query that never answers fails as a connection problem', () async {
      final stopwatch = Stopwatch()..start();

      try {
        await repo.runEphemeralQuery<int>(
          'hangs',
          () => Completer<int>().future, // never completes
        );
        fail('should have thrown');
      } on OperationFailure catch (failure) {
        expect(failure.message.toLowerCase(), contains('connect'));
      }

      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));
    });

    test('a hung mutation gives up too', () async {
      expect(
        () => repo.runOperation<int>('save', () => Completer<int>().future),
        throwsA(isA<OperationFailure>()),
      );
    });

    test('the default gives a slow indoor connection room to answer', () {
      expect(
        RepositoryMixin.defaultTimeout,
        greaterThanOrEqualTo(const Duration(seconds: 10)),
      );
    });
  });

  group('caching still works', () {
    test('a persisted query caches and reads back', () async {
      var calls = 0;
      Future<int> fetch() async {
        calls++;
        return 7;
      }

      final first = await repo.runPersistedQuery<int>(
        'count',
        fetch,
        encode: (v) => v,
        decode: (c) => c as int,
      );
      final second = await repo.runPersistedQuery<int>(
        'count',
        fetch,
        encode: (v) => v,
        decode: (c) => c as int,
      );

      expect(first, 7);
      expect(second, 7);
      expect(calls, 1);
    });

    test('offline-first falls back to the cache when the fetch fails',
        () async {
      await repo.runOfflineFirstQuery<int>(
        'rooms',
        () async => 3,
        encode: (v) => v,
        decode: (c) => c as int,
      );

      final offline = await repo.runOfflineFirstQuery<int>(
        'rooms',
        () => throw const SocketException('offline'),
        encode: (v) => v,
        decode: (c) => c as int,
      );

      expect(offline, 3);
    });
  });
}
