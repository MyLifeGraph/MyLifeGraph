import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../../../core/theme/theme_mode_provider.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_page.dart';
import '../../../auth/presentation/providers/auth_providers.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  bool _isSigningOut = false;

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(authControllerProvider).valueOrNull;
    final profile = session?.profile;
    final themeMode = ref.watch(appThemeModeProvider);
    final lightModeEnabled = themeMode == ThemeMode.light;

    return AppPage(
      title: 'Settings',
      subtitle: 'Account and appearance',
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Profile', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: AppSpacing.md),
              _ProfileValue(label: 'Name', value: profile?.name),
              _ProfileValue(label: 'Email', value: profile?.email),
              _ProfileValue(label: 'Timezone', value: profile?.timezone),
              _ProfileValue(
                label: 'Account',
                value: session == null
                    ? null
                    : session.isGuestSession
                        ? 'Local guest'
                        : 'Synced account',
                isLast: true,
              ),
            ],
          ),
        ),
        AppCard(
          padding: EdgeInsets.zero,
          child: ListTile(
            leading: const Icon(Icons.tune_outlined),
            title: const Text('Setup and commitments'),
            subtitle: const Text(
              'Review goals, routine candidates, and fixed commitments.',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('${AppRoutes.onboarding}?edit=1'),
          ),
        ),
        AppCard(
          padding: EdgeInsets.zero,
          child: SwitchListTile(
            value: lightModeEnabled,
            onChanged: (value) {
              ref.read(appThemeModeProvider.notifier).setLightMode(value);
            },
            secondary: Icon(
              lightModeEnabled
                  ? Icons.light_mode_outlined
                  : Icons.dark_mode_outlined,
            ),
            title: const Text('Light mode'),
            subtitle: const Text('Applies until the app is restarted.'),
          ),
        ),
        AppCard(
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _isSigningOut ? null : _signOut,
              icon: _isSigningOut
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.logout_outlined),
              label: const Text('Sign out'),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _signOut() async {
    setState(() => _isSigningOut = true);
    try {
      await ref.read(authControllerProvider.notifier).signOut();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not sign out. Try again.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSigningOut = false);
      }
    }
  }
}

class _ProfileValue extends StatelessWidget {
  const _ProfileValue({
    required this.label,
    required this.value,
    this.isLast = false,
  });

  final String label;
  final String? value;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final displayValue = value?.trim();
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ),
          Expanded(
            child: Text(
              displayValue == null || displayValue.isEmpty
                  ? 'Not available'
                  : displayValue,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
        ],
      ),
    );
  }
}
