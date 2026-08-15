import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimens.dart';
import '../../../features/guidance/bloc/guidance_bloc.dart';
import '../../../features/guidance/guidance_session.dart';
import '../../../features/profile/profile_repository.dart';
import '../../../services/injection_container.dart';
import '../../../services/motion/stride_profile.dart';

/// Following a route by voice.
///
/// The screen is the secondary channel here — everything on it has already
/// been spoken, and a blind user never needs to look at it. It exists so a
/// sighted helper can see what the phone is doing, so the state is visible
/// when the speaker is muted, and so the two controls that need a finger —
/// "I'm at the sign" and "I'm lost" — are big enough to hit without looking.
class GuidancePage extends StatefulWidget {
  const GuidancePage({super.key, required this.session});

  final GuidanceSession session;

  @override
  State<GuidancePage> createState() => _GuidancePageState();
}

class _GuidancePageState extends State<GuidancePage> {
  late final Future<GuidanceSession> _prepared = _withStride();

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
    return FutureBuilder<GuidanceSession>(
      future: _prepared,
      builder: (context, snapshot) {
        final session = snapshot.data;
        if (session == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return BlocProvider(
          create: (_) => getIt<GuidanceBloc>()..add(GuidanceStarted(session)),
          child: const _GuidanceView(),
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
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _TopBar(
                  destination: session?.destinationName ?? 'Route',
                  voiceOn: state.voiceOn,
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppDimens.space16,
                    ),
                    child: state.status == GuidanceStatus.arrived
                        ? _Arrived(destination: session?.destinationName ?? '')
                        : _Walking(state: state),
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
  const _TopBar({required this.destination, required this.voiceOn});

  final String destination;
  final bool voiceOn;

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

class _Walking extends StatelessWidget {
  const _Walking({required this.state});

  final GuidanceState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = state.session;
    final leg = state.currentLeg;
    final nextName = leg == null ? '' : session?.nameOf(leg.toLandmarkId) ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
