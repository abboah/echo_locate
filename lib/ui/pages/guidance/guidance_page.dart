import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimens.dart';
import '../../../core/utils/logger.dart';
import '../../../features/guidance/bloc/ar_guidance_cubit.dart';
import '../../../features/guidance/bloc/guidance_bloc.dart';
import '../../../features/guidance/guidance_session.dart';
import '../../../features/profile/profile_repository.dart';
import '../../../services/injection_container.dart';
import '../../../services/motion/stride_profile.dart';
import '../../../services/sensing/detection_service.dart';
import '../../../services/vision/ar_guidance_service.dart';

/// Following a route by voice, and — where the phone can — by an arrow on the
/// floor.
///
/// The screen is the secondary channel here — everything on it has already
/// been spoken, and a blind user never needs to look at it. It exists so a
/// sighted helper can see what the phone is doing, so the state is visible
/// when the speaker is muted, and so the two controls that need a finger —
/// "I'm at the sign" and "I'm lost" — are big enough to hit without looking.
///
/// ## The AR view is a layer, not a second screen
///
/// Where ARCore is available the same route also draws itself into the world:
/// arrows along the floor toward the landmark at the end of the current leg.
/// It is the same [GuidanceBloc], the same session, the same voice and the
/// same two buttons — [ArGuidanceCubit] only mirrors the leg into the camera
/// view. On the uncertified hardware most of this app's users carry, none of it
/// starts and the screen is exactly what it always was.
class GuidancePage extends StatefulWidget {
  const GuidancePage({super.key, required this.session});

  final GuidanceSession session;

  @override
  State<GuidancePage> createState() => _GuidancePageState();
}

class _GuidancePageState extends State<GuidancePage>
    with WidgetsBindingObserver {
  /// Created here rather than in a `BlocProvider` factory because the AR
  /// session has to be running **before** guidance starts detection: ARCore
  /// holds the camera exclusively, so whichever opens it first wins, and the
  /// wrong order leaves the camera plugin holding it and ARCore unable to
  /// start. Both are closed in [dispose].
  late final GuidanceBloc _guidance = getIt<GuidanceBloc>();
  late final ArGuidanceCubit _ar = ArGuidanceCubit(
    getIt<ArGuidanceService>(),
    _guidance,
  );

  late final Future<void> _booted = _boot();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_ar.close());
    unawaited(_guidance.close());
    super.dispose();
  }

  /// **Not optional.** `MainActivity.onPause` tears the ARCore session down
  /// natively whether Dart asks or not, so without this the screen comes back
  /// rendering a `Texture` pointing at a released id — a blank rectangle where
  /// the camera was, no crash, nothing in the log. The route itself is
  /// untouched: only the arrows go.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      // `hidden` is the one that arrives first on a modern Android when the app
      // goes away, and leaving it out means the camera is held for the moment
      // before `paused` — long enough for another app opening the camera to
      // find it taken.
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        unawaited(_ar.stop());
      case AppLifecycleState.resumed:
        if (mounted) unawaited(_resume());
      case AppLifecycleState.detached:
        break;
    }
  }

  /// Brings the screen up: the user's stride, then the AR layer, then the route.
  ///
  /// **The route starts whatever the AR layer does.** Guidance works with no
  /// camera and no ARCore, which is how most of this app's users walk, so
  /// anything thrown on the way up is logged and stepped over rather than
  /// allowed to take the walk with it. Without the catch, one unexpected
  /// exception here is a permanent spinner where a working route should be.
  Future<void> _boot() async {
    final session = await _withStride();
    if (!mounted) return;
    try {
      await _startAr();
    } catch (e, stack) {
      AppLogger.error('AR guidance failed to start: $e', e, stack);
    }
    if (!mounted) return;
    _guidance.add(GuidanceStarted(session));
  }

  /// Coming back to the screen: the arrows, and then the senses they carry.
  Future<void> _resume() async {
    await _startAr();
    if (!mounted) return;
    await _ensureSensing();
  }

  /// Puts obstacle detection back on a camera it can actually have.
  ///
  /// **This is the failure that matters most and shows least.** While the AR
  /// session runs, its frames are the *only* thing feeding ML Kit — the camera
  /// plugin cannot be opened alongside ARCore. So if the session does not come
  /// back after a resume, because another app took the camera or ARCore is
  /// updating itself, obstacle callouts and sign reading stop dead and nothing
  /// says so: the route keeps counting steps, the screen keeps giving
  /// directions, and a blind user simply stops being told about the trolley in
  /// the corridor for the rest of the walk.
  ///
  /// With ARCore gone the camera is free, so the plugin can have it back. It
  /// then keeps it — a later resume will not get the arrows back, because the
  /// plugin is holding the camera ARCore would need. That is the right way
  /// round: this app is an accessibility aid before it is an AR demo.
  Future<void> _ensureSensing() async {
    // Never while the app is away. The commonest reason the AR frames stop is
    // that the phone went in a pocket, and opening a camera in the background
    // fails on some devices and throws on others.
    final phase = WidgetsBinding.instance.lifecycleState;
    if (phase != null && phase != AppLifecycleState.resumed) return;

    final detection = getIt<DetectionService>();
    // The AR session is up, so its frames are feeding ML Kit.
    if (_ar.state.running) return;
    // Detection already has its own camera.
    if (detection.camera != null) return;
    // What is left is detection with no source at all: stranded on AR frames
    // that have stopped arriving, or stopped outright because [_startAr] took
    // the camera for a session that then failed to come up. Both are silent,
    // and both mean a blind walker stops being told about the trolley in the
    // corridor for the rest of the walk.

    AppLogger.warn('AR frames gone — moving detection back to the camera');
    await detection.stop();
    final restarted = await detection.start();
    if (!restarted) {
      AppLogger.warn('Camera unavailable — guidance continues on steps alone');
    }
  }

  /// Brings the AR session up, if this phone has one.
  ///
  /// The window's size is used rather than the view's: the AR area has not been
  /// laid out yet at this point, and the first `LayoutBuilder` pass corrects it
  /// through `setViewport` — which is also what handles rotation later.
  ///
  /// **Bounded, because guidance waits on it.** The route is started after this
  /// returns, so an ARCore install that hangs — a device checking availability
  /// against a Play Services that is updating itself, a camera another app has
  /// not let go of — would otherwise leave the walker on a spinner instead of
  /// on the perfectly good voice guidance that needs none of this.
  Future<void> _startAr() async {
    // The camera plugin may already have the camera — detection fell back to
    // it, or the Detect environment screen was visited on the way here — and
    // ARCore cannot share.
    //
    // **This used to give up here**, on the reasoning that obstacle callouts
    // matter more than arrows. That reasoning was wrong about the facts: an AR
    // session feeds ML Kit from its own frames (`setAnalysis`), so taking the
    // camera for ARCore costs sensing nothing, and refusing to take it cost
    // the arrows entirely — silently, on a phone that had visited one earlier
    // screen. If the session then fails to start, `DetectionService.start`
    // finds the camera free and opens it, which is where the fallback belongs.
    final detection = getIt<DetectionService>();
    if (detection.camera != null) {
      AppLogger.info('Taking the camera back from detection for the AR view');
      await detection.stop();
    }

    try {
      final supported = await _ar.checkAvailability().timeout(
        const Duration(seconds: 4),
      );
      if (!supported || !mounted) return;
      final size = View.of(context).physicalSize;
      await _ar
          .start(
            viewWidth: size.width.round(),
            viewHeight: size.height.round(),
          )
          .timeout(const Duration(seconds: 8));
    } on TimeoutException {
      AppLogger.warn('AR guidance took too long to start — walking without it');
    }
  }


  /// Loads the user's own step length before guidance quotes any counts.
  ///
  /// Routes store metres; this is where they become *this* user's steps. An
  /// uncalibrated user gets the anthropometric fallback rather than a blocked
  /// screen — a slightly wrong count still beats no directions, and every
  /// landmark resets the error anyway.
  Future<GuidanceSession> _withStride() async {
    try {
      final profile = await getIt<ProfileRepository>().currentProfile();
      final metres = profile.strideLengthM;
      if (metres != null) {
        final stride = StrideProfile(
          metres: metres,
          source: StrideSource.calibrated,
        );
        if (stride.isPlausible) {
          return widget.session.copyWith(stride: stride);
        }
      }
    } catch (_) {
      // Offline or signed out: the fallback stride is still a walkable route.
    }
    return widget.session;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _booted,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return MultiBlocProvider(
          providers: [
            BlocProvider<GuidanceBloc>.value(value: _guidance),
            BlocProvider<ArGuidanceCubit>.value(value: _ar),
          ],
          // The session can end without anybody asking — the camera taken by a
          // call, ARCore giving up — and when it does, the frames feeding
          // obstacle detection and sign reading stop with it.
          child: BlocListener<ArGuidanceCubit, ArGuidanceState>(
            listenWhen: (before, after) => before.running && !after.running,
            listener: (_, _) => unawaited(_ensureSensing()),
            child: const _GuidanceView(),
          ),
        );
      },
    );
  }
}

class _GuidanceView extends StatelessWidget {
  const _GuidanceView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: BlocBuilder<GuidanceBloc, GuidanceState>(
          builder: (context, state) {
            final session = state.session;
            final ar = context.watch<ArGuidanceCubit>().state;
            // The camera is shown only while there is a walk to point along.
            // On arrival the destination's name matters and the corridor behind
            // it does not.
            final showCamera =
                ar.running &&
                ar.cameraVisible &&
                ar.textureId != null &&
                state.status != GuidanceStatus.arrived;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _TopBar(
                  destination: session?.destinationName ?? 'Route',
                  voiceOn: state.voiceOn,
                  arRunning: ar.running,
                  cameraVisible: ar.cameraVisible,
                ),
                Expanded(
                  // Double-tapping anywhere confirms the landmark, which is
                  // the same thing the button below does. The button is a
                  // target you have to find on a screen you may not be able to
                  // see, held at chest height, while standing at a door — and
                  // the moment guidance most needs an answer is exactly that
                  // one. The whole view is a bigger target.
                  //
                  // Not a replacement for the button: with a screen reader
                  // running, a double tap belongs to the reader and never
                  // reaches this, so the labelled button stays the way in.
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onDoubleTap: state.status == GuidanceStatus.arrived
                        ? null
                        : () => context.read<GuidanceBloc>().add(
                            const GuidanceLandmarkConfirmed(),
                          ),
                    child: showCamera
                        ? _ArView(state: state, ar: ar)
                        : Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppDimens.space16,
                            ),
                            child: state.status == GuidanceStatus.arrived
                                ? _Arrived(
                                    destination: session?.destinationName ?? '',
                                  )
                                : _Walking(state: state, ar: ar),
                          ),
                  ),
                ),
                if (state.status != GuidanceStatus.arrived)
                  _Controls(state: state),
                const SizedBox(height: AppDimens.space8),
              ],
            );
          },
        ),
      ),
      backgroundColor: theme.scaffoldBackgroundColor,
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.destination,
    required this.voiceOn,
    this.arRunning = false,
    this.cameraVisible = true,
  });

  final String destination;
  final bool voiceOn;
  final bool arRunning;
  final bool cameraVisible;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(AppDimens.space12),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(PhosphorIconsRegular.x),
            tooltip: 'End guidance',
            onPressed: () => context.pop(),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Walking to', style: theme.textTheme.labelSmall),
                Text(destination, style: theme.textTheme.titleMedium),
              ],
            ),
          ),
          if (arRunning)
            IconButton(
              tooltip: cameraVisible ? 'Hide the camera' : 'Show the camera',
              icon: Icon(
                cameraVisible
                    ? PhosphorIconsFill.eye
                    : PhosphorIconsFill.eyeSlash,
                color: cameraVisible ? AppColors.coral : null,
              ),
              // The session keeps running either way — it is still feeding sign
              // reading — so this is instant and costs nothing to change your
              // mind about. Somebody who wants the big text back, or who is
              // handing the phone to a blind companion, should not have to
              // wait for tracking to come round again.
              onPressed: () => context.read<ArGuidanceCubit>().setCameraVisible(
                visible: !cameraVisible,
              ),
            ),
          IconButton(
            tooltip: voiceOn ? 'Mute voice' : 'Unmute voice',
            icon: Icon(
              voiceOn
                  ? PhosphorIconsFill.speakerHigh
                  : PhosphorIconsFill.speakerSlash,
              color: voiceOn ? AppColors.coral : null,
            ),
            onPressed: () =>
                context.read<GuidanceBloc>().add(const GuidanceVoiceToggled()),
          ),
        ],
      ),
    );
  }
}

/// The camera, with the route drawn into it.
///
/// **The arrow is not in this widget.** It is drawn natively, into the same
/// buffer as the camera image, from the same frame's matrices — see
/// `ArrowRenderer`. Painting it here from a projected position would put it
/// over whichever camera frame the compositor had by then, so it would lag the
/// room exactly while the phone is moving, which is all of the time somebody is
/// walking.
///
/// What is here is everything that belongs to the *screen* rather than to the
/// room: the instruction, the distance left, and whatever the AR layer has to
/// say. Each of those sits on its own translucent card rather than on a scrim
/// over the whole view — the middle of the screen belongs to the arrow and to
/// the corridor behind it, and darkening the corridor to make room for text
/// that is not there is how an AR view ends up murkier than the camera.
class _ArView extends StatelessWidget {
  const _ArView({required this.state, required this.ar});

  final GuidanceState state;
  final ArGuidanceState ar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        // Device pixels, and reported on every layout pass: ARCore is told the
        // view it is drawing into, and a stale one puts the arrows in the wrong
        // part of the screen after a rotation.
        final ratio = MediaQuery.devicePixelRatioOf(context);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!context.mounted) return;
          context.read<ArGuidanceCubit>().setViewport(
            viewWidth: (constraints.maxWidth * ratio).round(),
            viewHeight: (constraints.maxHeight * ratio).round(),
          );
        });

        return Stack(
          fit: StackFit.expand,
          children: [
            // Labelled rather than left silent: a screen reader user has no
            // other way to know the camera is on, and it is the only thing that
            // explains the eye button in the bar above.
            Semantics(
              image: true,
              label: 'Camera view, with the way ahead drawn on the floor',
              child: Texture(textureId: ar.textureId!),
            ),
            Positioned(
              left: AppDimens.space16,
              right: AppDimens.space16,
              top: AppDimens.space12,
              child: _ArCard(
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    state.instruction,
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: AppDimens.space16,
              right: AppDimens.space16,
              bottom: AppDimens.space12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Without this the camera view of a lost walker is the last
                  // leg's instruction over a corridor with no arrows in it —
                  // indistinguishable from guidance having quietly died. Same
                  // wording as the plain view, because it is the same advice.
                  if (state.status == GuidanceStatus.recovering)
                    _Banner(
                      icon: state.askForHelp
                          ? PhosphorIconsFill.handWaving
                          : PhosphorIconsFill.magnifyingGlass,
                      text: state.askForHelp
                          ? 'Ask someone nearby for '
                                '${state.session?.destinationName ?? 'your destination'}.'
                          : 'Sweep the phone slowly left to right to find a sign.',
                    ),
                  if (state.callout != null)
                    _Banner(
                      icon: PhosphorIconsFill.warning,
                      text: state.callout!.spoken,
                      urgent: state.callout!.urgent,
                    ),
                  Row(
                    children: [
                      if (ar.remainingLabel != null)
                        _ArChip(
                          icon: PhosphorIconsFill.mapPin,
                          text: ar.remainingLabel!,
                          semanticsLabel: ar.remainingSpoken,
                        ),
                      if (ar.hint != null)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(
                              left: AppDimens.space8,
                            ),
                            // Announced, because nothing else announces it: the
                            // app's own voice speaks the route and the
                            // obstacles, but never this line, so without a live
                            // region "walk a few steps so the arrow can line
                            // up" only ever reaches someone who can read it.
                            child: Semantics(
                              liveRegion: true,
                              child: _ArCard(
                                child: Text(
                                  ar.hint!,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// A translucent dark card, so a line of white text stays readable over a
/// corridor that might be any colour at all.
///
/// This replaced a top-to-bottom scrim over the whole camera view. The scrim
/// darkened the corridor even where nothing was written, which on a phone held
/// at walking height is most of the screen and all of the part the walker is
/// actually trying to see. A card only darkens what it has to.
class _ArCard extends StatelessWidget {
  const _ArCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      // Dark enough for white text against a sunlit window at the end of a
      // corridor, which is the worst case and a common one.
      color: Colors.black.withValues(alpha: 0.62),
      borderRadius: BorderRadius.circular(AppDimens.radiusLg),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.space16,
        vertical: AppDimens.space12,
      ),
      child: child,
    ),
  );
}

class _ArChip extends StatelessWidget {
  const _ArChip({required this.icon, required this.text, this.semanticsLabel});

  final IconData icon;
  final String text;

  /// What a screen reader says instead of [text], which is abbreviated.
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: AppColors.coral,
      borderRadius: BorderRadius.circular(AppDimens.radiusPill),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.space12,
        vertical: AppDimens.space8,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: Colors.white),
          const SizedBox(width: AppDimens.space8),
          Text(
            text,
            semanticsLabel: semanticsLabel,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    ),
  );
}

class _Walking extends StatelessWidget {
  const _Walking({required this.state, this.ar});

  final GuidanceState state;

  /// The AR layer's state, so this view can say why it is *this* view.
  final ArGuidanceState? ar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = state.session;
    final leg = state.currentLeg;
    final nextName = leg == null ? '' : session?.nameOf(leg.toLandmarkId) ?? '';
    final noCamera = ar?.cameraReason;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // **Why the camera is not on.** Every reason the AR view fails to come
        // up used to leave this screen looking exactly like a phone that had
        // never supported it: correct directions, no camera, nothing said. Two
        // of those reasons are one tap from being fixed and a third is a stale
        // permission, so the screen names them rather than absorbing them.
        if (noCamera != null)
          Padding(
            padding: const EdgeInsets.only(top: AppDimens.space8),
            child: Text(
              noCamera,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.warning,
              ),
            ),
          ),
        if (state.status == GuidanceStatus.recovering)
          _Banner(
            icon: state.askForHelp
                ? PhosphorIconsFill.handWaving
                : PhosphorIconsFill.magnifyingGlass,
            text: state.askForHelp
                ? 'Ask someone nearby for '
                      '${session?.destinationName ?? 'your destination'}.'
                : 'Sweep the phone slowly left to right to find a sign.',
          ),
        const SizedBox(height: AppDimens.space16),
        Semantics(
          // Announced by TalkBack whenever the instruction changes, so the
          // screen reader and the app's own voice say the same thing.
          liveRegion: true,
          child: Text(state.instruction, style: theme.textTheme.headlineSmall),
        ),
        const SizedBox(height: AppDimens.space24),
        if (state.expectedSteps > 0) ...[
          Text(
            '${state.stepsThisLeg} of about ${state.expectedSteps} steps',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: AppDimens.space8),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppDimens.radiusPill),
            child: LinearProgressIndicator(
              value: state.legProgress,
              minHeight: 8,
              backgroundColor: theme.colorScheme.surface,
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.coral),
            ),
          ),
        ] else
          Text(
            state.stepCounting
                ? 'This leg is guided by its sign.'
                : 'No step counter on this phone — watch for the sign.',
            style: theme.textTheme.bodyMedium,
          ),
        const SizedBox(height: AppDimens.space16),
        if (nextName.isNotEmpty)
          Row(
            children: [
              const Icon(
                PhosphorIconsFill.signpost,
                size: 18,
                color: AppColors.coral,
              ),
              const SizedBox(width: AppDimens.space8),
              Expanded(
                child: Text(
                  'Looking for: $nextName',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        const Spacer(),
        if (state.callout != null)
          _Banner(
            icon: PhosphorIconsFill.warning,
            text: state.callout!.spoken,
            urgent: state.callout!.urgent,
          ),
        Text(
          'Leg ${state.legIndex + 1} of ${state.plan.legs.length}',
          style: theme.textTheme.labelSmall,
        ),
      ],
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({required this.state});

  final GuidanceState state;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppDimens.space16),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 64,
              child: ElevatedButton.icon(
                onPressed: () => context.read<GuidanceBloc>().add(
                  const GuidanceLandmarkConfirmed(),
                ),
                icon: const Icon(PhosphorIconsFill.check),
                label: const Text("I'm at the sign"),
              ),
            ),
          ),
          const SizedBox(width: AppDimens.space12),
          Expanded(
            child: SizedBox(
              height: 64,
              child: OutlinedButton.icon(
                onPressed: () => context.read<GuidanceBloc>().add(
                  const GuidanceLostReported(),
                ),
                icon: const Icon(PhosphorIconsRegular.question),
                label: const Text("I'm lost"),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Arrived extends StatelessWidget {
  const _Arrived({required this.destination});

  final String destination;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            PhosphorIconsFill.checkCircle,
            size: 64,
            color: AppColors.coral,
          ),
          const SizedBox(height: AppDimens.space16),
          Semantics(
            liveRegion: true,
            child: Text(
              'You have arrived at $destination.',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge,
            ),
          ),
          const SizedBox(height: AppDimens.space24),
          ElevatedButton(
            onPressed: () => context.pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.text, this.urgent = false});

  final IconData icon;
  final String text;
  final bool urgent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final tint = urgent ? AppColors.error : AppColors.coral;

    return Container(
      margin: const EdgeInsets.only(bottom: AppDimens.space12),
      padding: const EdgeInsets.all(AppDimens.space12),
      decoration: BoxDecoration(
        color: isDark
            ? tint.withValues(alpha: 0.16)
            : (urgent ? AppColors.errorSoft : AppColors.coralSoft),
        borderRadius: BorderRadius.circular(AppDimens.radiusLg),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: tint),
          const SizedBox(width: AppDimens.space12),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
