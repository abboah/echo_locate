import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimens.dart';
import '../../../features/sonar/bloc/sonar_bloc.dart';
import '../../../services/injection_container.dart';
import '../../widgets/radar_painter.dart';

/// Sonar — single-shot acoustic distance measurement + radar view.
///
/// Kept as a standalone feature per the build plan: phone speaker/mic
/// ranging is unreliable, so this is presented as a "lite" demo, not a
/// primary sensing mode (that's the camera, in Assist Mode/Scan).
class SonarPage extends StatelessWidget {
  const SonarPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<SonarBloc>()..add(const SonarStarted()),
      child: const _SonarView(),
    );
  }
}

class _SonarView extends StatelessWidget {
  const _SonarView();

  @override
  Widget build(BuildContext context) {
    const viewportColor = Color(0xFF161514);

    return Scaffold(
      backgroundColor: viewportColor,
      body: BlocBuilder<SonarBloc, SonarState>(
        builder: (context, state) {
          return Column(
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(AppDimens.space32),
                      child: RadarView(
                        headingDegrees: state.headingDegrees,
                        distanceMeters: state.lastMeasurement?.distanceMeters,
                      ),
                    ),
                    SafeArea(
                      bottom: false,
                      child: Stack(
                        children: [
                          Positioned(
                            left: AppDimens.space16,
                            top: AppDimens.space12,
                            child: Material(
                              color: Colors.black.withValues(alpha: 0.35),
                              shape: const CircleBorder(),
                              child: InkWell(
                                onTap: () => context.pop(),
                                customBorder: const CircleBorder(),
                                child: const SizedBox(
                                  width: 42,
                                  height: 42,
                                  child: Icon(PhosphorIconsRegular.x,
                                      color: Colors.white, size: 20),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            top: AppDimens.space20,
                            left: 0,
                            right: 0,
                            child: Center(child: _StatusPill(state: state)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              _SonarSheet(state: state),
            ],
          );
        },
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.state});

  final SonarState state;

  @override
  Widget build(BuildContext context) {
    final label = switch (state.status) {
      SonarStatus.starting => 'Starting…',
      SonarStatus.unavailable => 'Mic unavailable',
      SonarStatus.idle => state.isCalibrated ? 'Ready' : 'Calibration needed',
      SonarStatus.measuring => 'Measuring…',
      SonarStatus.calibrating => 'Calibrating…',
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.space12,
        vertical: AppDimens.space8,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(AppDimens.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: switch (state.status) {
                SonarStatus.measuring ||
                SonarStatus.calibrating =>
                  AppColors.coral,
                _ => Colors.white54,
              },
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: AppDimens.space8),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _SonarSheet extends StatelessWidget {
  const _SonarSheet({required this.state});

  final SonarState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final measurement = state.lastMeasurement;
    final canMeasure = state.status == SonarStatus.idle;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkElevated : AppColors.white,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppDimens.radiusXl),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(
        AppDimens.space16,
        AppDimens.space12,
        AppDimens.space16,
        AppDimens.space16,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: theme.dividerColor,
                borderRadius: BorderRadius.circular(AppDimens.radiusPill),
              ),
            ),
            const SizedBox(height: AppDimens.space16),
            Semantics(
              liveRegion: true,
              child: Text(
                measurement == null
                    ? 'No reading yet'
                    : '${measurement.distanceMeters.toStringAsFixed(2)} m',
                style: theme.textTheme.headlineMedium,
              ),
            ),
            if (measurement != null) ...[
              const SizedBox(height: AppDimens.space4),
              Text(
                // Calibration readout: how far the correlation peak stood
                // above the noise floor, for tuning ToFCalculator's gate.
                'confidence ${measurement.peakToNoiseRatio.toStringAsFixed(1)}x',
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (state.error != null) ...[
              const SizedBox(height: AppDimens.space4),
              Text(
                state.error!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: AppColors.error),
              ),
            ],
            if (!state.isCalibrated) ...[
              const SizedBox(height: AppDimens.space8),
              Text(
                'Calibrate first: hold the phone away from surfaces and turn '
                'it slowly while it sweeps. This learns the speaker’s own '
                'echo so close objects can be seen.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: AppDimens.space16),
            // Both buttons must be Expanded: the app theme gives buttons
            // minimumSize Size.fromHeight(54), i.e. an infinite minimum
            // width. A Row hands children unbounded width, so that infinity
            // survives instead of being clamped the way it is in a Column,
            // and layout throws.
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: canMeasure
                        ? () => context
                            .read<SonarBloc>()
                            .add(const SonarCalibrateRequested())
                        : null,
                    icon: const Icon(PhosphorIconsRegular.crosshair, size: 20),
                    label: Text(
                      state.status == SonarStatus.calibrating
                          ? 'Calibrating…'
                          : state.isCalibrated
                              ? 'Recalibrate'
                              : 'Calibrate',
                    ),
                  ),
                ),
                const SizedBox(width: AppDimens.space12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: canMeasure
                        ? () => context
                            .read<SonarBloc>()
                            .add(const SonarMeasureRequested())
                        : null,
                    icon: const Icon(PhosphorIconsFill.broadcast, size: 20),
                    label: Text(
                      state.status == SonarStatus.measuring
                          ? 'Measuring…'
                          : 'Ping',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
