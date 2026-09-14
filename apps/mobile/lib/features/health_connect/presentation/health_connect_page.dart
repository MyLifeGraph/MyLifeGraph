import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../composition/health_connect_providers.dart';
import '../../../core/capabilities/app_surface_capabilities.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_page.dart';

class HealthConnectPage extends ConsumerStatefulWidget {
  const HealthConnectPage({super.key});
  @override
  ConsumerState<HealthConnectPage> createState() => _HealthConnectPageState();
}

class _HealthConnectPageState extends ConsumerState<HealthConnectPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          ref.read(appSurfaceCapabilitiesProvider).canUseSyncedExecution) {
        ref.read(healthConnectProvider.notifier).load();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!ref.watch(appSurfaceCapabilitiesProvider).canUseSyncedExecution) {
      return const AppPage(
        title: 'Health Connect',
        children: [Text('Sign in to connect your watch.')],
      );
    }
    final view = ref.watch(healthConnectProvider);
    final controller = ref.read(healthConnectProvider.notifier);
    final cloud = view.cloud;
    final editable = !view.busy && view.error == null && cloud != null;
    final ownDevice = view.deviceId != null && cloud?.deviceId == view.deviceId;
    return AppPage(
      title: 'Health Connect',
      compactHeader: true,
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Your watch · optional',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.sm),
              const Text('Steps and sleep, kept separate from your check-ins.'),
              const SizedBox(height: AppSpacing.sm),
              const Text(
                'In Garmin Connect, enable Health Connect sharing first. Then allow access here on Android 14 or later.',
              ),
              const SizedBox(height: AppSpacing.md),
              if (view.busy) const LinearProgressIndicator(),
              if (view.error != null)
                Text(
                  view.error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (cloud != null) ...[
                Text(cloud.enabled ? 'Cloud sharing on' : 'Cloud sharing off'),
                if (cloud.lastSyncedAt != null)
                  Text(
                    'Last sync: ${MaterialLocalizations.of(context).formatShortDate(cloud.lastSyncedAt!.toLocal())} · ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(cloud.lastSyncedAt!.toLocal()))}',
                  ),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    if (view.supported &&
                        (!cloud.enabled || !ownDevice || !view.granted))
                      FilledButton(
                        onPressed: editable ? _connect : null,
                        child: Text(
                          cloud.enabled ? 'Reconnect this device' : 'Connect',
                        ),
                      ),
                    if (view.supported &&
                        cloud.enabled &&
                        ownDevice &&
                        view.granted)
                      FilledButton.icon(
                        onPressed: editable ? controller.sync : null,
                        icon: const Icon(AppIcons.refresh),
                        label: const Text('Sync now'),
                      ),
                    if (cloud.enabled)
                      OutlinedButton(
                        onPressed: editable
                            ? () => controller.disconnect()
                            : null,
                        child: const Text('Stop sharing'),
                      ),
                    TextButton(
                      onPressed: editable ? _delete : null,
                      child: const Text('Delete imported data'),
                    ),
                  ],
                ),
              ],
              TextButton.icon(
                onPressed: view.busy ? null : controller.load,
                icon: const Icon(AppIcons.refresh),
                label: const Text('Reload'),
              ),
              if (view.supported)
                TextButton(
                  onPressed: view.busy
                      ? null
                      : () async {
                          try {
                            await controller.openSettings();
                          } catch (_) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Open Health Connect in Android Settings.',
                                  ),
                                ),
                              );
                            }
                          }
                        },
                  child: const Text('Android permissions'),
                ),
            ],
          ),
        ),
        const Text(
          'Checks the last 7 days when you open the Android app, or tap Sync now. Missing data stays empty. Earlier imports stay saved until you delete them.',
        ),
      ],
    );
  }

  Future<void> _connect() async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Share steps and sleep?'),
        content: const SingleChildScrollView(
          child: Text(
            'Daily Health Connect totals will be stored in your MyLifeGraph cloud account. Your selected Coach can read them; relevant results may be sent to its AI provider. Manual check-ins stay unchanged.\n\nYou can stop sharing or delete these imports here at any time. Android permission alone does not enable cloud sharing.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Agree and connect'),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    final controller = ref.read(healthConnectProvider.notifier);
    await controller.connect();
    if (mounted && ref.read(healthConnectProvider).error == null) {
      await controller.sync();
    }
  }

  Future<void> _delete() async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete watch imports?'),
        content: const Text(
          'Stops cloud sharing and deletes only Health Connect imports. Manual check-ins and data on your watch stay unchanged. Earlier saved Coach answers are not rewritten.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete imports'),
          ),
        ],
      ),
    );
    if (accepted == true && mounted) {
      await ref
          .read(healthConnectProvider.notifier)
          .disconnect(deleteData: true);
    }
  }
}
