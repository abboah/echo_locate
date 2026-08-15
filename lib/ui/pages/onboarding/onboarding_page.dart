import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../../core/routes/app_routes.dart';
import '../../../core/settings/settings_repository.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimens.dart';
import '../../../services/injection_container.dart';

class _Step {
  const _Step(this.icon, this.title, this.body, {this.inkIcon = false});

  final IconData icon;
  final String title;
  final String body;

  /// Step 3's icon square is ink instead of coral (accessibility step).
  final bool inkIcon;
}

const _steps = [
  _Step(
    PhosphorIconsFill.personSimpleWalk,
    'Move confidently,\nindoors',
    'EchoLocate speaks what is around you as you walk — obstacles, doors, '
        'and signs.',
  ),
  _Step(
    PhosphorIconsFill.mapTrifold,
    'Find any room,\nanywhere',
    "Turn-by-turn guidance in places GPS can't reach — malls, hospitals, "
        'campuses.',
  ),
  _Step(
    PhosphorIconsFill.handHeart,
    'Built with blind and\nlow-vision users',
    'Voice guidance, haptics, and a community that maps spaces for '
        'each other.',
    inkIcon: true,
  ),
];

/// 3-step intro (Figma 7:1155 / 7:1122 / 7:1089). Shown once; sets the
/// onboarding flag that the router redirect checks.
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    await getIt<SettingsRepository>().setOnboardingSeen();
    if (mounted) context.goNamed(RouteNames.welcome);
  }

  void _next() {
    if (_index == _steps.length - 1) {
      _finish();
    } else {
      _controller.nextPage(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLast = _index == _steps.length - 1;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppDimens.pageGutter),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('EchoLocate', style: theme.textTheme.titleLarge),
                  if (!isLast)
                    TextButton(
                      onPressed: _finish,
                      child: Text('Skip', style: theme.textTheme.bodyMedium),
                    ),
                ],
              ),
              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  itemCount: _steps.length,
                  onPageChanged: (i) => setState(() => _index = i),
                  itemBuilder: (context, i) => _StepView(step: _steps[i]),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < _steps.length; i++) ...[
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: i == _index ? 20 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: i == _index
                            ? AppColors.coral
                            : theme.dividerColor,
                        borderRadius: BorderRadius.circular(
                          AppDimens.radiusPill,
                        ),
                      ),
                    ),
                    if (i != _steps.length - 1)
                      const SizedBox(width: AppDimens.space8),
                  ],
                ],
              ),
              const SizedBox(height: AppDimens.space20),
              ElevatedButton(
                onPressed: _next,
                child: Text(isLast ? 'Get started' : 'Continue'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StepView extends StatelessWidget {
  const _StepView({required this.step});

  final _Step step;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final squareColor = step.inkIcon
        ? (isDark ? AppColors.darkElevated : AppColors.ink)
        : AppColors.coral;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Spacer(),
        Center(
          child: Container(
            width: 220,
            height: 220,
            decoration: BoxDecoration(
              color: isDark
                  ? AppColors.coral.withValues(alpha: 0.10)
                  : AppColors.coralSoft.withValues(alpha: 0.6),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  color: squareColor,
                  borderRadius: BorderRadius.circular(AppDimens.radiusXl),
                ),
                child: Icon(step.icon, color: Colors.white, size: 36),
              ),
            ),
          ),
        ),
        const Spacer(),
        Text(step.title, style: theme.textTheme.displaySmall),
        const SizedBox(height: AppDimens.space12),
        Text(
          step.body,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.textTheme.bodyMedium?.color,
          ),
        ),
        const SizedBox(height: AppDimens.space16),
      ],
    );
  }
}
