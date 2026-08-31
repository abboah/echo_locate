import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../../core/models/building.dart';
import '../../../core/models/room_plan.dart';
import '../../../core/routes/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimens.dart';
import '../../../features/auth/bloc/auth_bloc.dart';
import '../../../features/home/bloc/home_bloc.dart';
import '../../../services/injection_container.dart';
import '../../widgets/app_search_field.dart';
import '../../widgets/building_actions.dart';
import '../../widgets/building_glyph.dart';
import '../../widgets/building_list_tile.dart';
import '../../widgets/percent_badge.dart';
import '../../widgets/plan_thumbnail.dart';
import '../../widgets/responsive.dart';
import '../../widgets/section_label.dart';
import '../camera_flow.dart';

/// Home tab (Figma 7:488, assist-first): where you are, search, assistance,
/// mapping, and what has been mapped.
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<HomeBloc>()
        ..add(const HomeStarted())
        // Separately, and not awaited: a location fix takes seconds indoors
        // and may never arrive, and none of the screen depends on it.
        ..add(const HomeLocationRequested()),
      child: const HomeView(),
    );
  }
}

/// The screen itself, given its blocs already in the tree — so it can be
/// tested against mock repositories, the way the other screens are.
class HomeView extends StatelessWidget {
  const HomeView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: BlocBuilder<HomeBloc, HomeState>(
          // Pull to refresh. Everything on this screen is somebody else's
          // data — the buildings people are adding, the floors they are
          // tracing — and it changes while the app is open. Without this the
          // only way to see any of it was to kill the app.
          builder: (context, state) => RefreshIndicator(
            onRefresh: () async {
              final bloc = context.read<HomeBloc>()..add(const HomeStarted());
              // Location too: somebody pulling to refresh has usually moved.
              bloc.add(const HomeLocationRequested());
              await bloc.stream.firstWhere(
                (state) => state.status != HomeStatus.loading,
              );
            },
            child: ListView(
              // Always scrollable, so the gesture works on a short screen —
              // a fresh install with nothing mapped is exactly when somebody
              // pulls to see whether anything arrived.
              physics: const AlwaysScrollableScrollPhysics(),
              padding: Responsive.pagePadding(context),
              children: [
                const _Greeting(),
                const SizedBox(height: AppDimens.space20),
                const _Search(),
                const SizedBox(height: AppDimens.space20),
                // Searching replaces the screen rather than pushing a new one.
                // The field, the results and the way back out stay in one
                // place, and the keyboard never has a route change under it.
                if (state.isSearching)
                  _Results(state: state)
                else
                  ..._browse(context, state),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The ordinary Home: what the app does, and what has been mapped.
  List<Widget> _browse(BuildContext context, HomeState state) => [
    const _AssistBanner(),
    // **Walking a floor, from the screen the app opens on.**
    //
    // This is what the whole app is for, and it used to be four taps away:
    // Maps, a building, a floor, then walk. A floor already traced onto this
    // phone is one tap now.
    if (state.walkable.isNotEmpty) ...[
      const SizedBox(height: AppDimens.space24),
      const SectionLabel('Walk a floor'),
      const SizedBox(height: AppDimens.space12),
      _WalkShelf(floors: state.walkable),
    ],
    const SizedBox(height: AppDimens.space12),
    const _SecondaryActions(),
    const SizedBox(height: AppDimens.space24),
    SectionLabel(
      'Recently mapped',
      // A `GestureDetector` around a `Text` is a button to a sighted user and
      // a sentence to a screen reader. `TextButton` is both, and brings a real
      // touch target and a pressed state with it.
      trailing: TextButton(
        onPressed: () => context.goNamed(RouteNames.explore),
        child: const Text('See all'),
      ),
    ),
    const SizedBox(height: AppDimens.space12),
    switch (state.status) {
      HomeStatus.initial || HomeStatus.loading => const Padding(
        padding: EdgeInsets.symmetric(vertical: AppDimens.space48),
        child: Center(child: CircularProgressIndicator()),
      ),
      HomeStatus.failure => _LoadError(
        message: state.error ?? 'Could not load buildings',
        onRetry: () => context.read<HomeBloc>().add(const HomeStarted()),
      ),
      HomeStatus.success when state.recent.isEmpty => const _NothingMapped(),
      HomeStatus.success => GridView.count(
        // Was a hard-coded 2 columns at a 0.82 aspect ratio, which on a small
        // phone squeezed the cards and on a tablet stretched two of them
        // across the whole width.
        crossAxisCount: Responsive.gridColumns(context),
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: AppDimens.space16,
        crossAxisSpacing: AppDimens.space16,
        childAspectRatio: Responsive.cardAspectRatio(context),
        children: [
          for (final building in state.recent)
            _BuildingCard(
              building: building,
              plan: state.planFor(building.id),
              onChanged: () =>
                  context.read<HomeBloc>().add(const HomeStarted()),
            ),
        ],
      ),
    },
  ];
}

/// Where the user is, and who they are.
class _Greeting extends StatelessWidget {
  const _Greeting();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authState = context.watch<AuthBloc>().state;
    final user = authState is AuthAuthenticated ? authState.user : null;
    final place = context.select((HomeBloc bloc) => bloc.state.placeName);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    PhosphorIconsFill.mapPin,
                    size: 14,
                    color: place == null
                        ? theme.textTheme.bodyMedium?.color
                        : AppColors.coral,
                  ),
                  const SizedBox(width: AppDimens.space4),
                  Expanded(
                    child: Text(
                      // Read `KNUST, Kumasi` as a literal on every phone in
                      // the world until location was wired up. Says nothing
                      // rather than something false while it is unknown —
                      // which includes a refused permission, since indoor
                      // navigation does not depend on this.
                      place ?? 'Finding where you are…',
                      style: theme.textTheme.bodyMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              Text('Where to?', style: theme.textTheme.displaySmall),
            ],
          ),
        ),
        const SizedBox(width: AppDimens.space12),
        Semantics(
          label: user == null
              ? 'Your profile'
              : 'Signed in as ${user.fullName}',
          child: ExcludeSemantics(
            child: CircleAvatar(
              radius: 20,
              backgroundColor: AppColors.coralSoft,
              child: Text(
                user?.initial ?? '?',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: AppColors.coral,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Home's search field.
///
/// It used to be `readOnly: true` with an `onTap` that switched to the Explore
/// tab — a search box that could not be typed into, whose only behaviour was
/// to take you somewhere else and make you start again. It searches now, and
/// the results land underneath it.
class _Search extends StatefulWidget {
  const _Search();

  @override
  State<_Search> createState() => _SearchState();
}

class _SearchState extends State<_Search> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final searching = context.select((HomeBloc bloc) => bloc.state.isSearching);

    return AppSearchField(
      controller: _controller,
      hint: 'Search buildings',
      onChanged: (query) =>
          context.read<HomeBloc>().add(HomeSearchChanged(query)),
      onClear: !searching
          ? null
          : () {
              _controller.clear();
              context.read<HomeBloc>().add(const HomeSearchCleared());
              FocusScope.of(context).unfocus();
            },
    );
  }
}

/// What the search found.
class _Results extends StatelessWidget {
  const _Results({required this.state});

  final HomeState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (state.searching && state.results.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppDimens.space32),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (state.foundNothing) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppDimens.space32),
        child: Column(
          children: [
            Text(
              'No building matches "${state.query}".',
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppDimens.space16),
            // The index is crowdsourced, so "not found" is an invitation.
            OutlinedButton.icon(
              onPressed: () => context.pushNamed(RouteNames.mapBuilding),
              icon: const Icon(PhosphorIconsRegular.plus, size: 18),
              label: const Text('Add this building'),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel(
          '${state.results.length} '
          '${state.results.length == 1 ? 'result' : 'results'}',
        ),
        const SizedBox(height: AppDimens.space8),
        for (final building in state.results) ...[
          BuildingListTile(building: building),
          Divider(height: AppDimens.space24, color: theme.dividerColor),
        ],
      ],
    );
  }
}

/// Nothing mapped yet — on a fresh install, the whole of Home's lower half.
class _NothingMapped extends StatelessWidget {
  const _NothingMapped();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(AppDimens.space20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppDimens.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Nothing mapped here yet', style: theme.textTheme.titleMedium),
          const SizedBox(height: AppDimens.space4),
          Text(
            'Buildings appear here once somebody traces a floor. Yours can be '
            'the first.',
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

/// Dark "Start assistance" banner — the headline action.
class _AssistBanner extends StatelessWidget {
  const _AssistBanner();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background = isDark ? AppColors.darkElevated : AppColors.ink;

    return Semantics(
      button: true,
      label:
          'Start assistance. Obstacle alerts and voice guidance as you walk.',
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(AppDimens.radiusLg),
        child: InkWell(
          onTap: () => openAssistFlow(context),
          borderRadius: BorderRadius.circular(AppDimens.radiusLg),
          child: Padding(
            padding: const EdgeInsets.all(AppDimens.space16),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    color: AppColors.coral,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    PhosphorIconsFill.eye,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                const SizedBox(width: AppDimens.space12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Start assistance',
                        style: Theme.of(
                          context,
                        ).textTheme.titleMedium?.copyWith(color: Colors.white),
                      ),
                      Text(
                        'Obstacle alerts and voice guidance as you walk',
                        style: Theme.of(
                          context,
                        ).textTheme.bodyMedium?.copyWith(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  PhosphorIconsRegular.caretRight,
                  color: Colors.white70,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The contributor action that maps a building: trace the floor plan posted on
/// its wall.
///
/// The only authoring path, and deliberately so. Traced coordinates are
/// absolute, it needs neither ARCore nor a working pedometer, and it therefore
/// works identically on every phone — which is what keeps contributing open to
/// the handsets most contributors actually own.
///
/// Goes to the "what are you mapping" chooser rather than Explore: Explore
/// only lists buildings somebody has already added, which strands the
/// contributor standing in one nobody has — the case mapping exists for.
/// The two rounded squares under the assistance banner.
///
/// **Sized from the width, not measured from the children.** They were a pair
/// of `Expanded` tiles inside an `IntrinsicHeight`, which overflowed by 24
/// pixels: `IntrinsicHeight` measures a `Text` at its *unconstrained* width —
/// one line — so a title that wraps to two makes the box it hands down too
/// short. No amount of tuning fixes that while the height comes from the
/// measurement.
///
/// A `LayoutBuilder` knows the width before anything is laid out, and the
/// tiles are square by definition, so the height is arithmetic rather than a
/// guess. It grows with the system font instead of clipping, and the copy
/// inside is `Flexible` so even a wrong sum cannot overflow — only ellipsise.
class _SecondaryActions extends StatelessWidget {
  const _SecondaryActions();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = (constraints.maxWidth - AppDimens.space12) / 2;
        final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
        return SizedBox(
          // Square *plus* the room two lines of title and two of detail
          // actually need. A true square clipped "Identify this space" through
          // the middle of its second line: the shape is the point, but not at
          // the cost of the words inside it.
          height: (side + 28) * scale.clamp(1.0, 1.5),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _TraceCard()),
              SizedBox(width: AppDimens.space12),
              Expanded(child: _ListenCard()),
            ],
          ),
        );
      },
    );
  }
}

class _TraceCard extends StatelessWidget {
  const _TraceCard();

  @override
  Widget build(BuildContext context) => _ActionTile(
    icon: PhosphorIconsFill.mapTrifold,
    title: 'Map a building',
    detail: 'Trace its rooms off the plan on its wall',
    semanticLabel:
        'Map a building. Trace its rooms off the plan posted on its wall.',
    tinted: true,
    // No `extra`: this card means tracing, so the picker keeps its default
    // destination.
    onTap: (context) => context.pushNamed(RouteNames.mapBuilding),
  );
}

/// The floors this phone can guide somebody along.
///
/// **Two shapes, because one floor and six floors are different problems.**
/// A single square card in a full-width row leaves two thirds of the screen
/// empty beside it and reads as a layout fault rather than as a list with one
/// item in it — and on a fresh install one floor is the normal case. So a lone
/// floor gets a full-width row, and a shelf only appears once there is
/// something to scroll.
class _WalkShelf extends StatelessWidget {
  const _WalkShelf({required this.floors});

  final List<WalkableFloor> floors;

  @override
  Widget build(BuildContext context) {
    if (floors.length == 1) return _WalkRow(floor: floors.single);

    // Grows with the system font instead of clipping the labels, which is the
    // failure this app can least afford. The card is a square plan plus two
    // lines, so the height follows the width.
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final height = _WalkCard.width + 56.0 * scale.clamp(1.0, 1.8);

    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        itemCount: floors.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppDimens.space12),
        itemBuilder: (context, index) => _WalkCard(floor: floors[index]),
      ),
    );
  }
}

/// Where a walk card goes when tapped, and what a screen reader calls it.
///
/// Shared by both shapes so the two can never drift apart on the thing that
/// matters — the route they open.
extension on WalkableFloor {
  String get walkLabel =>
      'Walk $floorTitle of $buildingName. '
      '$roomCount ${roomCount == 1 ? 'room' : 'rooms'}.';

  void openWalk(BuildContext context) => context.pushNamed(
    RouteNames.roomNavigate,
    pathParameters: {'id': plan.buildingId},
    extra: plan.floorId,
  );
}

/// The single-floor shape: a square plan beside its name, full width.
class _WalkRow extends StatelessWidget {
  const _WalkRow({required this.floor});

  final WalkableFloor floor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final rooms = floor.roomCount;

    return Semantics(
      button: true,
      label: floor.walkLabel,
      child: ExcludeSemantics(
        child: Material(
          color: isDark ? AppColors.darkSurface : AppColors.white,
          borderRadius: BorderRadius.circular(AppDimens.radiusLg),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppDimens.radiusLg),
            onTap: () => floor.openWalk(context),
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: theme.dividerColor),
                borderRadius: BorderRadius.circular(AppDimens.radiusLg),
              ),
              padding: const EdgeInsets.all(AppDimens.space12),
              child: Row(
                children: [
                  // Square, so the plan is read as a plan rather than as a
                  // banner cropped out of one.
                  PlanThumbnail(plan: floor.plan, size: 72),
                  const SizedBox(width: AppDimens.space12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          floor.floorTitle,
                          style: theme.textTheme.titleMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          floor.buildingName,
                          style: theme.textTheme.bodyMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: AppDimens.space2),
                        Text(
                          '$rooms ${rooms == 1 ? 'room' : 'rooms'} · ready to '
                          'walk',
                          style: theme.textTheme.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppDimens.space8),
                  const Icon(
                    PhosphorIconsFill.navigationArrow,
                    size: 20,
                    color: AppColors.coral,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The many-floors shape: a square plan above its name.
class _WalkCard extends StatelessWidget {
  const _WalkCard({required this.floor});

  /// Also the height of the plan inside it, which is square.
  static const double width = 148;

  final WalkableFloor floor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Semantics(
      button: true,
      label: floor.walkLabel,
      child: ExcludeSemantics(
        child: SizedBox(
          width: width,
          child: Material(
            color: isDark ? AppColors.darkSurface : AppColors.white,
            borderRadius: BorderRadius.circular(AppDimens.radiusLg),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppDimens.radiusLg),
              onTap: () => floor.openWalk(context),
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: theme.dividerColor),
                  borderRadius: BorderRadius.circular(AppDimens.radiusLg),
                ),
                padding: const EdgeInsets.all(AppDimens.space8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Square rather than "whatever is left over": a plan
                    // stretched into a letterbox is not the shape of the floor
                    // somebody is trying to recognise.
                    PlanThumbnail(
                      plan: floor.plan,
                      size: width - AppDimens.space16,
                    ),
                    const SizedBox(height: AppDimens.space8),
                    Flexible(
                      child: Text(
                        floor.floorTitle,
                        style: theme.textTheme.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Flexible(
                      child: Text(
                        floor.buildingName,
                        style: theme.textTheme.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Acoustic room classification — the app's third sense, and until now the
/// only one with no way in.
///
/// It sat behind a card in Profile marked "(dev)", alongside the hardware
/// probes, despite being a headline capability in its own right: the phone
/// chirps, listens to how long the space rings, and names what kind of room
/// you are standing in. That is useful without a map of the building and
/// without sight, which is more than can be said for a developer shortcut.
class _ListenCard extends StatelessWidget {
  const _ListenCard();

  @override
  Widget build(BuildContext context) => _ActionTile(
    icon: PhosphorIconsFill.waveform,
    title: 'Identify this space',
    detail: 'Listen to how the room sounds',
    semanticLabel:
        'Identify this space. The phone listens to how the room echoes and '
        'names what kind of space you are in.',
    tinted: false,
    onTap: (context) => context.pushNamed(RouteNames.acoustic),
  );
}

/// One of Home's two secondary actions: a rounded square.
///
/// Shared so the pair cannot drift apart in padding, type or icon size — they
/// sit side by side, where any difference between them reads as a mistake.
class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.detail,
    required this.semanticLabel,
    required this.tinted,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String detail;
  final String semanticLabel;

  /// The mapping tile carries the accent, because contributing is the action
  /// the crowdsourced index depends on. Tinting both would spend the accent
  /// twice and emphasise neither.
  final bool tinted;
  final void Function(BuildContext context) onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final background = tinted
        ? (isDark
              ? AppColors.coral.withValues(alpha: 0.16)
              : AppColors.coralSoft)
        : theme.colorScheme.surface;
    // On the tinted tile in light mode the ground is a fixed coral wash, so the
    // ink is stated rather than inherited from a theme that assumes a white
    // page underneath.
    final foreground = tinted && !isDark
        ? AppColors.ink
        : theme.colorScheme.onSurface;

    return Semantics(
      button: true,
      label: semanticLabel,
      child: ExcludeSemantics(
        child: Material(
          color: background,
          borderRadius: BorderRadius.circular(AppDimens.radiusLg),
          child: InkWell(
            onTap: () => onTap(context),
            borderRadius: BorderRadius.circular(AppDimens.radiusLg),
            child: Padding(
              padding: const EdgeInsets.all(AppDimens.space16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 22, color: AppColors.coral),
                  // Pushes the words to the bottom of the square, so the two
                  // tiles' titles line up whatever length their copy is.
                  const Spacer(),
                  Flexible(
                    child: Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: foreground,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(height: AppDimens.space2),
                  Flexible(
                    child: Text(
                      detail,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: foreground.withValues(alpha: 0.7),
                      ),
                      // `Flexible` + `maxLines` rather than trusting the sum
                      // above: if the height is ever wrong the copy shortens
                      // instead of the tile overflowing.
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One recently mapped building, as a tile in the Home grid.
///
/// (This comment used to describe the AR scan card that stood here before the
/// capture path was removed — a card that promised walking rooms and tapping
/// their corners. Nothing on this widget ever did that.)
class _BuildingCard extends StatelessWidget {
  const _BuildingCard({
    required this.building,
    this.plan,
    required this.onChanged,
  });

  /// Reloads the grid after the card's own menu renames or removes this
  /// building.
  final VoidCallback onChanged;

  final Building building;

  /// A floor of this building traced onto this device. When there is one the
  /// card draws it — the actual shape of the place — instead of the stock
  /// glyph that stood in for every building alike.
  final RoomPlan? plan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Material(
      color: isDark ? AppColors.darkSurface : AppColors.white,
      borderRadius: BorderRadius.circular(AppDimens.radiusLg),
      child: InkWell(
        onTap: () => context.pushNamed(
          RouteNames.building,
          pathParameters: {'id': building.id},
          extra: building,
        ),
        borderRadius: BorderRadius.circular(AppDimens.radiusLg),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: theme.dividerColor),
            borderRadius: BorderRadius.circular(AppDimens.radiusLg),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.all(AppDimens.space8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(AppDimens.radiusMd),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (plan case final plan?)
                        // The floor itself. A card showing the real geometry
                        // is recognisable — somebody scanning Home knows the
                        // shape of the building they were in this morning —
                        // where the glyph was the same icon on every card.
                        Padding(
                          padding: const EdgeInsets.all(AppDimens.space8),
                          child: PlanThumbnail(
                            plan: plan,
                            size: double.infinity,
                          ),
                        )
                      else
                        Center(
                          child: Icon(
                            BuildingGlyph.iconFor(building.glyph),
                            size: 40,
                            color: theme.textTheme.bodyMedium?.color,
                          ),
                        ),
                      Positioned(
                        top: AppDimens.space8,
                        right: AppDimens.space8,
                        child: PercentBadge(building.mappedPercent),
                      ),
                      // Rename and remove, on the card itself.
                      //
                      // An explicit button rather than a long-press: this app
                      // is built for people who cannot see where they are
                      // aiming, and a gesture with no visible target is a
                      // feature they will never find. It sits over the plan
                      // rather than in the title row, where it would squeeze
                      // the building's name on a narrow phone.
                      Positioned(
                        bottom: 0,
                        left: 0,
                        child: IconButton(
                          tooltip: 'Options for ${building.name}',
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(
                            PhosphorIconsRegular.dotsThreeVertical,
                            size: 18,
                          ),
                          onPressed: () async {
                            final change = await showBuildingActions(
                              context,
                              building,
                            );
                            if (change != BuildingChange.none) onChanged();
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppDimens.space12,
                  AppDimens.space4,
                  AppDimens.space12,
                  AppDimens.space12,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(building.name, style: theme.textTheme.titleMedium),
                    const SizedBox(height: AppDimens.space2),
                    Text(
                      '${building.floorsCount} floors · ${building.mappers} mappers',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppDimens.space24),
      child: Column(
        children: [
          Text(message, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: AppDimens.space12),
          OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
