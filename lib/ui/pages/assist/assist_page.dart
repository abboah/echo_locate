import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimens.dart';

/// Assist Mode — the headline experience: obstacle alerts + voice guidance
/// while the user moves.
///
/// Phase 1: dark placeholder viewport with mock callouts cycling on a timer
/// and spoken via TTS, so the voice delivery is testable end-to-end today.
/// The camera + ML Kit detection stream replaces [_mockCallouts] in the
/// Phase 1 sensing step — this layout and the TTS path stay.
class AssistPage extends StatefulWidget {
  const AssistPage({super.key});

  @override
  State<AssistPage> createState() => _AssistPageState();
}

class _Callout {
  const _Callout(this.icon, this.text, this.detail);

  final IconData icon;
  final String text;
  final String detail;
}

const _mockCallouts = [
  _Callout(PhosphorIconsFill.door, 'Door ahead', 'about 3 steps'),
  _Callout(PhosphorIconsFill.armchair, 'Chair on your left', 'close by'),
  _Callout(PhosphorIconsFill.arrowBendUpRight, 'Path bends right',
      'in 5 steps'),
  _Callout(PhosphorIconsFill.textT, 'Sign: "Room 204"', 'on your right'),
];

class _AssistPageState extends State<AssistPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  )..repeat();

  final FlutterTts _tts = FlutterTts();
  Timer? _timer;
  int _calloutIndex = 0;
  bool _voiceOn = true;

  @override
  void initState() {
    super.initState();
    _speak(_mockCallouts[_calloutIndex]);
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      setState(() {
        _calloutIndex = (_calloutIndex + 1) % _mockCallouts.length;
      });
      _speak(_mockCallouts[_calloutIndex]);
    });
  }

  Future<void> _speak(_Callout callout) async {
    if (!_voiceOn) return;
    try {
      await _tts.speak('${callout.text}, ${callout.detail}');
    } catch (_) {
      // TTS unavailable (e.g. emulator without a TTS engine) — stay silent.
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _tts.stop();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const viewportColor = Color(0xFF161514);
    final callout = _mockCallouts[_calloutIndex];

    return Scaffold(
      backgroundColor: viewportColor,
      body: Column(
        children: [
          Expanded(
            child: SafeArea(
              bottom: false,
              child: Stack(
                children: [
                  // Pulsing rings around the assist glyph.
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
                  Positioned(
                    left: AppDimens.space16,
                    top: AppDimens.space12,
                    child: Material(
                      color: Colors.white.withValues(alpha: 0.12),
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
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppDimens.space12,
                          vertical: AppDimens.space8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.12),
                          borderRadius:
                              BorderRadius.circular(AppDimens.radiusPill),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _LiveDot(),
                            SizedBox(width: AppDimens.space8),
                            Text(
                              'Assisting',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
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
                        padding: const EdgeInsets.all(AppDimens.space16),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.10),
                          borderRadius:
                              BorderRadius.circular(AppDimens.radiusLg),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: const BoxDecoration(
                                color: AppColors.coral,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(callout.icon,
                                  color: Colors.white, size: 22),
                            ),
                            const SizedBox(width: AppDimens.space12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    callout.text,
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
                                        fontSize: 14),
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
          ),
          _AssistSheet(
            voiceOn: _voiceOn,
            onVoiceToggle: () => setState(() => _voiceOn = !_voiceOn),
          ),
        ],
      ),
    );
  }
}

class _LiveDot extends StatelessWidget {
  const _LiveDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: const BoxDecoration(
        color: AppColors.coral,
        shape: BoxShape.circle,
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
                  value: 'On',
                ),
                const SizedBox(width: AppDimens.space8),
                Expanded(
                  child: Semantics(
                    button: true,
                    label: voiceOn ? 'Mute voice' : 'Unmute voice',
                    child: Material(
                      color: theme.colorScheme.surface,
                      borderRadius:
                          BorderRadius.circular(AppDimens.radiusMd),
                      child: InkWell(
                        onTap: onVoiceToggle,
                        borderRadius:
                            BorderRadius.circular(AppDimens.radiusMd),
                        child: Padding(
                          padding:
                              const EdgeInsets.all(AppDimens.space12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Voice',
                                  style: theme.textTheme.labelSmall),
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
                                        : theme
                                            .textTheme.bodyMedium?.color,
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
                Icon(icon, size: 16,
                    color: theme.textTheme.bodyMedium?.color),
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
