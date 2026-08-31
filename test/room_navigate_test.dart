import 'package:echo_locate/features/room_navigate/bloc/room_navigate_cubit.dart';
import 'package:echo_locate/core/models/user_profile.dart';
import 'package:echo_locate/features/profile/profile_repository.dart';
import 'package:echo_locate/features/room_trace/room_plan_repository.dart';
import 'package:echo_locate/ui/pages/room_navigate/room_navigate_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'room_directions_test.dart' show buildWing;

class _MockPlans extends Mock implements RoomPlanRepository {}

class _MockProfiles extends Mock implements ProfileRepository {}

void main() {
  late _MockPlans plans;

  setUp(() {
    plans = _MockPlans();
    when(
      () => plans.planFor(any(), any()),
    ).thenAnswer((_) async => buildWing());
  });

  Future<RoomNavigateCubit> opened() async {
    final cubit = RoomNavigateCubit(plans);
    await cubit.load(buildingId: 'knust-cs', floorId: 'gf');
    return cubit;
  }

  group('opening a floor', () {
    test('picks two rooms so a route is drawn immediately', () async {
      final cubit = await opened();

      expect(cubit.state.status, RoomNavigateStatus.ready);
      expect(cubit.state.fromRoomId, isNotNull);
      expect(cubit.state.toRoomId, isNotNull);
      expect(cubit.state.hasRoute, isTrue);
      await cubit.close();
    });

    test('a floor with nothing on it says so', () async {
      when(() => plans.planFor(any(), any())).thenAnswer((_) async => null);

      final cubit = await opened();

      expect(cubit.state.status, RoomNavigateStatus.empty);
      await cubit.close();
    });

    test('corridors can be started from but not navigated to', () async {
      final cubit = await opened();

      // Nobody navigates *to* a corridor; standing in one is exactly where
      // somebody sets off from.
      expect(
        cubit.state.destinations.any((room) => room.isCirculation),
        isFalse,
      );
      expect(cubit.state.origins.any((room) => room.isCirculation), isTrue);
      await cubit.close();
    });
  });

  group('arriving with a destination already chosen', () {
    Future<RoomNavigateCubit> openedTo(String? roomId) async {
      final cubit = RoomNavigateCubit(plans);
      await cubit.load(
        buildingId: 'knust-cs',
        floorId: 'gf',
        destinationRoomId: roomId,
      );
      return cubit;
    }

    test('opens on the room the user tapped', () async {
      // Tapping "Digital Forensic Office" on the building screen and then
      // being asked to pick it again out of a dropdown is the same question
      // twice.
      final cubit = await openedTo('n2');

      expect(cubit.state.toRoomId, 'n2');
      expect(cubit.state.hasRoute, isTrue);
      await cubit.close();
    });

    test('never plans a route from a room to itself', () async {
      // The default origin and the tapped destination can be the same room.
      final defaults = await openedTo(null);
      final origin = defaults.state.fromRoomId!;
      await defaults.close();

      final cubit = await openedTo(origin);

      expect(cubit.state.toRoomId, origin);
      expect(cubit.state.fromRoomId, isNot(origin));
      await cubit.close();
    });

    test(
      'a room this floor no longer contains falls back to a default',
      () async {
        // The plan may have been retraced since the link was made. Landing on
        // the floor beats an error about a room.
        final cubit = await openedTo('retraced-away');

        expect(cubit.state.status, RoomNavigateStatus.ready);
        expect(cubit.state.toRoomId, isNotNull);
        expect(cubit.state.hasRoute, isTrue);
        await cubit.close();
      },
    );
  });

  group('THE POINT: a mapped floor can actually be walked', () {
    test('assembles everything GuidanceBloc needs', () async {
      final cubit = await opened();
      cubit.selectFrom('lobby');
      cubit.selectTo('n2');

      final session = cubit.sessionFor(initialHeading: const Offset(1, 0));

      // Before this screen existed, RoomPlanBridge was tested and called by
      // nothing — a floor could be mapped in full and then not walked.
      expect(session, isNotNull);
      expect(session!.destinationName, 'Digital Forensic Office');
      expect(session.landmarks, isNotEmpty);
      expect(session.graph, isNotNull);
      await cubit.close();
    });

    test('the door count reaches guidance as words it will speak', () async {
      final cubit = await opened();
      cubit.selectFrom('lobby');
      cubit.selectTo('n2');

      final session = cubit.sessionFor(initialHeading: const Offset(1, 0))!;
      final spoken = session.plan.legs
          .map((leg) => leg.instruction ?? '')
          .join(' ');

      // The sentence the whole feature exists for, arriving at the screen
      // that says it out loud.
      expect(spoken, contains('second door on your left'));
      await cubit.close();
    });

    test(
      'a traced floor is marked non-metric so no fake steps are spoken',
      () async {
        final cubit = await opened();
        cubit.selectFrom('lobby');
        cubit.selectTo('n2');

        expect(cubit.sessionFor()!.metric, isFalse);
        await cubit.close();
      },
    );

    test('no session for two rooms nothing joins', () async {
      when(() => plans.planFor(any(), any())).thenAnswer(
        (_) async => buildWing().copyWith(
          storedOpenings: const [],
          declaredDoorCounts: const {},
        ),
      );

      final cubit = await opened();
      cubit.selectFrom('lobby');
      cubit.selectTo('n2');

      expect(cubit.sessionFor(), isNull);
      expect(cubit.state.isUnreachable, isTrue);
      await cubit.close();
    });

    test('no session for a room to itself', () async {
      final cubit = await opened();
      cubit.selectFrom('n2');
      cubit.selectTo('n2');

      expect(cubit.sessionFor(), isNull);
      await cubit.close();
    });
  });

  group('the preview', () {
    test('shows what will be said before setting off', () async {
      final cubit = await opened();
      cubit.selectFrom('lobby');
      cubit.selectTo('n3');

      expect(cubit.state.preview, isNotEmpty);
      expect(
        cubit.state.preview.map((i) => i.text).join(' '),
        contains('door on your'),
      );
      await cubit.close();
    });

    test('reversing is a different walk, not the same one backwards', () async {
      final cubit = await opened();
      cubit.selectFrom('lobby');
      cubit.selectTo('n3');
      final forwards = cubit.state.preview.map((i) => i.text).toList();

      cubit.reverse();
      final backwards = cubit.state.preview.map((i) => i.text).toList();

      // Every ordinal and every turn changes with the heading.
      expect(backwards, isNot(equals(forwards)));
      await cubit.close();
    });

    test('warns when door counts on this route are incomplete', () async {
      when(
        () => plans.planFor(any(), any()),
      ).thenAnswer((_) async => buildWing(declareDoors: false));

      final cubit = await opened();
      cubit.selectFrom('lobby');
      cubit.selectTo('n2');

      expect(cubit.state.ordinalsAreSafe, isFalse);
      // Still walkable — it just will not name which door.
      expect(cubit.state.hasRoute, isTrue);
      await cubit.close();
    });
  });

  group('the screen', () {
    Widget host({Brightness brightness = Brightness.light}) => MaterialApp(
      theme: ThemeData(brightness: brightness),
      home: BlocProvider(
        create: (_) =>
            RoomNavigateCubit(plans)
              ..load(buildingId: 'knust-cs', floorId: 'gf'),
        child: const RoomNavigateView(),
      ),
    );

    testWidgets('offers a start, a destination and the instructions', (
      tester,
    ) async {
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      expect(find.text('From'), findsOneWidget);
      expect(find.text('To'), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, 'Start guidance'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('says when two rooms are not joined', (tester) async {
      when(() => plans.planFor(any(), any())).thenAnswer(
        (_) async => buildWing().copyWith(
          storedOpenings: const [],
          declaredDoorCounts: const {},
        ),
      );

      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      expect(find.textContaining('a door is missing'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Start guidance'),
            )
            .onPressed,
        isNull,
      );
    });

    testWidgets('renders in dark mode', (tester) async {
      await tester.pumpWidget(host(brightness: Brightness.dark));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });

  group('measuring your step', () {
    const uncalibrated = UserProfile(
      id: 'u1',
      fullName: 'Ama Mensah',
      email: 'ama@knust.edu.gh',
    );

    Future<RoomNavigateCubit> openedWith(UserProfile profile) async {
      final profiles = _MockProfiles();
      when(() => profiles.currentProfile()).thenAnswer((_) async => profile);
      final cubit = RoomNavigateCubit(plans, profiles);
      await cubit.load(buildingId: 'knust-cs', floorId: 'gf');
      return cubit;
    }

    test('offered on a floor with a scale when nobody has measured', () async {
      // The row moved off Profile, where it asked before the user had walked
      // anywhere. Here the route is drawn and the distance about to be spoken
      // is a generic adult's rather than theirs.
      when(
        () => plans.planFor(any(), any()),
      ).thenAnswer((_) async => buildWing().copyWith(metresPerUnit: 1));

      final cubit = await openedWith(uncalibrated);

      expect(cubit.state.shouldOfferStride, isTrue);
      await cubit.close();
    });

    test('not offered once it has been measured', () async {
      when(
        () => plans.planFor(any(), any()),
      ).thenAnswer((_) async => buildWing().copyWith(metresPerUnit: 1));

      final cubit = await openedWith(
        uncalibrated.copyWith(strideLengthM: 0.72),
      );

      expect(cubit.state.shouldOfferStride, isFalse);
      await cubit.close();
    });

    test('not offered on a floor with no scale', () async {
      // Without a scale no distance is spoken at all, so measuring a step
      // would change nothing and the offer would be noise.
      final cubit = await openedWith(uncalibrated);

      expect(cubit.state.plan?.isMetric, isFalse);
      expect(cubit.state.shouldOfferStride, isFalse);
      await cubit.close();
    });

    test('a screen with no profile repository never nags', () async {
      final cubit = RoomNavigateCubit(plans);
      await cubit.load(buildingId: 'knust-cs', floorId: 'gf');

      expect(cubit.state.shouldOfferStride, isFalse);
      await cubit.close();
    });
  });
}
