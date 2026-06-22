import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'core/theme/app_theme.dart';
import 'core/theme/theme_cubit.dart';
import 'router/app_router.dart';
import 'services/injection_container.dart';

/// Root widget. Provides the app-wide [ThemeCubit] and rebuilds
/// `MaterialApp.router` on theme changes.
class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<ThemeCubit>.value(
      value: getIt<ThemeCubit>(),
      child: BlocBuilder<ThemeCubit, ThemeMode>(
        builder: (context, themeMode) {
          return MaterialApp.router(
            title: 'EchoLocate',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: themeMode,
            routerConfig: appRouter,
          );
        },
      ),
    );
  }
}
