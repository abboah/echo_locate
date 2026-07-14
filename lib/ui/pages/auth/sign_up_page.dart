import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../../core/routes/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_dimens.dart';
import '../../../features/auth/bloc/auth_bloc.dart';

/// Email sign-up with inline validation error (Figma 7:963).
class SignUpPage extends StatefulWidget {
  const SignUpPage({super.key});

  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    context.read<AuthBloc>().add(AuthSignUpSubmitted(
          fullName: _name.text,
          email: _email.text.trim(),
          password: _password.text,
        ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: BlocBuilder<AuthBloc, AuthState>(
          builder: (context, state) {
            final unauthenticated =
                state is AuthUnauthenticated ? state : null;
            final busy = unauthenticated?.inProgress ?? false;
            final error = unauthenticated?.error;
            // Route the error to the field it belongs to (the design shows
            // the password error inline under the field).
            final nameError =
                error != null && error.contains('name') ? error : null;
            final emailError =
                error != null && error.contains('email') ? error : null;
            final passwordError = error != null &&
                    nameError == null &&
                    emailError == null
                ? error
                : null;

            return ListView(
              padding: const EdgeInsets.all(AppDimens.pageGutter),
              children: [
                _BackCircle(onTap: () => context.pop()),
                const SizedBox(height: AppDimens.space24),
                Text('Create account', style: theme.textTheme.displaySmall),
                const SizedBox(height: AppDimens.space4),
                Text(
                  'Start mapping in under a minute.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: AppDimens.space24),
                Text('Full name', style: theme.textTheme.labelSmall),
                const SizedBox(height: AppDimens.space8),
                TextField(
                  controller: _name,
                  autofillHints: const [AutofillHints.name],
                  decoration: InputDecoration(
                    hintText: 'John Adomako',
                    errorText: nameError,
                  ),
                ),
                const SizedBox(height: AppDimens.space16),
                Text('Email', style: theme.textTheme.labelSmall),
                const SizedBox(height: AppDimens.space8),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  decoration: InputDecoration(
                    hintText: 'you@example.com',
                    errorText: emailError,
                  ),
                ),
                const SizedBox(height: AppDimens.space16),
                Text('Password', style: theme.textTheme.labelSmall),
                const SizedBox(height: AppDimens.space8),
                TextField(
                  controller: _password,
                  obscureText: _obscure,
                  autofillHints: const [AutofillHints.newPassword],
                  onSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    hintText: 'At least 8 characters',
                    prefixIcon:
                        const Icon(PhosphorIconsRegular.lockSimple, size: 20),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscure
                            ? PhosphorIconsRegular.eye
                            : PhosphorIconsRegular.eyeSlash,
                        size: 20,
                      ),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                    errorText: passwordError,
                  ),
                ),
                const SizedBox(height: AppDimens.space24),
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
                      : const Text('Create account'),
                ),
                const SizedBox(height: AppDimens.space48),
                Center(
                  child: Text.rich(
                    TextSpan(
                      text: 'Already have an account? ',
                      style: theme.textTheme.bodyMedium,
                      children: [
                        WidgetSpan(
                          child: GestureDetector(
                            onTap: () => context
                                .pushReplacementNamed(RouteNames.signIn),
                            child: Text(
                              'Sign in',
                              style: theme.textTheme.labelLarge
                                  ?.copyWith(color: AppColors.coral),
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
