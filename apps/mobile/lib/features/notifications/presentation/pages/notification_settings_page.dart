import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_page.dart';
import '../../domain/entities/notification_delivery.dart';
import '../providers/notifications_providers.dart';

class NotificationSettingsPage extends ConsumerStatefulWidget {
  const NotificationSettingsPage({super.key});

  @override
  ConsumerState<NotificationSettingsPage> createState() =>
      _NotificationSettingsPageState();
}

class _NotificationSettingsPageState
    extends ConsumerState<NotificationSettingsPage> {
  DateTime? _draftRevision;
  bool _dirty = false;
  bool _deliveryEnabled = false;
  bool _focusPrompt = true;
  bool _recoveryPrompt = true;
  bool _weeklySummary = true;
  bool _quietHoursEnabled = false;
  String _quietStartsAt = '22:00';
  String _quietEndsAt = '07:00';
  int _dailyLimit = 2;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(notificationSettingsProvider);
    final controller = ref.read(notificationSettingsProvider.notifier);
    final settings = state.settings;
    if (settings != null &&
        _draftRevision != settings.updatedAt &&
        !state.isSaving) {
      _applySettings(settings);
    }

    if (state.isLoading && settings == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error != null && settings == null) {
      return _NotificationSettingsLoadError(onRetry: controller.load);
    }
    if (settings == null) {
      return _NotificationSettingsLoadError(onRetry: controller.load);
    }
    final controlsEnabled = !state.isSaving &&
        !state.isLoading &&
        !state.requiresExactRetry &&
        !state.requiresReload;

    return AppPage(
      title: 'In-app notifications',
      subtitle: 'Explicit foreground delivery controls',
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile(
                key: const ValueKey('notification-delivery-consent'),
                contentPadding: EdgeInsets.zero,
                value: _deliveryEnabled,
                onChanged: controlsEnabled
                    ? (value) => setState(() {
                          _deliveryEnabled = value;
                          _dirty = true;
                        })
                    : null,
                title: const Text('Allow in-app delivery'),
                subtitle: const Text(
                  'Shows a banner only while MyLifeGraph is open. This is separate from your saved reminder preference.',
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'This does not enable browser, Android, email, or push notifications. The local scheduler creates only fixed, non-LLM copy after consent.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (settings.consentedAt != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  _deliveryEnabled
                      ? 'Consent is active.'
                      : 'In-app delivery is disabled; stored Inbox items remain available.',
                  key: const ValueKey('notification-consent-status'),
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ],
            ],
          ),
        ),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Categories',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.sm),
              _categorySwitch(
                key: 'notification-category-focus',
                title: 'Today focus prompt',
                subtitle: 'Available only when a current briefing exists.',
                value: _focusPrompt,
                enabled: controlsEnabled,
                onChanged: (value) => _setDraft(
                  () => _focusPrompt = value,
                ),
              ),
              _categorySwitch(
                key: 'notification-category-recovery',
                title: 'Recovery prompt',
                subtitle: 'Replaces the generic focus prompt on recovery days.',
                value: _recoveryPrompt,
                enabled: controlsEnabled,
                onChanged: (value) => _setDraft(
                  () => _recoveryPrompt = value,
                ),
              ),
              _categorySwitch(
                key: 'notification-category-weekly',
                title: 'Weekly review summary',
                subtitle: 'Only for the exact completed week on Monday.',
                value: _weeklySummary,
                enabled: controlsEnabled,
                onChanged: (value) => _setDraft(
                  () => _weeklySummary = value,
                ),
              ),
            ],
          ),
        ),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile(
                key: const ValueKey('notification-quiet-hours-enabled'),
                contentPadding: EdgeInsets.zero,
                value: _quietHoursEnabled,
                onChanged: controlsEnabled
                    ? (value) => _setDraft(
                          () => _quietHoursEnabled = value,
                        )
                    : null,
                title: const Text('Quiet hours'),
                subtitle: const Text('Uses your saved profile timezone.'),
              ),
              if (_quietHoursEnabled) ...[
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    OutlinedButton.icon(
                      key: const ValueKey('notification-quiet-start'),
                      onPressed: controlsEnabled
                          ? () => _chooseTime(isStart: true)
                          : null,
                      icon: const Icon(Icons.bedtime_outlined),
                      label: Text('Starts $_quietStartsAt'),
                    ),
                    OutlinedButton.icon(
                      key: const ValueKey('notification-quiet-end'),
                      onPressed: controlsEnabled
                          ? () => _chooseTime(isStart: false)
                          : null,
                      icon: const Icon(Icons.wb_sunny_outlined),
                      label: Text('Ends $_quietEndsAt'),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  const Expanded(child: Text('Daily generated-item limit')),
                  DropdownButton<int>(
                    key: const ValueKey('notification-daily-limit'),
                    value: _dailyLimit,
                    onChanged: controlsEnabled
                        ? (value) {
                            if (value != null) {
                              _setDraft(() => _dailyLimit = value);
                            }
                          }
                        : null,
                    items: [
                      for (var value = 1; value <= 5; value++)
                        DropdownMenuItem(value: value, child: Text('$value')),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
        if (state.error != null)
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  state.requiresExactRetry
                      ? 'The save result is unknown. Retry the exact same settings or reload before making another change.'
                      : 'Settings changed or could not be saved. Reload current settings before trying again.',
                  key: const ValueKey('notification-settings-error'),
                ),
                const SizedBox(height: AppSpacing.md),
                if (state.requiresExactRetry)
                  OutlinedButton.icon(
                    key: const ValueKey('notification-settings-exact-retry'),
                    onPressed: state.isSaving ? null : controller.retryExact,
                    icon: const Icon(Icons.replay_outlined),
                    label: const Text('Retry exact save'),
                  )
                else
                  OutlinedButton.icon(
                    onPressed: state.isSaving ? null : controller.load,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Reload settings'),
                  ),
              ],
            ),
          ),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            key: const ValueKey('notification-settings-save'),
            onPressed: controlsEnabled && _dirty ? _save : null,
            icon: state.isSaving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: const Text('Save notification settings'),
          ),
        ),
      ],
    );
  }

  Widget _categorySwitch({
    required String key,
    required String title,
    required String subtitle,
    required bool value,
    required bool enabled,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      key: ValueKey(key),
      contentPadding: EdgeInsets.zero,
      value: value,
      onChanged: enabled ? onChanged : null,
      title: Text(title),
      subtitle: Text(subtitle),
    );
  }

  void _applySettings(NotificationSettings settings) {
    _draftRevision = settings.updatedAt;
    _deliveryEnabled = settings.inAppDeliveryEnabled;
    _focusPrompt = settings.categories.focusPrompt;
    _recoveryPrompt = settings.categories.recoveryPrompt;
    _weeklySummary = settings.categories.weeklySummary;
    _quietHoursEnabled = settings.quietHours != null;
    _quietStartsAt = settings.quietHours?.startsAt ?? '22:00';
    _quietEndsAt = settings.quietHours?.endsAt ?? '07:00';
    _dailyLimit = settings.dailyLimit;
    _dirty = false;
  }

  void _setDraft(VoidCallback update) {
    setState(() {
      update();
      _dirty = true;
    });
  }

  Future<void> _chooseTime({required bool isStart}) async {
    final current = _parseTime(isStart ? _quietStartsAt : _quietEndsAt);
    final chosen = await showTimePicker(context: context, initialTime: current);
    if (!mounted || chosen == null) return;
    final value = _formatTime(chosen);
    _setDraft(() {
      if (isStart) {
        _quietStartsAt = value;
      } else {
        _quietEndsAt = value;
      }
    });
  }

  Future<void> _save() async {
    if (_quietHoursEnabled && _quietStartsAt == _quietEndsAt) {
      _showMessage('Quiet hours need different start and end times.');
      return;
    }
    final settings = ref.read(notificationSettingsProvider).settings;
    if (settings == null) return;
    if (_deliveryEnabled && !settings.inAppDeliveryEnabled) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Allow in-app notifications?'),
          content: const Text(
            'This is new delivery permission. Your existing reminder preference did not grant it. MyLifeGraph may show fixed, privacy-safe banners while the app is open; no push, email, browser, or Android notification is enabled.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const ValueKey('notification-consent-confirm'),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Allow in-app only'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    final saved = await ref.read(notificationSettingsProvider.notifier).save(
          inAppDeliveryEnabled: _deliveryEnabled,
          categories: NotificationCategories(
            focusPrompt: _focusPrompt,
            recoveryPrompt: _recoveryPrompt,
            weeklySummary: _weeklySummary,
          ),
          quietHours: _quietHoursEnabled
              ? NotificationQuietHours(
                  startsAt: _quietStartsAt,
                  endsAt: _quietEndsAt,
                )
              : null,
          dailyLimit: _dailyLimit,
        );
    if (mounted && saved) _showMessage('Notification settings saved.');
  }

  TimeOfDay _parseTime(String value) {
    final parts = value.split(':');
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }

  String _formatTime(TimeOfDay value) =>
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _NotificationSettingsLoadError extends StatelessWidget {
  const _NotificationSettingsLoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 36),
            const SizedBox(height: AppSpacing.md),
            const Text('Could not load notification settings.'),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
