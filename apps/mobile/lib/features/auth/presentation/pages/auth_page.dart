import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/navigation/app_routes.dart';
import '../providers/auth_providers.dart';

class AuthPage extends ConsumerStatefulWidget {
  const AuthPage({super.key});

  @override
  ConsumerState<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends ConsumerState<AuthPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  bool _registrationMode = false;
  bool _submitting = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authControllerProvider, (previous, next) {
      final session = next.valueOrNull;
      if (session == null) {
        return;
      }
      context.go(
        session.requiresOnboarding ? AppRoutes.onboarding : AppRoutes.dashboard,
      );
    });

    final authState = ref.watch(authControllerProvider);
    final isBusy = _submitting || authState.isLoading;

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 520;
            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                compact ? AppSpacing.md : AppSpacing.xl,
                AppSpacing.xl,
                compact ? AppSpacing.md : AppSpacing.xl,
                AppSpacing.xl,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - AppSpacing.xl * 2,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _IconHero(compact: compact),
                    const SizedBox(height: AppSpacing.xl),
                    Text(
                      'PERSONAL COACH',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                            letterSpacing: 4,
                          ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      'Build your day-aware coach',
                      style: Theme.of(context).textTheme.headlineLarge,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'Start as guest, connect later, and give the app your timetable so reminders understand school, study blocks, recovery windows, and deadlines.',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: _AuthColors.muted(context),
                            height: 1.55,
                          ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    _ModeTabs(
                      registrationMode: _registrationMode,
                      onChanged: (value) {
                        setState(() => _registrationMode = value);
                      },
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _AuthForm(
                      registrationMode: _registrationMode,
                      nameController: _nameController,
                      emailController: _emailController,
                      passwordController: _passwordController,
                      onSubmit: isBusy ? null : _submitEmail,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _AuthActionTile(
                      icon: Icons.person_outline,
                      title: 'Continue as guest',
                      subtitle: 'Best for testing right now',
                      onTap: isBusy ? null : _continueAsGuest,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _AuthActionTile(
                      icon: Icons.login,
                      title: 'Sign in with Google',
                      subtitle: 'Uses Supabase OAuth when enabled',
                      onTap: isBusy ? null : _signInWithGoogle,
                    ),
                    if (authState.hasError) ...[
                      const SizedBox(height: AppSpacing.md),
                      _InlineError(message: '${authState.error}'),
                    ],
                    if (isBusy) ...[
                      const SizedBox(height: AppSpacing.lg),
                      const LinearProgressIndicator(),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _submitEmail() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.length < 6) {
      _showMessage('Enter an email and a password with at least 6 characters.');
      return;
    }

    setState(() => _submitting = true);
    try {
      if (_registrationMode) {
        final created =
            await ref.read(authControllerProvider.notifier).registerWithEmail(
                  email: email,
                  password: password,
                  name: _nameController.text.trim(),
                );
        if (!created && mounted) {
          _showMessage('Check your email to confirm the registration.');
        }
      } else {
        await ref.read(authControllerProvider.notifier).signInWithEmail(
              email: email,
              password: password,
            );
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Future<void> _continueAsGuest() async {
    await ref.read(authControllerProvider.notifier).continueAsGuest();
  }

  Future<void> _signInWithGoogle() async {
    try {
      await ref.read(authControllerProvider.notifier).signInWithGoogle();
    } catch (error) {
      _showMessage(
        'Google OAuth is not enabled in Supabase yet. Enable Google provider first.',
      );
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }
}

class _IconHero extends StatelessWidget {
  const _IconHero({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: compact ? 72 : 90,
      height: compact ? 72 : 90,
      decoration: BoxDecoration(
        color: _AuthColors.panel(context),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: _AuthColors.border(context), width: 2),
      ),
      child: Icon(
        Icons.auto_awesome,
        color: Theme.of(context).colorScheme.primary,
        size: compact ? 34 : 42,
      ),
    );
  }
}

class _ModeTabs extends StatelessWidget {
  const _ModeTabs({
    required this.registrationMode,
    required this.onChanged,
  });

  final bool registrationMode;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<bool>(
      segments: const [
        ButtonSegment(value: false, label: Text('Login')),
        ButtonSegment(value: true, label: Text('Register')),
      ],
      selected: {registrationMode},
      onSelectionChanged: (selection) => onChanged(selection.first),
    );
  }
}

class _AuthForm extends StatelessWidget {
  const _AuthForm({
    required this.registrationMode,
    required this.nameController,
    required this.emailController,
    required this.passwordController,
    required this.onSubmit,
  });

  final bool registrationMode;
  final TextEditingController nameController;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final VoidCallback? onSubmit;

  @override
  Widget build(BuildContext context) {
    return _AuthSurface(
      child: Column(
        children: [
          if (registrationMode) ...[
            TextField(
              controller: nameController,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Name optional'),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          TextField(
            controller: emailController,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: 'Email'),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: passwordController,
            obscureText: true,
            onSubmitted: (_) => onSubmit?.call(),
            decoration: const InputDecoration(labelText: 'Password'),
          ),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onSubmit,
              icon: Icon(registrationMode ? Icons.person_add_alt : Icons.login),
              label: Text(registrationMode ? 'Create account' : 'Login'),
            ),
          ),
        ],
      ),
    );
  }
}

class _AuthActionTile extends StatelessWidget {
  const _AuthActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: _AuthSurface(
        child: Row(
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary, size: 30),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: _AuthColors.muted(context),
                        ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}

class _AuthSurface extends StatelessWidget {
  const _AuthSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: _AuthColors.panel(context),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: _AuthColors.border(context), width: 2),
      ),
      child: child,
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: const Color(0xFFFF8F70).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(message, style: Theme.of(context).textTheme.bodyMedium),
    );
  }
}

class _AuthColors {
  const _AuthColors._();

  static bool _light(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light;

  static Color panel(BuildContext context) =>
      _light(context) ? Colors.white : const Color(0xFF122329);

  static Color border(BuildContext context) =>
      _light(context) ? const Color(0xFFD4E1DF) : const Color(0xFF2A424A);

  static Color muted(BuildContext context) =>
      _light(context) ? const Color(0xFF607078) : const Color(0xFFA8B5BE);
}
