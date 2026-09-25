import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../composition/push_providers.dart';
import '../../../../core/platform/push_platform.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_page.dart';

class PushSettingsPage extends ConsumerStatefulWidget {
  const PushSettingsPage({super.key});
  @override
  ConsumerState<PushSettingsPage> createState() => _PushSettingsPageState();
}

class _PushSettingsPageState extends ConsumerState<PushSettingsPage> {
  Map<String, dynamic>? _draft;
  int? _revision;
  bool _dirty = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(pushProvider.notifier).refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(pushProvider);
    final cloud = state.cloud;
    if (cloud != null && !_dirty && !state.busy) {
      _draft = {
        for (final key in [
          'enabled',
          'sleep',
          'deadlines',
          'patterns',
          if (cloud.settings.containsKey('morning')) ...[
            'morning',
            'evening',
            'morning_time',
            'evening_time',
          ],
          'quiet_start',
          'quiet_end',
        ])
          key: cloud.settings[key],
      };
      _revision = cloud.revision;
    }
    final draft = _draft;
    final editable = !state.busy && state.error == null && draft != null;
    return AppPage(
      title: 'Push reminders',
      backFallback: '/settings',
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (state.busy) const LinearProgressIndicator(),
              if (state.error != null)
                Text(
                  state.error!,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              if (cloud != null && !cloud.available)
                const Text('Push is not activated on this server yet.'),
              if (!PushPlatform.supported)
                const Text(
                  'Enable on your Android phone. You can turn reminders off here.',
                ),
              if (PushPlatform.supported && !state.configured && !state.busy)
                const Text('Install a push-enabled APK to connect this phone.'),
              if (draft != null) ...[
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Important reminders'),
                  subtitle: const Text(
                    'Android notifications, even when the app is closed.',
                  ),
                  value: draft['enabled'] == true,
                  onChanged:
                      editable &&
                          (draft['enabled'] == true ||
                              (PushPlatform.supported &&
                                  state.configured &&
                                  cloud!.available))
                      ? (value) {
                          if (value &&
                              (!PushPlatform.supported ||
                                  !state.configured ||
                                  !cloud!.available)) {
                            return;
                          }
                          setState(() {
                            draft['enabled'] = value;
                            _dirty = true;
                          });
                        }
                      : null,
                ),
                for (final entry in {
                  'sleep': 'Before bedtime',
                  'deadlines': "Today's deadlines",
                  'patterns': 'Important patterns',
                  if (draft.containsKey('morning')) ...{
                    'morning': 'Morning check-in',
                    'evening': 'Evening check-in',
                  },
                }.entries)
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Row(
                      children: [
                        Expanded(child: Text(entry.value)),
                        if (entry.key == 'morning' || entry.key == 'evening')
                          TextButton(
                            onPressed: editable
                                ? () => _pickTime('${entry.key}_time')
                                : null,
                            child: Text(draft['${entry.key}_time'] as String),
                          ),
                      ],
                    ),
                    value: draft[entry.key] == true,
                    onChanged: editable
                        ? (value) => setState(() {
                            draft[entry.key] = value == true;
                            _dirty = true;
                          })
                        : null,
                  ),
                Row(
                  children: [
                    const Expanded(child: Text('Quiet hours')),
                    TextButton(
                      onPressed: editable
                          ? () => _pickTime('quiet_start')
                          : null,
                      child: Text(draft['quiet_start'] as String),
                    ),
                    const Text('–'),
                    TextButton(
                      onPressed: editable ? () => _pickTime('quiet_end') : null,
                      child: Text(draft['quiet_end'] as String),
                    ),
                  ],
                ),
                Text(
                  draft.containsKey('morning')
                      ? 'Up to 2 check-in reminders plus 2 other reminders per 24 hours. Patterns once per 30 days. Saved check-ins are skipped.'
                      : 'Up to 2 reminders per 24 hours. Patterns once per 30 days.',
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    FilledButton(
                      onPressed: editable && _dirty ? _save : null,
                      child: const Text('Save'),
                    ),
                    TextButton(
                      onPressed: state.busy
                          ? null
                          : () {
                              setState(() => _dirty = false);
                              ref.read(pushProvider.notifier).refresh();
                            },
                      child: const Text('Reload'),
                    ),
                    if (PushPlatform.supported)
                      TextButton(
                        onPressed: () =>
                            const PushPlatform().call<void>('openSettings'),
                        child: const Text('Android permissions'),
                      ),
                  ],
                ),
              ] else if (!state.busy)
                TextButton(
                  onPressed: () => ref.read(pushProvider.notifier).refresh(),
                  child: const Text('Reload'),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _pickTime(String key) async {
    final pieces = (_draft![key] as String).split(':');
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: int.parse(pieces[0]),
        minute: int.parse(pieces[1]),
      ),
    );
    if (picked != null && mounted) {
      setState(() {
        _draft![key] =
            '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
        _dirty = true;
      });
    }
  }

  Future<void> _save() async {
    if (_draft!['enabled'] == true &&
        ref.read(pushProvider).cloud?.enabled != true) {
      final yes = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Allow push reminders?'),
          content: const Text(
            'Google Firebase delivers brief reminders to this Android phone. A device identifier is linked to your account. Private check-in details are not sent. Turn this off here any time.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Not now'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Allow'),
            ),
          ],
        ),
      );
      if (yes != true || !mounted) return;
    }
    await ref.read(pushProvider.notifier).save(Map.of(_draft!), _revision!);
    if (mounted && ref.read(pushProvider).error == null) {
      setState(() => _dirty = false);
    }
  }
}
