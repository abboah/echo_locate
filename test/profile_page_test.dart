import 'package:echo_locate/core/models/auth_user.dart';
import 'package:echo_locate/core/models/user_profile.dart';
import 'package:echo_locate/core/theme/app_theme.dart';
import 'package:echo_locate/features/auth/auth_repository.dart';
import 'package:echo_locate/features/feedback/feedback_repository.dart';
import 'package:echo_locate/features/profile/bloc/profile_bloc.dart';
import 'package:echo_locate/features/profile/profile_repository.dart';
import 'package:echo_locate/ui/widgets/report_problem_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockProfiles extends Mock implements ProfileRepository {}

class _MockAuthRepository extends Mock implements AuthRepository {}

/// The Profile tab's account features.
///
/// It used to be a contributor card, three preferences and six `(dev)`
/// shortcuts to hardware probes. There was no way to change a name, no way to
/// leave, and no way to say a map was wrong — which matters more here than in
/// most apps, because a wrong map is invisible from the outside: the app will
/// confidently guide somebody into a wall and report success.
void main() {
  late _MockProfiles profiles;

  const ama = UserProfile(
    id: 'u1',
    fullName: 'Ama Mensah',
    email: 'ama@knust.edu.gh',
    buildingsMapped: 2,
    floorsMapped: 4,
    roomsMapped: 18,
  );

  setUp(() {
    profiles = _MockProfiles();
    when(() => profiles.currentProfile()).thenAnswer((_) async => ama);
  });

  group('renaming yourself', () {
    test('the new name replaces the old one', () async {
      when(
        () => profiles.updateName('Ama Mensah-Boateng'),
      ).thenAnswer((_) async => ama.copyWith(fullName: 'Ama Mensah-Boateng'));

      final bloc = ProfileBloc(profiles)..add(const ProfileStarted());
      await bloc.stream.firstWhere((s) => s.status == ProfileStatus.success);

      bloc.add(const ProfileNameChanged('Ama Mensah-Boateng'));
      final state = await bloc.stream.firstWhere(
        (s) => s.status == ProfileStatus.success,
      );

      expect(state.profile?.fullName, 'Ama Mensah-Boateng');
      await bloc.close();
    });

    test('a failed rename keeps the old name and says why', () async {
      when(() => profiles.updateName(any())).thenThrow(Exception('offline'));

      final bloc = ProfileBloc(profiles)..add(const ProfileStarted());
      await bloc.stream.firstWhere((s) => s.status == ProfileStatus.success);

      bloc.add(const ProfileNameChanged('Something Else'));
      final state = await bloc.stream.firstWhere(
        (s) => s.status == ProfileStatus.success,
      );

      // Still a perfectly good screen showing a perfectly good profile —
      // dropping to `failure` would replace the whole tab with an error.
      expect(state.profile?.fullName, 'Ama Mensah');
      expect(state.error, isNotNull);
      await bloc.close();
    });

    test('the screen can tell saving from saved', () async {
      // The dialog waits for this rather than assuming the write landed.
      when(() => profiles.updateName(any())).thenAnswer((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return ama.copyWith(fullName: 'New Name');
      });

      final bloc = ProfileBloc(profiles)..add(const ProfileStarted());
      await bloc.stream.firstWhere((s) => s.status == ProfileStatus.success);

      final seen = <ProfileStatus>[];
      final sub = bloc.stream.listen((s) => seen.add(s.status));
      bloc.add(const ProfileNameChanged('New Name'));
      await bloc.stream.firstWhere((s) => s.profile?.fullName == 'New Name');
      await sub.cancel();

      expect(seen, contains(ProfileStatus.saving));
      await bloc.close();
    });
  });

  group('the mock repository, which is what the offline build runs on', () {
    late MockProfileRepository repository;

    setUp(() {
      final auth = _MockAuthRepository();
      when(() => auth.currentUser).thenReturn(
        const AuthUser(
          id: 'u1',
          email: 'ama@knust.edu.gh',
          fullName: 'Ama Mensah',
        ),
      );
      repository = MockProfileRepository(auth);
    });

    test('a rename is readable back', () async {
      await repository.updateName('Ama Mensah-Boateng');

      expect(
        (await repository.currentProfile()).fullName,
        'Ama Mensah-Boateng',
      );
    });

    test('an empty name is refused', () async {
      expect(() => repository.updateName('   '), throwsA(isA<Exception>()));
    });
  });

  group('reporting a problem', () {
    testWidgets('a report carries what the user chose and wrote', (
      tester,
    ) async {
      FeedbackReport? captured;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  captured = await showModalBottomSheet<FeedbackReport>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) =>
                        const ReportProblemSheet(buildingId: 'knust-cs'),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('A map is wrong'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField),
        'The second door on the left is actually the third.',
      );
      await tester.tap(find.text('Send report'));
      await tester.pumpAndSettle();

      expect(captured, isNotNull);
      expect(captured!.kind, FeedbackKind.mapError);
      expect(captured!.message, contains('second door'));
      // Attached automatically: "the route was wrong" cannot be acted on
      // without knowing which building it was wrong in.
      expect(captured!.buildingId, 'knust-cs');
    });

    testWidgets('an empty report is refused rather than sent blank', (
      tester,
    ) async {
      var popped = false;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  await showModalBottomSheet<FeedbackReport>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => const ReportProblemSheet(),
                  );
                  popped = true;
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send report'));
      await tester.pumpAndSettle();

      expect(popped, isFalse, reason: 'the sheet stayed open');
      expect(find.text('Please say what went wrong.'), findsOneWidget);
    });
  });
}
