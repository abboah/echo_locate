import 'package:echo_locate/core/models/auth_user.dart';
import 'package:echo_locate/core/models/building.dart';
import 'package:echo_locate/core/theme/app_theme.dart';
import 'package:echo_locate/features/auth/auth_repository.dart';
import 'package:echo_locate/features/auth/bloc/auth_bloc.dart';
import 'package:echo_locate/features/buildings/building_repository.dart';
import 'package:echo_locate/features/home/bloc/home_bloc.dart';
import 'package:echo_locate/features/room_trace/room_plan_repository.dart';
import 'package:echo_locate/services/location/location_service.dart';
import 'package:echo_locate/ui/pages/home/home_page.dart';
import 'package:echo_locate/ui/widgets/plan_thumbnail.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'room_directions_test.dart' show buildWing;

class _MockBuildings extends Mock implements BuildingRepository {}

class _MockPlans extends Mock implements RoomPlanRepository {}

class _MockAuthRepository extends Mock implements AuthRepository {}

class _MockLocation extends Mock implements LocationService {}

/// Home's actions, its search, and where it says the user is.
///
/// Three of those were placeholders. The header read `KNUST, Kumasi` as a
/// literal on every phone; the search field was `readOnly` and its only
/// behaviour was to switch to the Explore tab; and the cards drew a stock
/// glyph even for buildings whose floors this device had traced.
void main() {
  late _MockBuildings buildings;
  late _MockPlans plans;
  late _MockLocation location;
  late AuthBloc auth;

  const knust = Building(
    id: 'knust-cs',
    name: 'College of Science',
    area: 'KNUST, Kumasi',
    floorsCount: 2,
    mappers: 3,
    mappedPercent: 40,
    distanceKm: 0.4,
    category: 'campus',
  );

  setUp(() {
    buildings = _MockBuildings();
    plans = _MockPlans();
    location = _MockLocation();

    // A real AuthBloc over a mock repository: `bloc_test` is deliberately not
    // a dependency here (its analyzer range fights freezed), so there is no
    // MockBloc to reach for.
    final repository = _MockAuthRepository();
    when(() => repository.currentUser).thenReturn(
      const AuthUser(
        id: 'u1',
        email: 'ama@knust.edu.gh',
        fullName: 'Ama Mensah',
      ),
    );
    when(
      () => repository.authStateChanges,
    ).thenAnswer((_) => const Stream<AuthUser?>.empty());
    auth = AuthBloc(repository);
    addTearDown(auth.close);

    when(() => buildings.recentlyMapped()).thenAnswer((_) async => [knust]);
    when(() => buildings.byId(any())).thenAnswer((_) async => knust);
    when(() => buildings.floorsOf(any())).thenAnswer(
      (_) async => const [BuildingFloor(id: 'gf', label: 'G', rooms: [])],
    );
    when(
      () => buildings.nearby(
        category: any(named: 'category'),
        query: any(named: 'query'),
        latitude: any(named: 'latitude'),
        longitude: any(named: 'longitude'),
      ),
    ).thenAnswer((_) async => [knust]);
    when(() => plans.allPlans()).thenAnswer((_) async => []);
    when(() => location.isGranted).thenAnswer((_) async => false);
    when(() => location.lastKnown).thenReturn(null);
  });

  Future<void> pump(
    WidgetTester tester, {
    ThemeData? theme,
    TextScaler textScaler = TextScaler.noScaling,
    Size size = const Size(390, 844),
  }) async {
    tester.view.physicalSize = size * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final bloc = HomeBloc(buildings, plans, location)
      ..add(const HomeStarted())
      ..add(const HomeLocationRequested());
    addTearDown(bloc.close);

    await tester.pumpWidget(
      MaterialApp(
        theme: theme ?? AppTheme.light,
        home: MediaQuery(
          data: MediaQueryData(size: size, textScaler: textScaler),
          child: MultiBlocProvider(
            providers: [
              BlocProvider<AuthBloc>.value(value: auth),
              BlocProvider<HomeBloc>.value(value: bloc),
            ],
            child: const HomeView(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('the screen', () {
    testWidgets('offers assistance, mapping and listening', (tester) async {
      await pump(tester);

      expect(find.text('Start assistance'), findsOneWidget);
      expect(find.text('Map a building'), findsOneWidget);
      expect(find.text('Identify this space'), findsOneWidget);
    });

    testWidgets('the recently mapped buildings load in', (tester) async {
      await pump(tester);

      expect(find.text('College of Science'), findsOneWidget);
    });

    testWidgets('renders in dark mode', (tester) async {
      await pump(tester, theme: AppTheme.dark);

      expect(find.text('Identify this space'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('where the user is', () {
    testWidgets('says nothing false while it does not know', (tester) async {
      await pump(tester);

      // Not "KNUST, Kumasi", which is what every phone in the world used to
      // read regardless of where it was.
      expect(find.text('KNUST, Kumasi'), findsNothing);
      expect(find.textContaining('Finding where you are'), findsOneWidget);
    });

    testWidgets('names the place once located', (tester) async {
      const here = UserLocation(latitude: 6.67, longitude: -1.57);
      when(() => location.isGranted).thenAnswer((_) async => true);
      when(() => location.current()).thenAnswer((_) async => here);
      when(
        () => location.placeName(here),
      ).thenAnswer((_) async => 'Kumasi, Ashanti');

      await pump(tester);

      expect(find.text('Kumasi, Ashanti'), findsOneWidget);
    });

    testWidgets('a refused permission is not an error', (tester) async {
      when(() => location.isGranted).thenAnswer((_) async => false);

      await pump(tester);

      expect(tester.takeException(), isNull);
      // The rest of the screen is unaffected.
      expect(find.text('Start assistance'), findsOneWidget);
      verifyNever(() => location.current());
    });
  });

  group('search', () {
    testWidgets('finds buildings instead of leaving the screen', (
      tester,
    ) async {
      await pump(tester);

      await tester.enterText(find.byType(TextField), 'science');
      // Past the debounce.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(find.text('1 RESULT'), findsOneWidget);
      expect(find.text('College of Science'), findsOneWidget);
      // The browsing half is out of the way while searching.
      expect(find.text('Start assistance'), findsNothing);
    });

    testWidgets('a search matching nothing offers to add the building', (
      tester,
    ) async {
      when(
        () => buildings.nearby(
          category: any(named: 'category'),
          query: any(named: 'query'),
          latitude: any(named: 'latitude'),
          longitude: any(named: 'longitude'),
        ),
      ).thenAnswer((_) async => []);

      await pump(tester);
      await tester.enterText(find.byType(TextField), 'nowhere hall');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      // The index is crowdsourced, so "not found" is an invitation.
      expect(find.text('Add this building'), findsOneWidget);
    });

    testWidgets('clearing goes back to the ordinary screen', (tester) async {
      await pump(tester);

      await tester.enterText(find.byType(TextField), 'science');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.text('Start assistance'), findsNothing);

      await tester.tap(find.byTooltip('Clear search'));
      await tester.pumpAndSettle();

      expect(find.text('Start assistance'), findsOneWidget);
    });

    testWidgets('one query per pause, not one per keystroke', (tester) async {
      await pump(tester);

      final field = find.byType(TextField);
      for (final text in ['s', 'sc', 'sci', 'scie']) {
        await tester.enterText(field, text);
        await tester.pump(const Duration(milliseconds: 60));
      }
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      verify(
        () => buildings.nearby(
          category: any(named: 'category'),
          query: 'scie',
          latitude: any(named: 'latitude'),
          longitude: any(named: 'longitude'),
        ),
      ).called(1);
      verifyNever(
        () => buildings.nearby(
          category: any(named: 'category'),
          query: 'sc',
          latitude: any(named: 'latitude'),
          longitude: any(named: 'longitude'),
        ),
      );
    });
  });

  group('layout', () {
    testWidgets('draws the traced floor on a card that has one', (
      tester,
    ) async {
      when(
        () => plans.allPlans(),
      ).thenAnswer((_) async => [buildWing().copyWith(buildingId: 'knust-cs')]);

      await pump(tester);

      // The actual shape of the building, not the stock glyph every card used
      // to share. Two of them: the walk row above and the grid card below,
      // both drawing the one floor this device holds.
      expect(find.byType(PlanThumbnail), findsNWidgets(2));
    });

    testWidgets('falls back to the glyph when nothing is traced', (
      tester,
    ) async {
      await pump(tester);

      expect(find.byType(PlanThumbnail), findsNothing);
      expect(find.text('College of Science'), findsOneWidget);
    });

    testWidgets('survives the system font turned up', (tester) async {
      await pump(tester, textScaler: const TextScaler.linear(1.8));

      expect(tester.takeException(), isNull);
    });

    testWidgets('lays out on a small phone without overflowing', (
      tester,
    ) async {
      // 320dp is the narrowest Android target still in use, and the layout was
      // pinned to a 22-point gutter and two grid columns whatever the width.
      await pump(tester, size: const Size(320, 640));

      expect(tester.takeException(), isNull);
    });

    testWidgets('lays out on a tablet without overflowing', (tester) async {
      await pump(tester, size: const Size(1024, 768));

      expect(tester.takeException(), isNull);
    });

    testWidgets('the action rows do not overflow on a narrow phone', (
      tester,
    ) async {
      // The bug in the screenshot. "Map a building" and "Identify this space"
      // were a pair of `Expanded` tiles inside an `IntrinsicHeight`, which
      // measures a `Text` at its *unconstrained* width — one line — so a title
      // that wrapped to two overflowed the box it had been given. Rows need no
      // such measurement.
      await pump(tester, size: const Size(340, 720));

      expect(tester.takeException(), isNull);
      expect(find.text('Map a building'), findsOneWidget);
      expect(find.text('Identify this space'), findsOneWidget);
    });

    testWidgets('and do not overflow with a large font either', (tester) async {
      await pump(
        tester,
        size: const Size(340, 720),
        textScaler: const TextScaler.linear(2),
      );

      expect(tester.takeException(), isNull);
    });
  });

  group('walking a floor', () {
    testWidgets('a traced floor can be walked straight from Home', (
      tester,
    ) async {
      // The point of the whole app, and it used to be four taps away: Maps, a
      // building, a floor, then walk.
      when(
        () => plans.allPlans(),
      ).thenAnswer((_) async => [buildWing().copyWith(buildingId: 'knust-cs')]);

      await pump(tester);

      expect(find.text('WALK A FLOOR'), findsOneWidget);
      expect(find.text('Ground floor'), findsOneWidget);
      expect(find.text('College of Science'), findsWidgets);
    });

    testWidgets('a floor that cannot be walked is not offered', (tester) async {
      // Rooms but no doors: it draws correctly, routes nowhere, and offering
      // to walk it is a promise the app cannot keep. It belongs on Maps, where
      // finishing it is the point.
      when(() => plans.allPlans()).thenAnswer(
        (_) async => [
          buildWing().copyWith(
            buildingId: 'knust-cs',
            storedOpenings: const [],
            declaredDoorCounts: const {},
          ),
        ],
      );

      await pump(tester);

      expect(find.text('WALK A FLOOR'), findsNothing);
    });

    testWidgets('the shelf hides itself when nothing is traced', (
      tester,
    ) async {
      await pump(tester);

      expect(find.text('WALK A FLOOR'), findsNothing);
      // The rest of Home is unaffected.
      expect(find.text('Start assistance'), findsOneWidget);
    });

    testWidgets('one floor gets a full-width row, not a lonely card', (
      tester,
    ) async {
      // The screenshot problem: a single square card in a full-width row
      // leaves two thirds of the screen empty beside it and reads as a layout
      // fault. On a fresh install one floor is the normal case.
      when(
        () => plans.allPlans(),
      ).thenAnswer((_) async => [buildWing().copyWith(buildingId: 'knust-cs')]);

      await pump(tester);

      expect(find.text('Ground floor'), findsOneWidget);
      // The row carries the extra line a card has no space for.
      expect(find.textContaining('ready to walk'), findsOneWidget);
      // And no horizontal shelf to scroll.
      expect(
        find.byWidgetPredicate(
          (w) => w is ListView && w.scrollDirection == Axis.horizontal,
        ),
        findsNothing,
      );
    });

    testWidgets('several floors get a scrollable shelf of square cards', (
      tester,
    ) async {
      when(() => plans.allPlans()).thenAnswer(
        (_) async => [
          buildWing().copyWith(buildingId: 'knust-cs', floorId: 'gf'),
          buildWing().copyWith(buildingId: 'knust-cs', floorId: 'floor-1'),
          buildWing().copyWith(buildingId: 'knust-cs', floorId: 'floor-2'),
        ],
      );

      await pump(tester);

      expect(
        find.byWidgetPredicate(
          (w) => w is ListView && w.scrollDirection == Axis.horizontal,
        ),
        findsOneWidget,
      );
      expect(find.text('Ground floor'), findsOneWidget);
      expect(find.text('Floor 1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an unreachable index does not empty the shelf', (
      tester,
    ) async {
      // The floors are on the device; the names are not. A shelf that hides
      // itself offline would hide the one thing that still works offline.
      when(() => buildings.byId(any())).thenThrow(Exception('offline'));
      when(() => buildings.floorsOf(any())).thenThrow(Exception('offline'));
      when(
        () => plans.allPlans(),
      ).thenAnswer((_) async => [buildWing().copyWith(buildingId: 'knust-cs')]);

      await pump(tester);

      expect(find.text('WALK A FLOOR'), findsOneWidget);
      // `gf` still reads as the ground floor without the index to say so.
      expect(find.text('Ground floor'), findsOneWidget);
    });
  });

  group('managing a building from the list', () {
    testWidgets('every card offers rename and remove', (tester) async {
      await pump(tester);

      await tester.tap(find.byTooltip('Options for College of Science'));
      await tester.pumpAndSettle();

      // An explicit button, not a long-press: a gesture with no visible
      // target is a feature this app's users would never find.
      expect(find.text('Rename'), findsOneWidget);
      expect(find.text('Remove building'), findsOneWidget);
    });

    testWidgets('removing asks first and states the rule', (tester) async {
      await pump(tester);

      await tester.tap(find.byTooltip('Options for College of Science'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove building'));
      await tester.pumpAndSettle();

      expect(find.text('Remove College of Science?'), findsOneWidget);
      // The rule, before the attempt rather than as an error afterwards.
      expect(
        find.textContaining('nobody else has mapped a floor here'),
        findsOneWidget,
      );

      await tester.tap(find.text('Keep it'));
      await tester.pumpAndSettle();
      expect(find.text('College of Science'), findsWidgets);
    });
  });

  group('pull to refresh', () {
    testWidgets('re-reads the buildings and the location', (tester) async {
      await pump(tester);
      clearInteractions(buildings);

      await tester.fling(
        find.byType(ListView).first,
        const Offset(0, 400),
        1000,
      );
      await tester.pumpAndSettle();

      // Everything on Home is somebody else's data and it changes while the
      // app is open; without this the only way to see any of it was to kill
      // the app.
      verify(() => buildings.recentlyMapped()).called(greaterThan(0));
      verify(() => location.isGranted).called(greaterThan(0));
    });
  });
}
