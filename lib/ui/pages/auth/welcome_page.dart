import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routes/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimens.dart';
import '../../../features/auth/bloc/auth_bloc.dart';

/// Auth landing (Figma 7:1057): Apple / Google / email entry points.
class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: BlocListener<AuthBloc, AuthState>(
        listenWhen: (prev, curr) =>
            curr is AuthUnauthenticated && curr.error != null,
        listener: (context, state) {
          final error = (state as AuthUnauthenticated).error!;
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(error)));
        },
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppDimens.pageGutter),
            child: BlocBuilder<AuthBloc, AuthState>(
              builder: (context, state) {
                final busy =
                    state is AuthUnauthenticated && state.inProgress;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Spacer(),
                    Center(
                      child: Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: AppColors.coral,
                          borderRadius:
                              BorderRadius.circular(AppDimens.radiusLg),
                        ),
                        child: const Icon(Icons.map_outlined,
                            color: Colors.white, size: 30),
                      ),
                    ),
                    const SizedBox(height: AppDimens.space20),
                    Text(
                      'Welcome to EchoLocate',
                      style: theme.textTheme.headlineMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppDimens.space4),
                    Text(
                      'Sign in to scan, save and contribute maps',
                      style: theme.textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppDimens.space32),
                    ElevatedButton.icon(
                      onPressed: busy
                          ? null
                          : () => context
                              .read<AuthBloc>()
                              .add(const AuthAppleRequested()),
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            isDark ? AppColors.darkElevated : AppColors.ink,
                      ),
                      icon: const Icon(Icons.apple, size: 20),
                      label: const Text('Sign in with Apple'),
                    ),
                    const SizedBox(height: AppDimens.space12),
                    OutlinedButton.icon(
                      onPressed: busy
                          ? null
                          : () => context
                              .read<AuthBloc>()
                              .add(const AuthGoogleRequested()),
                      icon: Text(
                        'G',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: AppColors.coral,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      label: const Text('Sign in with Google'),
                    ),
                    const SizedBox(height: AppDimens.space12),
                    OutlinedButton.icon(
                      onPressed: busy
                          ? null
                          : () => context.pushNamed(RouteNames.signIn),
                      icon: const Icon(Icons.mail_outline, size: 20),
                      label: const Text('Continue with email'),
                    ),
                    const Spacer(),
                    if (busy)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.only(bottom: AppDimens.space16),
                          child: CircularProgressIndicator(),
                        ),
                      ),
                    Text(
                      'By continuing you agree to our Terms and Privacy Policy.',
                      style: theme.textTheme.labelSmall,
                      textAlign: TextAlign.center,
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
