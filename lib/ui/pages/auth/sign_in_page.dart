import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../../core/routes/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimens.dart';
import '../../../features/auth/bloc/auth_bloc.dart';

/// Email sign-in (Figma 7:1010).
class SignInPage extends StatefulWidget {
  const SignInPage({super.key});

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    context.read<AuthBloc>().add(
      AuthSignInSubmitted(email: _email.text.trim(), password: _password.text),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: BlocBuilder<AuthBloc, AuthState>(
          builder: (context, state) {
            final unauthenticated = state is AuthUnauthenticated ? state : null;
            final busy = unauthenticated?.inProgress ?? false;
            final error = unauthenticated?.error;

            return ListView(
              padding: const EdgeInsets.all(AppDimens.pageGutter),
              children: [
                _BackCircle(onTap: () => context.pop()),
                const SizedBox(height: AppDimens.space24),
                Text('Sign in', style: theme.textTheme.displaySmall),
                const SizedBox(height: AppDimens.space4),
                Text(
                  'Welcome back. Enter your details.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: AppDimens.space24),
                Text('Email', style: theme.textTheme.labelSmall),
                const SizedBox(height: AppDimens.space8),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(
                    hintText: 'you@example.com',
                    prefixIcon: Icon(
                      PhosphorIconsRegular.envelopeSimple,
                      size: 20,
                    ),
                  ),
                ),
                const SizedBox(height: AppDimens.space16),
                Text('Password', style: theme.textTheme.labelSmall),
                const SizedBox(height: AppDimens.space8),
                TextField(
                  controller: _password,
                  obscureText: _obscure,
                  autofillHints: const [AutofillHints.password],
                  onSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    hintText: 'Your password',
                    prefixIcon: const Icon(
                      PhosphorIconsRegular.lockSimple,
                      size: 20,
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscure
                            ? PhosphorIconsRegular.eye
                            : PhosphorIconsRegular.eyeSlash,
                        size: 20,
                      ),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                    errorText: error,
                  ),
                ),
                const SizedBox(height: AppDimens.space8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Password reset arrives with Supabase auth',
                        ),
                      ),
                    ),
                    child: Text(
                      'Forgot password?',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: AppColors.coral,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppDimens.space8),
                ElevatedButton(
                  onPressed: busy ? null : _submit,
                  child: busy
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Sign in'),
                ),
                const SizedBox(height: AppDimens.space48),
                Center(
                  child: Text.rich(
                    TextSpan(
                      text: 'New here? ',
                      style: theme.textTheme.bodyMedium,
                      children: [
                        WidgetSpan(
                          child: GestureDetector(
                            onTap: () =>
                                context.pushReplacementNamed(RouteNames.signUp),
                            child: Text(
                              'Create account',
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: AppColors.coral,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _BackCircle extends StatelessWidget {
  const _BackCircle({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Material(
        color: theme.brightness == Brightness.dark
            ? AppColors.darkElevated
            : AppColors.white,
        shape: CircleBorder(side: BorderSide(color: theme.dividerColor)),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: 42,
            height: 42,
            child: Icon(
              PhosphorIconsRegular.caretLeft,
              size: 20,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}
