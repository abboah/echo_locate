import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimens.dart';
import '../scan/camera_flow.dart';

/// 5-slot bottom navigation: Home · Explore · [Assist FAB] · Maps · Profile.
/// The coral center FAB starts Assist Mode — one tap from anywhere to
/// obstacle alerts + voice guidance. Active tabs use Phosphor Fill weights
/// (filled shapes stay readable for low-vision users at small sizes).
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: navigationShell,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: Semantics(
        label: 'Start assistance',
        button: true,
        child: FloatingActionButton(
          onPressed: () => openAssistFlow(context),
          backgroundColor: AppColors.coral,
          foregroundColor: Colors.white,
          elevation: 2,
          shape: const CircleBorder(),
          child: const Icon(PhosphorIconsFill.eye, size: 26),
        ),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : AppColors.white,
          border: Border(top: BorderSide(color: theme.dividerColor)),
        ),
        child: SafeArea(
          child: SizedBox(
            height: 64,
            child: Row(
              children: [
                _NavItem(
                  index: 0,
                  shell: navigationShell,
                  icon: PhosphorIconsRegular.house,
                  activeIcon: PhosphorIconsFill.house,
                  label: 'Home',
                ),
                _NavItem(
                  index: 1,
                  shell: navigationShell,
                  icon: PhosphorIconsRegular.magnifyingGlass,
                  activeIcon: PhosphorIconsBold.magnifyingGlass,
                  label: 'Explore',
                ),
                // Gap under the docked assist FAB.
                const Expanded(child: SizedBox()),
                _NavItem(
                  index: 2,
                  shell: navigationShell,
                  icon: PhosphorIconsRegular.mapTrifold,
                  activeIcon: PhosphorIconsFill.mapTrifold,
                  label: 'Maps',
                ),
                _NavItem(
                  index: 3,
                  shell: navigationShell,
                  icon: PhosphorIconsRegular.user,
                  activeIcon: PhosphorIconsFill.user,
                  label: 'Profile',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.index,
    required this.shell,
    required this.icon,
    required this.activeIcon,
    required this.label,
  });

  final int index;
  final StatefulNavigationShell shell;
  final IconData icon;
  final IconData activeIcon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = shell.currentIndex == index;
    final color = active
        ? theme.colorScheme.onSurface
        : theme.textTheme.bodyMedium?.color;

    return Expanded(
      child: Semantics(
        label: label,
        selected: active,
        button: true,
        child: InkWell(
          onTap: () => shell.goBranch(
            index,
            initialLocation: index == shell.currentIndex,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(active ? activeIcon : icon, size: 24, color: color),
              const SizedBox(height: AppDimens.space2),
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              const SizedBox(height: AppDimens.space2),
              // Active indicator dash (per the Home mock).
              Container(
                width: 14,
                height: 3,
                decoration: BoxDecoration(
                  color: active ? AppColors.coral : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppDimens.radiusPill),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
