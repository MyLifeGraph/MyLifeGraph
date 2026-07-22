import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/capabilities/app_surface_capabilities.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../../../core/theme/theme_mode_provider.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_page.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../deadline_plans/presentation/providers/deadline_plan_providers.dart';
import '../../domain/account_settings.dart';
import '../providers/account_settings_providers.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  bool _isSigningOut = false;
  bool _isSavingTimezone = false;
  bool _isSavingPreparationBudget = false;
  bool _isExporting = false;
  bool _isDeleting = false;

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(authControllerProvider).valueOrNull;
    final profile = session?.profile;
    final capabilities = ref.watch(appSurfaceCapabilitiesProvider);
    final themeMode = ref.watch(appThemeModeProvider);
    final lightModeEnabled = themeMode == ThemeMode.light;
    final syncedAccount =
        session?.isAuthenticated == true && capabilities.canUseSyncedExecution;
    final profileTimezone = capabilities.isLocalDemo && profile != null
        ? 'Device local (${DateTime.now().timeZoneName})'
        : profile?.timezone;

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
              _ProfileValue(label: 'Timezone', value: profileTimezone),
              _ProfileValue(
                label: 'Account',
                value: session == null
                    ? null
                    : session.isGuestSession
                        ? 'Local guest'
                        : 'Synced account',
                isLast: true,
              ),
              const SizedBox(height: AppSpacing.md),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: syncedAccount && !_isSavingTimezone
                      ? _chooseTimezone
                      : null,
                  icon: _isSavingTimezone
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.public_outlined),
                  label: Text(
                    syncedAccount
                        ? 'Change timezone'
                        : 'Local dates follow this device',
                  ),
                ),
              ),
              if (!syncedAccount) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  capabilities.isLocalDemo
                      ? 'Guest/demo capture dates use this device clock; no account timezone is stored.'
                      : 'Timezone changes are available only for a synced account.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
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
          child: ListTile(
            key: const ValueKey('daily-preparation-budget-setting'),
            enabled: syncedAccount && !_isSavingPreparationBudget,
            leading: _isSavingPreparationBudget
                ? const SizedBox.square(
                    dimension: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.speed_outlined),
            title: const Text('Daily preparation budget'),
            subtitle: Text(
              !syncedAccount
                  ? 'Available only for a synced account.'
                  : profile?.dailyPreparationBudgetMinutes == null
                      ? 'Not set. Existing per-plan limits still apply.'
                      : '${_formatMinutes(profile!.dailyPreparationBudgetMinutes!)} total per day across confirmed preparation plans.',
            ),
            trailing: syncedAccount && !_isSavingPreparationBudget
                ? const Icon(Icons.edit_outlined)
                : null,
            onTap: syncedAccount && !_isSavingPreparationBudget
                ? _chooseDailyPreparationBudget
                : null,
          ),
        ),
        AppCard(
          padding: EdgeInsets.zero,
          child: ListTile(
            key: const ValueKey('settings-inbox-entry'),
            leading: const Icon(Icons.inbox_outlined),
            title: const Text('Inbox'),
            subtitle: const Text(
              'Read saved notifications and manage their read or dismissed state.',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go(AppRoutes.alerts),
          ),
        ),
        AppCard(
          padding: EdgeInsets.zero,
          child: ListTile(
            leading: const Icon(Icons.notifications_active_outlined),
            title: const Text('In-app reminders'),
            subtitle: Text(
              syncedAccount
                  ? 'Allow banners while the app is open and choose what may appear.'
                  : 'In-app banners are available only for a synced account.',
            ),
            trailing: syncedAccount ? const Icon(Icons.chevron_right) : null,
            onTap: syncedAccount
                ? () => context.go(AppRoutes.notificationSettings)
                : null,
          ),
        ),
        if (capabilities.canShowCoachSurface)
          AppCard(
            padding: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(Icons.forum_outlined),
              title: const Text('Coach'),
              subtitle: const Text(
                'Development preview only. Cannot change your data.',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.go(AppRoutes.coach),
            ),
          ),
        AppCard(
          padding: EdgeInsets.zero,
          child: ListTile(
            leading: const Icon(Icons.calendar_month_outlined),
            title: const Text('Calendar import (optional)'),
            subtitle: const Text(
              'Import a selected .ics file as a read-only local copy.',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go(AppRoutes.calendarIntegration),
          ),
        ),
        AppCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              ListTile(
                enabled: syncedAccount && !_isExporting && !_isDeleting,
                leading: _isExporting
                    ? const SizedBox.square(
                        dimension: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.download_outlined),
                title: const Text('Export data'),
                subtitle: Text(
                  syncedAccount
                      ? 'Save or share a JSON copy of your account data.'
                      : 'Available only for a synced account.',
                ),
                onTap: syncedAccount && !_isExporting && !_isDeleting
                    ? _exportData
                    : null,
              ),
              const Divider(height: 1),
              ListTile(
                enabled: syncedAccount && !_isDeleting && !_isExporting,
                leading: _isDeleting
                    ? const SizedBox.square(
                        dimension: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        Icons.delete_forever_outlined,
                        color: syncedAccount
                            ? Theme.of(context).colorScheme.error
                            : null,
                      ),
                title: const Text('Delete account'),
                subtitle: Text(
                  syncedAccount
                      ? 'Permanently delete your account and owned data. Requires a sign-in within the last 15 minutes.'
                      : 'A local guest has no synced account to delete.',
                ),
                onTap: syncedAccount && !_isDeleting && !_isExporting
                    ? _confirmDeleteAccount
                    : null,
              ),
            ],
          ),
        ),
        AppCard(
          padding: EdgeInsets.zero,
          child: SwitchListTile(
            value: lightModeEnabled,
            onChanged: _setLightMode,
            secondary: Icon(
              lightModeEnabled
                  ? Icons.light_mode_outlined
                  : Icons.dark_mode_outlined,
            ),
            title: const Text('Light mode'),
            subtitle: const Text('Saved on this device.'),
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

  Future<void> _chooseTimezone() async {
    final profile = ref.read(authControllerProvider).valueOrNull?.profile;
    if (profile == null) return;
    final timezone = await showDialog<String>(
      context: context,
      builder: (context) => _TimezoneDialog(current: profile.timezone),
    );
    if (!mounted || timezone == null || timezone == profile.timezone) return;
    final accountRepository = ref.read(accountSettingsRepositoryProvider);
    final authController = ref.read(authControllerProvider.notifier);
    setState(() => _isSavingTimezone = true);
    try {
      final saved = await accountRepository.updateTimezone(timezone);
      authController.updateProfileTimezone(saved);
      if (mounted) {
        _showMessage('Timezone updated to $saved.');
      }
    } on AccountTimezoneRejectedException {
      if (mounted) {
        _showMessage(
          'Timezone was not recognized. Choose another IANA timezone.',
        );
      }
    } on AccountProfileUpdateOutcomeUnknownException {
      if (mounted) {
        _showMessage(
          'Timezone update could not be confirmed. Select the same timezone again to retry safely, or sign in again to verify it before choosing another.',
        );
      }
    } catch (_) {
      if (mounted) {
        _showMessage('Could not update the timezone. Try again.');
      }
    } finally {
      if (mounted) setState(() => _isSavingTimezone = false);
    }
  }

  Future<void> _chooseDailyPreparationBudget() async {
    final profile = ref.read(authControllerProvider).valueOrNull?.profile;
    if (profile == null) return;
    final choice = await showDialog<_PreparationBudgetChoice>(
      context: context,
      builder: (_) => _PreparationBudgetDialog(
        current: profile.dailyPreparationBudgetMinutes,
      ),
    );
    if (!mounted ||
        choice == null ||
        choice.minutes == profile.dailyPreparationBudgetMinutes) {
      return;
    }
    final repository = ref.read(accountSettingsRepositoryProvider);
    final authController = ref.read(authControllerProvider.notifier);
    setState(() => _isSavingPreparationBudget = true);
    try {
      final saved =
          await repository.updateDailyPreparationBudget(choice.minutes);
      authController.updateDailyPreparationBudget(saved);
      ref.invalidate(preparationWorkloadProvider);
      if (mounted) {
        _showMessage(
          saved == null
              ? 'Account-wide preparation budget removed.'
              : 'Daily preparation budget set to ${_formatMinutes(saved)}.',
        );
      }
    } on AccountPreparationBudgetRejectedException {
      if (mounted) {
        _showMessage('Choose 25 to 480 minutes in five-minute steps.');
      }
    } on AccountPreparationBudgetUpdateOutcomeUnknownException {
      if (mounted) {
        _showMessage(
          'The budget update could not be confirmed. Retry the same value or sign in again before choosing another.',
        );
      }
    } catch (_) {
      if (mounted) {
        _showMessage('Could not update the preparation budget. Try again.');
      }
    } finally {
      if (mounted) setState(() => _isSavingPreparationBudget = false);
    }
  }

  Future<void> _exportData() async {
    final accountRepository = ref.read(accountSettingsRepositoryProvider);
    final exportSaver = ref.read(accountExportSaverProvider);
    final sharePositionOrigin = _sharePositionOrigin();
    setState(() => _isExporting = true);
    try {
      final export = await accountRepository.exportAccount();
      if (!mounted) return;
      final result = await exportSaver.save(
        suggestedName: _exportFileName(DateTime.now().toUtc()),
        export: export,
        sharePositionOrigin: sharePositionOrigin,
      );
      if (!mounted) return;
      _showMessage(
        switch (result) {
          AccountExportSaveResult.saved => 'Account export saved.',
          AccountExportSaveResult.shared =>
            'Account export handoff opened on this device.',
          AccountExportSaveResult.cancelled =>
            'Export cancelled. No destination was selected.',
          AccountExportSaveResult.shareDismissed =>
            'Share dismissed. No destination was selected; the platform may retain a temporary protected cache copy until cleanup.',
        },
      );
    } on AccountExportTooLargeException {
      if (mounted) {
        _showMessage(
          'This account exceeds the V1 export limits. Retrying unchanged will not help; reduce deletable history or request a larger export workflow.',
        );
      }
    } catch (_) {
      if (mounted) {
        _showMessage('Could not export account data. Try again.');
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Rect? _sharePositionOrigin() {
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return null;
    }
    return renderObject.localToGlobal(Offset.zero) & renderObject.size;
  }

  Future<void> _confirmDeleteAccount() async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (_) => const _DeleteAccountDialog(),
        ) ??
        false;
    if (!mounted || !confirmed) return;
    final accountRepository = ref.read(accountSettingsRepositoryProvider);
    final authController = ref.read(authControllerProvider.notifier);
    final authNotice = ref.read(authNoticeProvider.notifier);
    setState(() => _isDeleting = true);
    try {
      await accountRepository.deleteAccount();
    } on AccountRecentAuthenticationRequiredException {
      if (mounted) {
        _showMessage(
          'For safety, sign out and sign in again, then return here to delete the account.',
        );
        setState(() => _isDeleting = false);
      }
      return;
    } on AccountDeletionOutcomeUnknownException {
      authNotice.state = const AuthNotice(
        'Deletion could not be confirmed. Sign in again; if the account remains, retry deletion.',
        isError: true,
      );
      try {
        await authController.finalizeDeletedAccount();
      } catch (_) {
        // The controller still clears the local session in its finally block.
      }
      if (mounted) setState(() => _isDeleting = false);
      return;
    } catch (_) {
      if (mounted) {
        _showMessage('Could not delete the account. You remain signed in.');
      }
      if (mounted) setState(() => _isDeleting = false);
      return;
    }
    authNotice.state = const AuthNotice(
      'Account and canonical synced data deleted.',
    );
    try {
      await authController.finalizeDeletedAccount();
    } catch (_) {
      if (mounted) {
        _showMessage(
          'The account was deleted and the local session was closed. Remote sign-out cleanup could not be confirmed.',
        );
      }
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  Future<void> _setLightMode(bool enabled) async {
    final controller = ref.read(appThemeModeProvider.notifier);
    final saved = await controller.setLightMode(enabled);
    if (!saved && mounted) {
      _showMessage('Could not save the appearance setting. Try again.');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  Future<void> _signOut() async {
    final authController = ref.read(authControllerProvider.notifier);
    setState(() => _isSigningOut = true);
    try {
      await authController.signOut();
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

String _exportFileName(DateTime utcNow) {
  String two(int value) => value.toString().padLeft(2, '0');
  return 'mylifegraph-export-${utcNow.year}-${two(utcNow.month)}-'
      '${two(utcNow.day)}.json';
}

String _formatMinutes(int minutes) {
  final hours = minutes ~/ 60;
  final remainder = minutes % 60;
  if (hours == 0) return '$minutes min';
  if (remainder == 0) return '${hours}h';
  return '${hours}h ${remainder}m';
}

class _TimezoneDialog extends StatefulWidget {
  const _TimezoneDialog({required this.current});

  final String current;

  @override
  State<_TimezoneDialog> createState() => _TimezoneDialogState();
}

class _TimezoneDialogState extends State<_TimezoneDialog> {
  static const _customValue = '__custom_iana_timezone__';
  String? _selected;
  late final TextEditingController _customController;

  @override
  void initState() {
    super.initState();
    final curated = isSupportedAccountTimezone(widget.current);
    _selected = curated ? widget.current : _customValue;
    _customController = TextEditingController(
      text: curated ? '' : widget.current,
    );
  }

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: const Text('Account timezone'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _selected,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'IANA timezone',
                helperText:
                    'Used for local dates, briefings, reviews, and budgets.',
              ),
              items: [
                for (final timezone in supportedAccountTimezones)
                  DropdownMenuItem(value: timezone, child: Text(timezone)),
                const DropdownMenuItem(
                  value: _customValue,
                  child: Text('Enter another IANA timezone…'),
                ),
              ],
              onChanged: (value) => setState(() => _selected = value),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'New rule-based proposals and recurring commitments use this timezone. Existing preparation reservations keep their saved instants; imported calendar files do not refresh automatically.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (_selected == _customValue) ...[
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _customController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Custom IANA timezone',
                  hintText: 'Africa/Johannesburg',
                  helperText: 'The account service validates the zone.',
                ),
                onChanged: (_) => setState(() {}),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: !isValidAccountTimezone(_selectedTimezone)
              ? null
              : () => Navigator.of(context).pop(_selectedTimezone.trim()),
          child: const Text('Save timezone'),
        ),
      ],
    );
  }

  String get _selectedTimezone =>
      _selected == _customValue ? _customController.text : _selected ?? '';
}

class _PreparationBudgetChoice {
  const _PreparationBudgetChoice(this.minutes);

  final int? minutes;
}

class _PreparationBudgetDialog extends StatefulWidget {
  const _PreparationBudgetDialog({required this.current});

  final int? current;

  @override
  State<_PreparationBudgetDialog> createState() =>
      _PreparationBudgetDialogState();
}

class _PreparationBudgetDialogState extends State<_PreparationBudgetDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.current?.toString() ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final minutes = int.tryParse(_controller.text.trim());
    final valid = minutes != null && isValidDailyPreparationBudget(minutes);
    return AlertDialog(
      scrollable: true,
      title: const Text('Daily preparation budget'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Set the most preparation time you want reserved per day across all confirmed exam and assignment plans.',
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'This is a transparent rule, not an AI estimate. Existing reservations are not changed; days above a new lower budget are marked Needs review.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              key: const ValueKey('daily-preparation-budget-input'),
              controller: _controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Total preparation minutes per day',
                helperText: '25–480 minutes, in five-minute steps.',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [
                for (final preset in const [60, 120, 180, 240, 360, 480])
                  ChoiceChip(
                    label: Text(_formatMinutes(preset)),
                    selected: minutes == preset,
                    onSelected: (_) {
                      _controller.text = '$preset';
                      setState(() {});
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        if (widget.current != null)
          TextButton(
            onPressed: () => Navigator.of(context).pop(
              const _PreparationBudgetChoice(null),
            ),
            child: const Text('Remove budget'),
          ),
        FilledButton(
          onPressed: valid
              ? () => Navigator.of(context).pop(
                    _PreparationBudgetChoice(minutes),
                  )
              : null,
          child: const Text('Save budget'),
        ),
      ],
    );
  }
}

class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog();

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final _confirmationController = TextEditingController();

  @override
  void dispose() {
    _confirmationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final confirmed = _confirmationController.text == 'DELETE';
    return AlertDialog(
      scrollable: true,
      title: const Text('Delete account permanently?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'This permanently deletes the synced account and owned data. This action cannot be undone. For safety, you must have signed in within the last 15 minutes.',
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _confirmationController,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Type DELETE to confirm',
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: confirmed ? () => Navigator.of(context).pop(true) : null,
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
          ),
          child: const Text('Delete account'),
        ),
      ],
    );
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
