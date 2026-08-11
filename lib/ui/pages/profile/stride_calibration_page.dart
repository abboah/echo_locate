import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimens.dart';
import '../../../features/profile/bloc/stride_calibration_cubit.dart';
import '../../../services/injection_container.dart';

/// Measuring the user's step length.
///
/// Two minutes here changes every distance the app ever speaks: routes are
/// stored in metres, and this is the number that turns them into *this* user's
/// steps. Skipping it is allowed — the height estimate and then a generic
/// default stand in — because a wrong-ish count still gets someone to a
/// landmark, where it is reset to zero anyway.
class StrideCalibrationPage extends StatelessWidget {
  const StrideCalibrationPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<StrideCalibrationCubit>(),
      child: const _CalibrationView(),
    );
  }
}

class _CalibrationView extends StatelessWidget {
  const _CalibrationView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(PhosphorIconsRegular.x),
          onPressed: () => context.pop(),
        ),
        title: const Text('Measure your step'),
      ),
      body: SafeArea(
        child: BlocBuilder<StrideCalibrationCubit, StrideCalibrationState>(
          builder: (context, state) {
            final cubit = context.read<StrideCalibrationCubit>();

            return ListView(
              padding: const EdgeInsets.all(AppDimens.space16),
              children: [
                Text(
                  'Walk a distance you have measured, at your normal pace.',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: AppDimens.space8),
                Text(
                  'Directions are stored in metres, so the app needs your own '
                  'step length to say “about twenty steps” and mean it. If you '
                  'cannot measure a distance, give your height instead — it is '
                  'less exact and needs nothing but a number.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: AppDimens.space24),
                if (state.status == CalibrationStatus.walking) ...[
                  Center(
                    child: Text(
                      '${state.steps}',
                      style: theme.textTheme.displayMedium
                          ?.copyWith(color: AppColors.coral),
                    ),
                  ),
                  Center(
                    child: Text('steps', style: theme.textTheme.labelSmall),
                  ),
                  const SizedBox(height: AppDimens.space24),
                  ElevatedButton(
                    onPressed: cubit.finish,
                    child: Text(
                      "I've walked ${state.distanceM.round()} metres",
                    ),
                  ),
                ] else if (state.status == CalibrationStatus.done) ...[
                  _Result(text: 'Your step is ${state.profile}.'),
                  const SizedBox(height: AppDimens.space16),
                  ElevatedButton(
                    onPressed: () => context.pop(),
                    child: const Text('Done'),
                  ),
                ] else ...[
                  if (state.status == CalibrationStatus.unavailable)
                    _Result(
                      warning: true,
                      text: state.error ??
                          'This phone has no step counter, so the walk cannot '
                              'be measured. Give your height instead — '
                              'guidance will lean on landmarks rather than '
                              'counts.',
                    )
                  // A rejected walk keeps what it measured on screen. Dropping
                  // straight back to the start screen read as the app having
                  // done nothing at all, and hid the one number — the count —
                  // that says whether the counter is working.
                  else if (state.status == CalibrationStatus.implausible) ...[
                    _Result(warning: true, text: state.error ?? ''),
                    const SizedBox(height: AppDimens.space8),
                    Text(
                      'Counted ${state.steps} steps over '
                      '${state.distanceM.round()} metres.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ] else if (state.error != null)
                    _Result(warning: true, text: state.error!),
                  if (state.status != CalibrationStatus.unavailable) ...[
                    const SizedBox(height: AppDimens.space16),
                    _DistancePicker(
                      selected: state.distanceM,
                      onSelected: cubit.setDistance,
                    ),
                    const SizedBox(height: AppDimens.space16),
                    ElevatedButton.icon(
                      onPressed: cubit.begin,
                      icon: const Icon(PhosphorIconsFill.footprints, size: 18),
                      label: Text(
                        state.status == CalibrationStatus.implausible
                            ? 'Try the walk again'
                            : 'Start walking',
                      ),
                    ),
                  ],
                  const SizedBox(height: AppDimens.space24),
                  const _HeightFallback(),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

/// How far the user is about to walk.
///
/// The cubit has always supported any distance; without this the screen pinned
/// everyone to ten metres, so a corridor that happened to be eight or twenty
/// could not be used and the walk had to be abandoned.
class _DistancePicker extends StatelessWidget {
  const _DistancePicker({required this.selected, required this.onSelected});

  static const List<double> _options = [5, 10, 20];

  final double selected;
  final ValueChanged<double> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Distance you measured', style: theme.textTheme.labelSmall),
        const SizedBox(height: AppDimens.space8),
        Wrap(
          spacing: AppDimens.space8,
          children: [
            for (final metres in _options)
              ChoiceChip(
                label: Text('${metres.round()} m'),
                selected: (selected - metres).abs() < 0.01,
                selectedColor: AppColors.coralSoft,
                onSelected: (_) => onSelected(metres),
              ),
          ],
        ),
      ],
    );
  }
}

class _HeightFallback extends StatefulWidget {
  const _HeightFallback();

  @override
  State<_HeightFallback> createState() => _HeightFallbackState();
}

class _HeightFallbackState extends State<_HeightFallback> {
  final _height = TextEditingController();

  @override
  void dispose() {
    _height.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Or estimate it', style: theme.textTheme.labelSmall),
        const SizedBox(height: AppDimens.space8),
        TextField(
          controller: _height,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Your height in metres',
            hintText: '1.70',
          ),
        ),
        const SizedBox(height: AppDimens.space12),
        OutlinedButton(
          onPressed: () {
            final height = double.tryParse(_height.text.trim());
            if (height == null) return;
            context.read<StrideCalibrationCubit>().saveFromHeight(height);
          },
          child: const Text('Use my height'),
        ),
      ],
    );
  }
}

class _Result extends StatelessWidget {
  const _Result({required this.text, this.warning = false});

  final String text;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final tint = warning ? AppColors.warning : AppColors.coral;

    return Container(
      padding: const EdgeInsets.all(AppDimens.space12),
      decoration: BoxDecoration(
        color: isDark
            ? tint.withValues(alpha: 0.16)
            : (warning ? AppColors.warningSoft : AppColors.coralSoft),
        borderRadius: BorderRadius.circular(AppDimens.radiusLg),
      ),
      child: Text(text, style: theme.textTheme.bodyMedium),
    );
  }
}
