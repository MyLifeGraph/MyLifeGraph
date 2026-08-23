import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/widgets/app_page.dart';
import '../../../../core/widgets/app_surface.dart';
import 'package:my_life_graph/composition/auth_providers.dart';

class PilotParticipationPage extends ConsumerStatefulWidget {
  const PilotParticipationPage({super.key});

  @override
  ConsumerState<PilotParticipationPage> createState() =>
      _PilotParticipationPageState();
}

class _PilotParticipationPageState
    extends ConsumerState<PilotParticipationPage> {
  bool _confirmed = false;
  bool _submitting = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(appConfigProvider);
    final session = ref.watch(authControllerProvider).valueOrNull;
    final canSubmit = _confirmed &&
        !_submitting &&
        session != null &&
        !session.isGuestSession;
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: AppPage(
          title: 'Confirm pilot participation',
          subtitle: 'Required before Setup or synced product access.',
          showBackForFallback: false,
          maxWidth: 680,
          children: [
            AppSurface(
              variant: AppSurfaceVariant.accent,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Adult-only evaluation',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Your account may store real mood, sleep, stress, study, planning, calendar, reflection, and Coach data. Project and incident contact: ${config.pilotContactEmail}.',
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: _submitting
                          ? null
                          : () => context.push(AppRoutes.pilotPrivacyNotice),
                      child: const Text('Read pilot privacy notice'),
                    ),
                  ),
                  CheckboxListTile(
                    value: _confirmed,
                    onChanged: _submitting
                        ? null
                        : (value) {
                            setState(() {
                              _confirmed = value ?? false;
                              _error = null;
                            });
                          },
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text('I confirm that I am 18 or older'),
                    subtitle: const Text(
                      'Only the current notice version and acceptance time are saved. No birth date is collected.',
                    ),
                  ),
                ],
              ),
            ),
            if (_error != null)
              AppSurface(
                variant: AppSurfaceVariant.danger,
                child: Semantics(
                  liveRegion: true,
                  child: Text(_error!),
                ),
              ),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: canSubmit ? _accept : null,
                icon: _submitting
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(AppIcons.check),
                label: const Text('Continue to MyLifeGraph'),
              ),
            ),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _submitting ? null : _signOut,
                icon: const Icon(AppIcons.logoutOutlined),
                label: const Text('Sign out'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _accept() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref
          .read(authControllerProvider.notifier)
          .acceptCurrentPilotParticipation();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error =
            'Your confirmation could not be recorded. Your account remains blocked from Setup and saved product data. Try again unchanged or sign out.';
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _signOut() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref.read(authControllerProvider.notifier).signOut();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Sign-out could not be confirmed. Close and reopen the app.';
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}
