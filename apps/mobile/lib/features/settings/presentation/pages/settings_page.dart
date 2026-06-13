import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../../../core/theme/theme_mode_provider.dart';
import '../../../auth/presentation/providers/auth_providers.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  String _name = 'Demo Coach User';
  String _email = 'demo@personal-coach.local';
  String _timezone = 'Europe/Berlin';
  final bool _guestMode = true;
  bool _weeklyReview = true;
  bool _dailyReminders = true;
  bool _sleepAlerts = true;
  bool _screenTimeAlerts = true;
  bool _deadlineAlerts = true;
  bool _memoryEnabled = true;
  bool _biometricLock = false;
  double _coachIntensity = 0.65;
  String _coachTone = 'Balanced';
  final int _timetableBlocks = 1;

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(appThemeModeProvider);
    final lightModeEnabled = themeMode == ThemeMode.light;
    final session = ref.watch(authControllerProvider).valueOrNull;
    final profile = session?.profile;
    final displayName = profile?.name ?? _name;
    final displayEmail = profile?.email ?? _email;
    final isGuestMode = session?.isGuestSession ?? _guestMode;
    final roleLabel =
        profile?.role.databaseValue ?? (isGuestMode ? 'guest' : 'user');

    return SafeArea(
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.xl,
            ),
            sliver: SliverList.list(
              children: [
                _SettingsHeader(lightModeEnabled: lightModeEnabled),
                const SizedBox(height: AppSpacing.xl),
                _ProfileSummary(
                  name: displayName,
                  email: displayEmail,
                  status: roleLabel,
                ),
                const SizedBox(height: AppSpacing.lg),
                _SettingsPanel(
                  title: 'Preferences',
                  children: [
                    _SettingToggleRow(
                      icon: lightModeEnabled
                          ? Icons.light_mode_outlined
                          : Icons.dark_mode_outlined,
                      title: 'Light mode',
                      subtitle: 'Dark remains the default on app start.',
                      valueLabel: lightModeEnabled ? 'Light' : 'Dark',
                      value: lightModeEnabled,
                      onChanged: (value) {
                        ref
                            .read(appThemeModeProvider.notifier)
                            .setLightMode(value);
                        _showSnack(
                          value
                              ? 'Light mode enabled for this session.'
                              : 'Dark mode restored.',
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                _SettingsPanel(
                  title: 'Account',
                  children: [
                    _SettingActionRow(
                      icon: Icons.person_outline,
                      title: 'Profile',
                      subtitle: 'Name, email and timezone',
                      onTap: _openProfileEditor,
                    ),
                    _SettingActionRow(
                      icon: Icons.key_outlined,
                      title: 'Google login',
                      subtitle: isGuestMode
                          ? 'Prepared for Supabase OAuth'
                          : 'Connected for this session',
                      onTap: _connectGoogle,
                    ),
                    _SettingActionRow(
                      icon: Icons.mail_outline,
                      title: 'Email preferences',
                      subtitle: _emailPreferenceSummary,
                      onTap: _openEmailPreferences,
                    ),
                    _SettingActionRow(
                      icon: Icons.logout_outlined,
                      title: 'Sign out',
                      subtitle: isGuestMode
                          ? 'Leave guest session'
                          : 'Return to auth screen',
                      onTap: _signOut,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                _SettingsPanel(
                  title: 'Your data',
                  children: [
                    _DataGrid(
                      stats: [
                        const _DataStat('11', 'Daily logs'),
                        _DataStat('$_timetableBlocks', 'Timetable blocks'),
                        _DataStat(_memoryEnabled ? '4' : '0', 'Memory entries'),
                        const _DataStat('2', 'Insights'),
                        const _DataStat('17', 'Notifications'),
                        const _DataStat('4', 'Coach messages'),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _FullWidthAction(
                      icon: Icons.file_download_outlined,
                      label: 'Export data',
                      onTap: _exportData,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    _FullWidthAction(
                      icon: Icons.storage_outlined,
                      label: 'Edit timetable setup',
                      filled: true,
                      onTap: _openTimetableSetup,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                _SettingsPanel(
                  title: 'App controls',
                  children: [
                    _SettingActionRow(
                      icon: Icons.notifications_none,
                      iconColor: const Color(0xFFFFA72F),
                      title: 'Alert rules',
                      subtitle: 'Sleep, screen time, deadlines',
                      onTap: _openAlertRules,
                    ),
                    _SettingActionRow(
                      icon: Icons.smart_toy_outlined,
                      iconColor: const Color(0xFFFFA72F),
                      title: 'Coach behavior',
                      subtitle: 'Tone and reminder intensity',
                      onTap: _openCoachBehavior,
                    ),
                    _SettingActionRow(
                      icon: Icons.lock_outline,
                      iconColor: const Color(0xFFFFA72F),
                      title: 'Privacy',
                      subtitle: 'Memory and stored context',
                      onTap: _openPrivacy,
                    ),
                    _SettingActionRow(
                      icon: Icons.shield_outlined,
                      iconColor: const Color(0xFFFFA72F),
                      title: 'Security',
                      subtitle: 'Supabase Auth later',
                      onTap: _openSecurity,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String get _emailPreferenceSummary {
    if (_weeklyReview && _dailyReminders) {
      return 'Weekly review and reminders';
    }
    if (_weeklyReview) {
      return 'Weekly review only';
    }
    if (_dailyReminders) {
      return 'Reminders only';
    }
    return 'Email updates paused';
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _openProfileEditor() async {
    final nameController = TextEditingController(text: _name);
    final emailController = TextEditingController(text: _email);
    final timezoneController = TextEditingController(text: _timezone);
    final result = await showModalBottomSheet<_ProfileDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _SettingsColors.panel(context),
      builder: (context) {
        return _SettingsSheet(
          title: 'Profile',
          child: Column(
            children: [
              _SheetField(label: 'Name', controller: nameController),
              _SheetField(label: 'Email', controller: emailController),
              _SheetField(label: 'Timezone', controller: timezoneController),
              const SizedBox(height: AppSpacing.md),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    Navigator.of(context).pop(
                      _ProfileDraft(
                        nameController.text.trim(),
                        emailController.text.trim(),
                        timezoneController.text.trim(),
                      ),
                    );
                  },
                  child: const Text('Save profile'),
                ),
              ),
            ],
          ),
        );
      },
    );

    if (result == null) {
      return;
    }

    setState(() {
      _name = result.name.isEmpty ? _name : result.name;
      _email = result.email.isEmpty ? _email : result.email;
      _timezone = result.timezone.isEmpty ? _timezone : result.timezone;
    });
    _showSnack('Profile updated.');
  }

  Future<void> _connectGoogle() async {
    try {
      await ref.read(authControllerProvider.notifier).signInWithGoogle();
    } catch (_) {
      _showSnack('Enable Google OAuth in Supabase first.');
    }
  }

  Future<void> _signOut() async {
    await ref.read(authControllerProvider.notifier).signOut();
    if (mounted) {
      context.go(AppRoutes.auth);
    }
  }

  Future<void> _openEmailPreferences() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: _SettingsColors.panel(context),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) => _SettingsSheet(
            title: 'Email preferences',
            child: Column(
              children: [
                _SheetSwitch(
                  title: 'Weekly review',
                  subtitle: 'Send a summary of patterns and completed tasks.',
                  value: _weeklyReview,
                  onChanged: (value) {
                    setState(() => _weeklyReview = value);
                    setSheetState(() {});
                  },
                ),
                _SheetSwitch(
                  title: 'Daily reminders',
                  subtitle: 'Send nudges for alerts and check-ins.',
                  value: _dailyReminders,
                  onChanged: (value) {
                    setState(() => _dailyReminders = value);
                    setSheetState(() {});
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openAlertRules() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: _SettingsColors.panel(context),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) => _SettingsSheet(
            title: 'Alert rules',
            child: Column(
              children: [
                _SheetSwitch(
                  title: 'Sleep debt warnings',
                  subtitle: 'Warn when recovery drops below your usual range.',
                  value: _sleepAlerts,
                  onChanged: (value) {
                    setState(() => _sleepAlerts = value);
                    setSheetState(() {});
                  },
                ),
                _SheetSwitch(
                  title: 'Screen time nudges',
                  subtitle: 'Flag high screen-time days before focus blocks.',
                  value: _screenTimeAlerts,
                  onChanged: (value) {
                    setState(() => _screenTimeAlerts = value);
                    setSheetState(() {});
                  },
                ),
                _SheetSwitch(
                  title: 'Deadline warnings',
                  subtitle: 'Create focus prompts before due dates.',
                  value: _deadlineAlerts,
                  onChanged: (value) {
                    setState(() => _deadlineAlerts = value);
                    setSheetState(() {});
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openCoachBehavior() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: _SettingsColors.panel(context),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) => _SettingsSheet(
            title: 'Coach behavior',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'Calm', label: Text('Calm')),
                    ButtonSegment(value: 'Balanced', label: Text('Balanced')),
                    ButtonSegment(value: 'Direct', label: Text('Direct')),
                  ],
                  selected: {_coachTone},
                  onSelectionChanged: (selection) {
                    setState(() => _coachTone = selection.first);
                    setSheetState(() {});
                  },
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'Reminder intensity',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Slider(
                  value: _coachIntensity,
                  onChanged: (value) {
                    setState(() => _coachIntensity = value);
                    setSheetState(() {});
                  },
                ),
                Text(
                  '${(_coachIntensity * 100).round()}%',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openPrivacy() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: _SettingsColors.panel(context),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) => _SettingsSheet(
            title: 'Privacy',
            child: Column(
              children: [
                _SheetSwitch(
                  title: 'Personal memory',
                  subtitle: 'Allow coach to use stored context.',
                  value: _memoryEnabled,
                  onChanged: (value) {
                    setState(() => _memoryEnabled = value);
                    setSheetState(() {});
                  },
                ),
                const SizedBox(height: AppSpacing.md),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () {
                      setState(() => _memoryEnabled = false);
                      setSheetState(() {});
                      _showSnack('Memory disabled and hidden locally.');
                    },
                    child: const Text('Clear local memory'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openSecurity() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: _SettingsColors.panel(context),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) => _SettingsSheet(
            title: 'Security',
            child: Column(
              children: [
                _SheetSwitch(
                  title: 'Biometric app lock',
                  subtitle: 'Prepared for mobile secure storage.',
                  value: _biometricLock,
                  onChanged: (value) {
                    setState(() => _biometricLock = value);
                    setSheetState(() {});
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openTimetableSetup() async {
    context.go('${AppRoutes.onboarding}?edit=1');
  }

  Future<void> _exportData() async {
    final payload = const JsonEncoder.withIndent('  ').convert({
      'profile': {
        'name': _name,
        'email': _email,
        'timezone': _timezone,
        'guestMode': _guestMode,
      },
      'preferences': {
        'themeMode': ref.read(appThemeModeProvider).name,
        'weeklyReview': _weeklyReview,
        'dailyReminders': _dailyReminders,
        'coachTone': _coachTone,
        'coachIntensity': _coachIntensity,
      },
      'alertRules': {
        'sleep': _sleepAlerts,
        'screenTime': _screenTimeAlerts,
        'deadlines': _deadlineAlerts,
      },
    });

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Export data'),
        content: SingleChildScrollView(
          child: SelectableText(payload),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _SettingsHeader extends StatelessWidget {
  const _SettingsHeader({required this.lightModeEnabled});

  final bool lightModeEnabled;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'APP SETTINGS',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      letterSpacing: 4,
                    ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'Settings',
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                      fontSize: 48,
                      height: 1,
                    ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'Account, data, privacy, appearance, and integrations.',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: _SettingsColors.mutedText(context),
                      height: 1.55,
                    ),
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        _IconTile(icon: lightModeEnabled ? Icons.light_mode : Icons.dark_mode),
      ],
    );
  }
}

class _ProfileSummary extends StatelessWidget {
  const _ProfileSummary({
    required this.name,
    required this.email,
    required this.status,
  });

  final String name;
  final String email;
  final String status;

  @override
  Widget build(BuildContext context) {
    return _SettingsSurface(
      child: Row(
        children: [
          Icon(
            Icons.person_outline,
            color: Theme.of(context).colorScheme.primary,
            size: 34,
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: Theme.of(context).textTheme.titleLarge),
                Text(email, style: Theme.of(context).textTheme.bodyLarge),
              ],
            ),
          ),
          _StatusPill(label: status),
        ],
      ),
    );
  }
}

class _SettingsPanel extends StatelessWidget {
  const _SettingsPanel({
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return _SettingsSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppSpacing.lg),
          ...children,
        ],
      ),
    );
  }
}

class _SettingActionRow extends StatelessWidget {
  const _SettingActionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.iconColor,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return _SettingRowShell(
      onTap: onTap,
      child: Row(
        children: [
          _SmallIconBox(icon: icon, color: iconColor),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: _RowText(title: title, subtitle: subtitle)),
          const Icon(Icons.chevron_right),
        ],
      ),
    );
  }
}

class _SettingToggleRow extends StatelessWidget {
  const _SettingToggleRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.valueLabel,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String valueLabel;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return _SettingRowShell(
      onTap: () => onChanged(!value),
      child: Row(
        children: [
          Expanded(child: _RowText(title: title, subtitle: subtitle)),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: _SettingsColors.button(context),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: _SettingsColors.border(context)),
            ),
            child: Row(
              children: [
                Icon(icon, size: 20),
                const SizedBox(width: AppSpacing.sm),
                Text(valueLabel, style: Theme.of(context).textTheme.labelLarge),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DataGrid extends StatelessWidget {
  const _DataGrid({required this.stats});

  final List<_DataStat> stats;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: stats.map((stat) {
            final width = (constraints.maxWidth - AppSpacing.md) / 2;
            return SizedBox(
              width: width,
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: _SettingsColors.row(context),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      stat.value,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    Text(
                      stat.label,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

class _FullWidthAction extends StatelessWidget {
  const _FullWidthAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.filled = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: filled
              ? _SettingsColors.row(context)
              : _SettingsColors.button(context),
          borderRadius: BorderRadius.circular(18),
          border: filled
              ? null
              : Border.all(color: _SettingsColors.border(context)),
        ),
        child: Row(
          children: [
            Icon(icon),
            const SizedBox(width: AppSpacing.md),
            Text(label, style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
      ),
    );
  }
}

class _SettingsSurface extends StatelessWidget {
  const _SettingsSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: _SettingsColors.panel(context),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: _SettingsColors.border(context), width: 2),
      ),
      child: child,
    );
  }
}

class _SettingRowShell extends StatelessWidget {
  const _SettingRowShell({
    required this.child,
    required this.onTap,
  });

  final Widget child;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: _SettingsColors.row(context),
            borderRadius: BorderRadius.circular(18),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _SmallIconBox extends StatelessWidget {
  const _SmallIconBox({required this.icon, this.color});

  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: _SettingsColors.button(context),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Icon(
        icon,
        color: color ?? Theme.of(context).colorScheme.primary,
      ),
    );
  }
}

class _IconTile extends StatelessWidget {
  const _IconTile({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        color: _SettingsColors.iconTile(context),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: _SettingsColors.border(context), width: 2),
      ),
      child: Icon(
        icon,
        color: Theme.of(context).colorScheme.primary,
        size: 34,
      ),
    );
  }
}

class _RowText extends StatelessWidget {
  const _RowText({
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: _SettingsColors.pill(context),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelLarge),
    );
  }
}

class _SettingsSheet extends StatelessWidget {
  const _SettingsSheet({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
          MediaQuery.viewInsetsOf(context).bottom + AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppSpacing.lg),
            child,
          ],
        ),
      ),
    );
  }
}

class _SheetField extends StatelessWidget {
  const _SheetField({
    required this.label,
    required this.controller,
  });

  final String label;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(labelText: label),
      ),
    );
  }
}

class _SheetSwitch extends StatelessWidget {
  const _SheetSwitch({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      value: value,
      onChanged: onChanged,
      title: Text(title),
      subtitle: Text(subtitle),
      contentPadding: EdgeInsets.zero,
    );
  }
}

class _DataStat {
  const _DataStat(this.value, this.label);

  final String value;
  final String label;
}

class _ProfileDraft {
  const _ProfileDraft(this.name, this.email, this.timezone);

  final String name;
  final String email;
  final String timezone;
}

class _SettingsColors {
  const _SettingsColors._();

  static bool _light(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light;

  static Color panel(BuildContext context) =>
      _light(context) ? const Color(0xFFFFFFFF) : const Color(0xFF122329);

  static Color row(BuildContext context) =>
      _light(context) ? const Color(0xFFEAF1F0) : const Color(0xFF202B32);

  static Color button(BuildContext context) =>
      _light(context) ? const Color(0xFFF7FAFA) : const Color(0xFF0D121A);

  static Color iconTile(BuildContext context) =>
      _light(context) ? const Color(0xFFE7F4F1) : const Color(0xFF15242A);

  static Color pill(BuildContext context) =>
      _light(context) ? const Color(0xFFE0E9E7) : const Color(0xFF2A323C);

  static Color border(BuildContext context) =>
      _light(context) ? const Color(0xFFD4E1DF) : const Color(0xFF2A424A);

  static Color mutedText(BuildContext context) =>
      _light(context) ? const Color(0xFF607078) : const Color(0xFFA8B5BE);
}
