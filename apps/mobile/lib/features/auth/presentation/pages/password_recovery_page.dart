import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/navigation/app_routes.dart';
import '../providers/auth_providers.dart';

class PasswordRecoveryPage extends ConsumerStatefulWidget {
  const PasswordRecoveryPage({super.key});

  @override
  ConsumerState<PasswordRecoveryPage> createState() =>
      _PasswordRecoveryPageState();
}

class _PasswordRecoveryPageState extends ConsumerState<PasswordRecoveryPage> {
  final _passwordController = TextEditingController();
  final _confirmationController = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.lock_reset_outlined,
                          color: Theme.of(context).colorScheme.primary,
                          size: 40,
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        Text(
                          'Choose a new password',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          'This page is available only after opening a valid password-reset link. The new password is sent directly to Supabase Auth.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        TextField(
                          controller: _passwordController,
                          obscureText: true,
                          enabled: !_submitting,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.newPassword],
                          decoration: const InputDecoration(
                            labelText: 'New password',
                            helperText: 'Use at least 8 characters.',
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        TextField(
                          controller: _confirmationController,
                          obscureText: true,
                          enabled: !_submitting,
                          autofillHints: const [AutofillHints.newPassword],
                          onSubmitted: (_) => _submitting ? null : _submit(),
                          decoration: const InputDecoration(
                            labelText: 'Confirm new password',
                          ),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: AppSpacing.md),
                          Semantics(
                            liveRegion: true,
                            child: Text(
                              _error!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: AppSpacing.lg),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _submitting ? null : _submit,
                            icon: _submitting
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.check_outlined),
                            label: const Text('Update password'),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        SizedBox(
                          width: double.infinity,
                          child: TextButton(
                            onPressed: _submitting ? null : _cancel,
                            child: const Text('Cancel and return to login'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final password = _passwordController.text;
    if (password.length < 8) {
      setState(() => _error = 'Use a password with at least 8 characters.');
      return;
    }
    if (password != _confirmationController.text) {
      setState(() => _error = 'The passwords do not match.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final controller = ref.read(authControllerProvider.notifier);
      final completion =
          await controller.completePasswordRecovery(password: password);
      if (!mounted) return;
      final session = ref.read(authControllerProvider).valueOrNull;
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            completion == PasswordRecoveryCompletion.updated
                ? 'Password updated.'
                : 'Password updated. Sign in again to continue; local session refresh was unavailable.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      final recoveryStateSaved = controller.finalizePasswordRecovery();
      context.go(
        session == null
            ? AppRoutes.auth
            : session.requiresOnboarding
                ? AppRoutes.onboarding
                : AppRoutes.dashboard,
      );
      if (!await recoveryStateSaved && messenger.mounted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Password updated, but local recovery-state cleanup was not saved. If recovery opens again, cancel it and sign in with the new password.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error =
              'The password update could not be confirmed. Try signing in with the new password before requesting another reset link.';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Future<void> _cancel() async {
    setState(() => _submitting = true);
    try {
      await ref.read(authControllerProvider.notifier).signOut();
    } finally {
      if (mounted) {
        context.go(AppRoutes.auth);
      }
    }
  }
}
