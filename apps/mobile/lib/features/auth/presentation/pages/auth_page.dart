import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_radii.dart';
import '../../../../core/constants/app_spacing.dart';
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
  String? _accountHelpMessage;
  bool _accountHelpFailed = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final authNotice = ref.watch(authNoticeProvider);
    final isBusy = _submitting || authState.isLoading;
    final authErrorMessage = authState.error is AuthConfigurationException
        ? 'Synced sign-in is not configured. Configure Supabase or continue as guest.'
        : 'Authentication failed. Check your details and connection, then try again.';

    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Theme.of(context).scaffoldBackgroundColor,
              colors.primaryContainer.withValues(alpha: 0.16),
              Theme.of(context).scaffoldBackgroundColor,
            ],
            stops: const [0, 0.48, 1],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 960;
              final horizontalPadding = wide ? 56.0 : AppSpacing.md;
              final verticalPadding = wide ? 48.0 : AppSpacing.lg;
              final intro = _AuthIntro(compact: !wide);
              final access = _AuthPanel(
                child: _buildAccessPanel(
                  authHasError: authState.hasError,
                  authNotice: authNotice,
                  authErrorMessage: authErrorMessage,
                  isBusy: isBusy,
                ),
              );

              return SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: horizontalPadding,
                  vertical: verticalPadding,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: 1120,
                      minHeight: constraints.maxHeight - verticalPadding * 2,
                    ),
                    child: wide
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(child: intro),
                              const SizedBox(width: 72),
                              SizedBox(width: 440, child: access),
                            ],
                          )
                        : ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 560),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                intro,
                                const SizedBox(height: AppSpacing.xl),
                                access,
                              ],
                            ),
                          ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildAccessPanel({
    required bool authHasError,
    required AuthNotice? authNotice,
    required String authErrorMessage,
    required bool isBusy,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _registrationMode ? 'Create your account' : 'Welcome back',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          _registrationMode
              ? 'Start with a synced space you can return to.'
              : 'Choose how you want to continue.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        if (authNotice != null) ...[
          const SizedBox(height: AppSpacing.md),
          _InlineStatus(
            message: authNotice.message,
            isError: authNotice.isError,
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () =>
                  ref.read(authNoticeProvider.notifier).state = null,
              child: const Text('Dismiss'),
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        SizedBox(
          width: double.infinity,
          child: _ModeTabs(
            registrationMode: _registrationMode,
            onChanged: (value) {
              setState(() {
                _registrationMode = value;
                _accountHelpMessage = null;
              });
              _clearAuthNotice();
            },
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        _AuthForm(
          registrationMode: _registrationMode,
          nameController: _nameController,
          emailController: _emailController,
          passwordController: _passwordController,
          onSubmit: isBusy ? null : _submitEmail,
        ),
        if (authHasError) ...[
          const SizedBox(height: AppSpacing.md),
          _InlineStatus(message: authErrorMessage, isError: true),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: isBusy
                ? null
                : _registrationMode
                    ? _resendSignupConfirmation
                    : _requestPasswordReset,
            child: Text(
              _registrationMode
                  ? 'Resend confirmation email'
                  : 'Forgot password?',
            ),
          ),
        ),
        if (_accountHelpMessage != null) ...[
          const SizedBox(height: AppSpacing.sm),
          _InlineStatus(
            message: _accountHelpMessage!,
            isError: _accountHelpFailed,
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            const Expanded(child: Divider()),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Text(
                'or',
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
            const Expanded(child: Divider()),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        _AuthActionTile(
          icon: Icons.person_outline_rounded,
          title: 'Continue as guest',
          subtitle:
              'Local demo. Setup stays on this device and will not move to a later account.',
          onTap: isBusy ? null : _continueAsGuest,
        ),
        const SizedBox(height: AppSpacing.sm),
        _AuthActionTile(
          leading: const _GoogleLogo(),
          title: 'Sign in with Google',
          subtitle: 'Continue with your Google account',
          onTap: isBusy ? null : _signInWithGoogle,
        ),
        if (isBusy) ...[
          const SizedBox(height: AppSpacing.lg),
          const LinearProgressIndicator(),
        ],
      ],
    );
  }

  Future<void> _submitEmail() async {
    _clearAuthNotice();
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
          final registrationState = ref.read(authControllerProvider);
          if (registrationState.hasError) {
            return;
          }
          setState(() {
            _accountHelpFailed = false;
            _accountHelpMessage =
                'Check your email to confirm registration. You can resend the confirmation here if needed.';
          });
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
    _clearAuthNotice();
    await ref.read(authControllerProvider.notifier).continueAsGuest();
  }

  Future<void> _signInWithGoogle() async {
    _clearAuthNotice();
    setState(() => _submitting = true);
    try {
      await ref.read(authControllerProvider.notifier).signInWithGoogle();
    } catch (_) {
      if (mounted) {
        _showMessage(
          'Google sign-in could not start. Check Supabase OAuth settings.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Future<void> _requestPasswordReset() async {
    _clearAuthNotice();
    final email = _emailController.text.trim();
    if (!_looksLikeEmail(email)) {
      setState(() {
        _accountHelpFailed = true;
        _accountHelpMessage = 'Enter your account email first.';
      });
      return;
    }
    await _runAccountHelp(
      () => ref
          .read(authControllerProvider.notifier)
          .requestPasswordReset(email: email),
      success:
          'If that account exists, a password-reset link has been sent. Open it on this device to choose a new password.',
      failure:
          'The password-reset email could not be requested. Check your connection and try again.',
    );
  }

  Future<void> _resendSignupConfirmation() async {
    _clearAuthNotice();
    final email = _emailController.text.trim();
    if (!_looksLikeEmail(email)) {
      setState(() {
        _accountHelpFailed = true;
        _accountHelpMessage = 'Enter the registration email first.';
      });
      return;
    }
    await _runAccountHelp(
      () => ref
          .read(authControllerProvider.notifier)
          .resendSignupConfirmation(email: email),
      success: 'If confirmation is still pending, a new email has been sent.',
      failure:
          'The confirmation email could not be resent. Check your connection and try again.',
    );
  }

  Future<void> _runAccountHelp(
    Future<void> Function() operation, {
    required String success,
    required String failure,
  }) async {
    setState(() {
      _submitting = true;
      _accountHelpMessage = null;
    });
    try {
      await operation();
      if (mounted) {
        setState(() {
          _accountHelpFailed = false;
          _accountHelpMessage = success;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _accountHelpFailed = true;
          _accountHelpMessage = failure;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  bool _looksLikeEmail(String value) {
    final at = value.indexOf('@');
    return at > 0 && at < value.length - 1;
  }

  void _clearAuthNotice() {
    ref.read(authNoticeProvider.notifier).state = null;
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }
}

class _AuthIntro extends StatelessWidget {
  const _AuthIntro({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _IconHero(compact: compact),
        SizedBox(height: compact ? AppSpacing.lg : AppSpacing.xl),
        Text(
          'PERSONAL COACH',
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.primary,
            letterSpacing: 3.2,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Build your day-aware coach',
          style: compact
              ? theme.textTheme.headlineLarge
              : theme.textTheme.displaySmall,
        ),
        const SizedBox(height: AppSpacing.md),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Text(
            'Use a synced account or explore locally as a guest. Guest Setup stays on this device and is not copied into a later account; only guest check-ins may migrate best-effort.',
            style: theme.textTheme.bodyLarge,
          ),
        ),
      ],
    );
  }
}

class _AuthPanel extends StatelessWidget {
  const _AuthPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(AppRadii.xl),
        border: Border.all(color: colors.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 32,
            spreadRadius: -12,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _IconHero extends StatelessWidget {
  const _IconHero({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: compact ? 64 : 76,
      height: compact ? 64 : 76,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colors.primaryContainer, colors.secondaryContainer],
        ),
        borderRadius: BorderRadius.circular(AppRadii.xl),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Icon(
        Icons.auto_awesome_rounded,
        color: colors.onPrimaryContainer,
        size: compact ? 30 : 36,
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
    return Column(
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
    );
  }
}

class _AuthActionTile extends StatelessWidget {
  const _AuthActionTile({
    this.icon,
    this.leading,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData? icon;
  final Widget? leading;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final borderRadius = BorderRadius.circular(AppRadii.lg);
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: title,
      hint: subtitle,
      onTap: onTap,
      child: ExcludeSemantics(
        child: Material(
          color: colors.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: borderRadius,
            side: BorderSide(color: colors.outlineVariant),
          ),
          child: InkWell(
            borderRadius: borderRadius,
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  leading ??
                      Icon(
                        icon,
                        color: colors.primary,
                        size: 26,
                      ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          subtitle,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: colors.outline),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GoogleLogo extends StatelessWidget {
  const _GoogleLogo();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: colors.surface,
        shape: BoxShape.circle,
        border: Border.all(color: colors.outlineVariant),
      ),
      alignment: Alignment.center,
      child: CustomPaint(
        size: const Size(22, 22),
        painter: _GoogleLogoPainter(),
      ),
    );
  }
}

class _GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.16;
    final rect = Offset.zero & size;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    paint.color = const Color(0xFF4285F4);
    canvas.drawArc(rect.deflate(stroke / 2), -0.1, 1.35, false, paint);
    paint.color = const Color(0xFF34A853);
    canvas.drawArc(rect.deflate(stroke / 2), 1.35, 1.05, false, paint);
    paint.color = const Color(0xFFFBBC05);
    canvas.drawArc(rect.deflate(stroke / 2), 2.4, 1.05, false, paint);
    paint.color = const Color(0xFFEA4335);
    canvas.drawArc(rect.deflate(stroke / 2), 3.45, 1.45, false, paint);

    final centerY = size.height * 0.52;
    paint.color = const Color(0xFF4285F4);
    canvas.drawLine(
      Offset(size.width * 0.52, centerY),
      Offset(size.width * 0.92, centerY),
      paint,
    );
    canvas.drawLine(
      Offset(size.width * 0.92, centerY),
      Offset(size.width * 0.82, size.height * 0.75),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _InlineStatus extends StatelessWidget {
  const _InlineStatus({required this.message, required this.isError});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final background =
        isError ? colors.errorContainer : colors.primaryContainer;
    final foreground =
        isError ? colors.onErrorContainer : colors.onPrimaryContainer;
    return Semantics(
      liveRegion: true,
      container: true,
      label: isError ? 'Error. $message' : message,
      child: ExcludeSemantics(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
          child: Text(
            message,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: foreground,
                ),
          ),
        ),
      ),
    );
  }
}
