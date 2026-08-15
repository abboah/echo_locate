import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimens.dart';
import '../../../features/assist/bloc/assist_bloc.dart';
import '../../../services/injection_container.dart';
import '../../../services/sensing/detection_service.dart';

/// Assist Mode — the headline experience: obstacle alerts + voice guidance
/// while the user moves.
///
/// Live mode shows the camera feed with real ML Kit detections spoken via
/// TTS. When no camera is available (emulator, permission denied) the Bloc
/// falls back to a scripted demo loop over the dark viewport.
class AssistPage extends StatelessWidget {
  const AssistPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<AssistBloc>()..add(const AssistStarted()),
      child: const _AssistView(),
    );
  }
}

class _AssistView extends StatefulWidget {
  const _AssistView();

  @override
  State<_AssistView> createState() => _AssistViewState();
}

class _AssistViewState extends State<_AssistView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  )..repeat();

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  static IconData _iconFor(String label) => switch (label) {
    'furniture' => PhosphorIconsFill.armchair,
    'doorway' => PhosphorIconsFill.door,
    'plant' => PhosphorIconsFill.plant,
    'clothing item' => PhosphorIconsFill.tShirt,
    'food item' => PhosphorIconsFill.forkKnife,
    'path' => PhosphorIconsFill.arrowBendUpRight,
    'sign' => PhosphorIconsFill.textT,
    _ => PhosphorIconsFill.warningCircle,
  };

  @override
  Widget build(BuildContext context) {
    const viewportColor = Color(0xFF161514);

    return Scaffold(
      backgroundColor: viewportColor,
      body: BlocBuilder<AssistBloc, AssistState>(
        builder: (context, state) {
          final callout = state.callout;

          return Column(
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Viewport: live camera feed, or pulsing glyph while
                    // starting / in demo mode.
                    if (state.status == AssistStatus.live)
                      const _CameraViewport()
                    else
                      Center(
                        child: AnimatedBuilder(
                          animation: _pulse,
                          builder: (context, _) => CustomPaint(
                            size: const Size(260, 260),
                            painter: _PulsePainter(t: _pulse.value),
                            child: const SizedBox(
                              width: 260,
                              height: 260,
                              child: Center(
                                child: Icon(
                                  PhosphorIconsFill.eye,
                                  color: Colors.white,
                                  size: 52,
                                ),
                              ),
                            ),
                          ),
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
                                  child: Icon(
                                    PhosphorIconsRegular.x,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            top: AppDimens.space20,
                            left: 0,
                            right: 0,
                            child: Center(
                              child: _StatusPill(status: state.status),
                            ),
                          ),
                          // Latest callout card.
                          Positioned(
                            left: AppDimens.space16,
                            right: AppDimens.space16,
                            bottom: AppDimens.space20,
                            child: Semantics(
                              liveRegion: true,
                              child: Container(
                                padding: const EdgeInsets.all(
                                  AppDimens.space16,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.45),
                                  borderRadius: BorderRadius.circular(
                                    AppDimens.radiusLg,
                                  ),
                                ),
                                child: callout == null
                                    ? const Text(
                                        'Looking around you…',
                                        style: TextStyle(
                                          color: Colors.white70,
                                          fontSize: 15,
                                        ),
                                      )
                                    : Row(
                                        children: [
                                          Container(
                                            width: 44,
                                            height: 44,
                                            decoration: BoxDecoration(
                                              color: callout.urgent
                                                  ? AppColors.error
                                                  : AppColors.coral,
                                              shape: BoxShape.circle,
                                            ),
                                            child: Icon(
                                              _iconFor(callout.label),
                                              color: Colors.white,
                                              size: 22,
                                            ),
                                          ),
                                          const SizedBox(
                                            width: AppDimens.space12,
                                          ),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  callout.title,
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 17,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                                Text(
                                                  callout.detail,
                                                  style: const TextStyle(
                                                    color: Colors.white70,
                                                    fontSize: 14,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              _AssistSheet(
                voiceOn: state.voiceOn,
                onVoiceToggle: () =>
                    context.read<AssistBloc>().add(const AssistVoiceToggled()),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Full-bleed camera preview (cover-fit, portrait-corrected).
class _CameraViewport extends StatelessWidget {
  const _CameraViewport();

  @override
  Widget build(BuildContext context) {
    final controller = getIt<DetectionService>().camera;
    if (controller == null || !controller.value.isInitialized) {
      return const ColoredBox(color: Color(0xFF161514));
    }
    final preview = controller.value.previewSize!;
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          // Preview size is landscape; swap for portrait rendering.
          width: preview.height,
          height: preview.width,
          child: CameraPreview(controller),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});

  final AssistStatus status;

  @override
  Widget build(BuildContext context) {
    final label = switch (status) {
      AssistStatus.starting => 'Starting…',
      AssistStatus.live => 'Assisting',
      AssistStatus.demo => 'Demo — no camera',
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
              color: status == AssistStatus.live
                  ? AppColors.coral
                  : Colors.white54,
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

class _PulsePainter extends CustomPainter {
  _PulsePainter({required this.t});

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    for (var i = 0; i < 3; i++) {
      final progress = (t + i / 3) % 1.0;
      final radius = 40 + progress * (size.width / 2 - 40);
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.22 * (1 - progress))
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PulsePainter old) => old.t != t;
}

class _AssistSheet extends StatelessWidget {
  const _AssistSheet({required this.voiceOn, required this.onVoiceToggle});

  final bool voiceOn;
  final VoidCallback onVoiceToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

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
            Row(
              children: [
                const _AssistChip(
                  icon: PhosphorIconsFill.personSimpleWalk,
                  label: 'Obstacles',
                  value: 'On',
                ),
                const SizedBox(width: AppDimens.space8),
                const _AssistChip(
                  icon: PhosphorIconsFill.textT,
                  label: 'Read signs',
                  value: 'Soon',
                ),
                const SizedBox(width: AppDimens.space8),
                Expanded(
                  child: Semantics(
                    button: true,
                    label: voiceOn ? 'Mute voice' : 'Unmute voice',
                    child: Material(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(AppDimens.radiusMd),
                      child: InkWell(
                        onTap: onVoiceToggle,
                        borderRadius: BorderRadius.circular(AppDimens.radiusMd),
                        child: Padding(
                          padding: const EdgeInsets.all(AppDimens.space12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Voice', style: theme.textTheme.labelSmall),
                              const SizedBox(height: AppDimens.space2),
                              Row(
                                children: [
                                  Icon(
                                    voiceOn
                                        ? PhosphorIconsFill.speakerHigh
                                        : PhosphorIconsFill.speakerSlash,
                                    size: 16,
                                    color: voiceOn
                                        ? AppColors.coral
                                        : theme.textTheme.bodyMedium?.color,
                                  ),
                                  const SizedBox(width: AppDimens.space4),
                                  Text(
                                    voiceOn ? 'On' : 'Off',
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(
                                          color: voiceOn
                                              ? AppColors.coral
                                              : null,
                                        ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppDimens.space16),
            ElevatedButton.icon(
              onPressed: () => context.pop(),
              icon: const Icon(PhosphorIconsFill.handPalm, size: 20),
              label: const Text('End assistance'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AssistChip extends StatelessWidget {
  const _AssistChip({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(AppDimens.space12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(AppDimens.radiusMd),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.textTheme.labelSmall),
            const SizedBox(height: AppDimens.space2),
            Row(
              children: [
                Icon(icon, size: 16, color: theme.textTheme.bodyMedium?.color),
                const SizedBox(width: AppDimens.space4),
                Text(value, style: theme.textTheme.titleMedium),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
