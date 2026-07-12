import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

import 'package:echo_locate/data/repository_mixin.dart';
import 'package:echo_locate/features/auth/auth_repository.dart';

void main() {
  late Directory tempDir;
  late Box box;
  late MockAuthRepository repository;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('echo_locate_test');
    Hive.init(tempDir.path);
    box = await Hive.openBox('settings_test');
    repository = MockAuthRepository(box);
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await tempDir.delete(recursive: true);
  });

  test('sign up rejects short passwords with the design error message',
      () async {
    expect(
      () => repository.signUpWithEmail(
        fullName: 'John Adomako',
        email: 'john@knust.edu.gh',
        password: 'abc',
      ),
      throwsA(
        isA<OperationFailure>().having(
          (f) => f.message,
          'message',
          'Use at least 8 characters',
        ),
      ),
    );
  });

  test('sign up rejects invalid emails', () async {
    expect(
      () => repository.signUpWithEmail(
        fullName: 'John Adomako',
        email: 'not-an-email',
        password: 'longenough',
      ),
      throwsA(isA<OperationFailure>()),
    );
  });

  test('sign in succeeds, emits on the auth stream, and persists', () async {
    final emissions = <Object?>[];
    final sub = repository.authStateChanges.listen(emissions.add);

    final user = await repository.signInWithEmail(
      email: 'john@knust.edu.gh',
      password: 'longenough',
    );

    expect(user.email, 'john@knust.edu.gh');
    expect(repository.currentUser, isNotNull);
    // Session persisted: a new repository over the same box restores it.
    final revived = MockAuthRepository(box);
    expect(revived.currentUser?.email, 'john@knust.edu.gh');

    await pumpEventQueue();
    expect(emissions, hasLength(1));
    await sub.cancel();
  });

  test('sign out clears the session', () async {
    await repository.signInWithEmail(
      email: 'john@knust.edu.gh',
      password: 'longenough',
    );
    await repository.signOut();

    expect(repository.currentUser, isNull);
    expect(MockAuthRepository(box).currentUser, isNull);
  });
}
