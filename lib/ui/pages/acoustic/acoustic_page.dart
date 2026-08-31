import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimens.dart';
import '../../../features/acoustic/bloc/acoustic_bloc.dart';
import '../../../services/acoustic/room_classification.dart';
import '../../../services/injection_container.dart';
import '../../widgets/responsive.dart';

/// Acoustic room classification — names the surrounding space from how long
/// it rings (M5).
///
/// Presents the reverberation figures alongside the verdict rather than just
/// the label: they are the evidence, they explain an `unknown`, and they are
/// what the evaluation chapter reports.
class AcousticPage extends StatelessWidget {
  const AcousticPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<AcousticBloc>()..add(const AcousticStarted()),
      child: const _AcousticView(),
    );
  }
}

class _AcousticView extends StatelessWidget {
  const _AcousticView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(PhosphorIconsRegular.x),
          onPressed: () => context.pop(),
        ),
        title: const Text('Room acoustics'),
      ),
      body: BlocBuilder<AcousticBloc, AcousticState>(
        builder: (context, state) {
          final canMeasure = state.status == AcousticStatus.idle;
          final classification = state.lastClassification;

          return SafeArea(
            child: Padding(
              padding: Responsive.pagePadding(context),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Center(
                      child: switch (state.status) {
                        AcousticStatus.starting =>
                          const CircularProgressIndicator(),
                        AcousticStatus.unavailable => Text(
                          'Microphone unavailable',
                          style: theme.textTheme.bodyLarge,
                        ),
                        AcousticStatus.listening => const _Listening(),
                        AcousticStatus.idle =>
                          classification == null
                              ? Text(
                                  'Listen to identify the space around you.',
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodyLarge,
                                )
                              : _Result(classification: classification),
                      },
                    ),
                  ),
                  if (state.error != null &&
                      state.status == AcousticStatus.idle) ...[
                    Text(
                      state.error!,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.error,
                      ),
                    ),
                    const SizedBox(height: AppDimens.space12),
                  ],
                  ElevatedButton.icon(
                    onPressed: canMeasure
                        ? () => context.read<AcousticBloc>().add(
                            const AcousticMeasureRequested(),
                          )
                        : null,
                    icon: const Icon(PhosphorIconsFill.waveform, size: 20),
                    label: Text(
                      state.status == AcousticStatus.listening
                          ? 'Listening…'
                          : 'Identify space',
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Listening extends StatelessWidget {
  const _Listening();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: AppDimens.space16),
        Text('Listening to the room…', style: theme.textTheme.bodyLarge),
        const SizedBox(height: AppDimens.space4),
        Text('Hold still and stay quiet', style: theme.textTheme.bodySmall),
      ],
    );
  }
}

class _Result extends StatelessWidget {
  const _Result({required this.classification});

  final RoomClassification classification;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final features = classification.features;

    final label = switch (classification.type) {
      RoomType.corridor => 'Corridor',
      RoomType.smallRoom => 'Small room',
      RoomType.hall => 'Hall',
      RoomType.unknown => 'Unknown space',
    };
    final icon = switch (classification.type) {
      RoomType.corridor => PhosphorIconsRegular.arrowsOutLineHorizontal,
      RoomType.smallRoom => PhosphorIconsRegular.door,
      RoomType.hall => PhosphorIconsRegular.buildings,
      RoomType.unknown => PhosphorIconsRegular.question,
    };

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 56, color: AppColors.coral),
        const SizedBox(height: AppDimens.space12),
        Semantics(
          liveRegion: true,
          child: Text(label, style: theme.textTheme.headlineMedium),
        ),
        if (classification.type != RoomType.unknown) ...[
          const SizedBox(height: AppDimens.space4),
          Text(
            'confidence ${(classification.confidence * 100).round()}%',
            style: theme.textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: AppDimens.space16),
        Text(
          classification.reason,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall,
        ),
        if (features != null) ...[
          const SizedBox(height: AppDimens.space16),
          // The measurement itself. Shown because it is the evidence behind
          // the label, and because these are the numbers the evaluation
          // reports — a reader should not have to trust the verdict alone.
          Wrap(
            spacing: AppDimens.space16,
            runSpacing: AppDimens.space8,
            alignment: WrapAlignment.center,
            children: [
              _Metric(
                label: 'RT60',
                value: '${features.rt60Seconds.toStringAsFixed(2)} s',
              ),
              _Metric(
                label: 'EDT',
                value: '${features.earlyDecayTimeSeconds.toStringAsFixed(2)} s',
              ),
              _Metric(
                label: 'fit',
                value: features.fitQuality.toStringAsFixed(2),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value, style: theme.textTheme.titleMedium),
        Text(label, style: theme.textTheme.bodySmall),
      ],
    );
  }
}
