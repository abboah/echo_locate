import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'core/theme/app_theme.dart';
import 'core/theme/theme_cubit.dart';
import 'features/auth/bloc/auth_bloc.dart';
import 'router/app_router.dart';
import 'services/injection_container.dart';

/// Root widget. Provides the app-wide [ThemeCubit] and [AuthBloc], and
/// rebuilds `MaterialApp.router` on theme changes.
class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<ThemeCubit>.value(value: getIt<ThemeCubit>()),
        BlocProvider<AuthBloc>.value(value: getIt<AuthBloc>()),
      ],
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

/*
  Top of ArGuidanceHandler.kt, lines 145 and 163:

  private const val MEASURE_FLOOR = true    // line 145
  private const val FOLLOW_ANCHORS = true   // line 163

  Flip either to false, rebuild, and that half of yesterday's
  work behaves exactly like the build you had before it.

  MEASURE_FLOOR = false — no plane fitting at all, floor falls
  back to the assumed 1.35 m below the phone. Turn this off
  first if the session stutters when the guidance screen
  opens. Your 60 fps measurement on the Infinix was taken
  without plane finding, and it now competes with the ML Kit
  frame feed for the first 20 seconds rather than 9.

  **The cost of turning it off is no longer only cosmetic.**
  It used to be: an assumed floor height, a ring floating a
  few centimetres off. The same switch now also turns off
  vertical plane finding, and the wall grid those planes
  supply is the only thing correcting the registration's yaw
  — which rotates the entire building and which no landmark
  can repair. Without it the rotation falls back to the
  direction the walker happened to set off in, which is the
  thing that was putting rings in the wrong room.

  So: turn it off to get frames back, and expect the arrow to
  be roughly right rather than right. Read `off …m` in the
  capture before and after, not the frame rate alone.

  FOLLOW_ANCHORS = false — route and leg keep the raw world
  coordinates they were laid down in. Turn this off if a
  registered route looks wrong in a way a dead-reckoned leg
  doesn't: arrow drifting sideways, the line slowly rotating,
  rings landing off the corridor. This is the only code that
  rewrites route geometry after registration, so if the
  geometry is being mangled, it's this or nothing. Cost of
  turning it off is that a relocalisation moves the building
  out from under the route.
*/
