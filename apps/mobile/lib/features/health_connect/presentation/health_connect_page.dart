import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../composition/health_connect_providers.dart';
import '../../../core/capabilities/app_surface_capabilities.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_feature_palette.dart';
import '../../../core/theme/app_motion_tokens.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_page.dart';
import '../../../core/widgets/app_surface.dart';

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
    final connected =
        view.error == null &&
        !view.busy &&
        cloud?.enabled == true &&
        view.supported &&
        view.granted &&
        ownDevice;
    final connectionLabel = view.error != null
        ? 'Could not confirm'
        : view.busy || cloud == null
        ? 'Checking…'
        : !view.supported
        ? 'Unavailable here'
        : cloud.enabled && !ownDevice
        ? 'Other device'
        : connected
        ? 'Connected'
        : 'Not connected';
    return AppPage(
      title: 'Health Connect',
      compactHeader: true,
      maxWidth: 720,
      actions: [
        IconButton(
          tooltip: 'Reload',
          onPressed: view.busy ? null : controller.load,
          icon: const Icon(AppIcons.refresh),
        ),
      ],
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.xs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          'Watch data',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        if (cloud != null)
                          AppStatusPill(
                            label: cloud.enabled ? 'Sharing on' : 'Sharing off',
                            tone: cloud.enabled
                                ? AppStatusTone.success
                                : AppStatusTone.neutral,
                          ),
                      ],
                    ),
                  ),
                  if (cloud != null)
                    PopupMenuButton<String>(
                      tooltip: 'Watch data actions',
                      enabled: editable,
                      icon: const Icon(AppIcons.moreHoriz),
                      onSelected: (action) {
                        if (action == 'stop') {
                          controller.disconnect();
                        } else {
                          _delete();
                        }
                      },
                      itemBuilder: (_) => [
                        if (cloud.enabled)
                          const PopupMenuItem(
                            value: 'stop',
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(AppIcons.stop),
                              title: Text('Stop sharing'),
                            ),
                          ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(AppIcons.deleteOutline),
                            title: Text('Delete imported data'),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              AnimatedSwitcher(
                duration: context.motionTokens.stateFor(context),
                child: Row(
                  key: ValueKey('watch-status-$connectionLabel'),
                  children: [
                    SizedBox.square(
                      dimension: 88,
                      child: AppSurface(
                        variant: connected
                            ? AppSurfaceVariant.accent
                            : AppSurfaceVariant.subtle,
                        padding: EdgeInsets.zero,
                        child: Center(
                          child: ExcludeSemantics(
                            child: Icon(
                              AppIcons.watch,
                              size: 60,
                              color: connected
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            connectionLabel,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          const Text('Sleep · Steps'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              if (cloud != null) ...[
                _metrics(cloud.latest),
                const SizedBox(height: AppSpacing.sm),
                if (view.supported && cloud.enabled && ownDevice)
                  TextButton.icon(
                    icon: const Icon(AppIcons.heartbeat),
                    onPressed: editable ? () => _vitals(cloud.vitalsEnabled) : null,
                    label: Text(cloud.vitalsEnabled ? 'Remove heart data' : 'Add heart data'),
                  ),
              ],
              if (view.busy) const LinearProgressIndicator(),
              if (view.error != null)
                Text(
                  view.error!,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              if (cloud != null) ...[
                if (cloud.lastSyncedAt != null)
                  Text(
                    'Last sync: ${MaterialLocalizations.of(context).formatShortDate(cloud.lastSyncedAt!.toLocal())} · ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(cloud.lastSyncedAt!.toLocal()))}',
                  ),
                const SizedBox(height: AppSpacing.sm),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
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
                  ],
                ),
              ],
              if (!view.supported)
                const Text(
                  'Import on Android 14 or later.',
                  textAlign: TextAlign.start,
                ),
            ],
          ),
        ),
        if (view.supported)
          AppCard(
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Data permissions'),
              trailing: const Icon(AppIcons.chevronRight),
              onTap: view.busy ? null : _openPermissions,
            ),
          ),
        const AppCard(
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text('Details'),
            children: [
              Text(
                'In Garmin Connect, enable Health Connect sharing first. '
                'Then allow access here on Android 14 or later.\n\n'
                'Checks the last 7 days when you open the Android app, or tap Sync now. '
                'Manual check-ins stay separate. Missing data stays empty. '
                'Earlier imports stay saved until you delete them.',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _openPermissions() async {
    try {
      await ref.read(healthConnectProvider.notifier).openSettings();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Open Health Connect in Android Settings.'),
          ),
        );
      }
    }
  }

  Widget _metrics(Map<String, dynamic> data) {
    String value(String key, String unit) => data[key] is num ? '${(data[key] as num).round()}$unit' : 'Unavailable';
    final sleep = data['sleep_minutes'] as num?;
    final entries = [
      ('Sleep', sleep == null ? 'Unavailable' : '${sleep.round() ~/ 60}h ${sleep.round() % 60}m', AppIcons.bedtimeOutlined, AppFeaturePalette.sleep),
      ('Steps', value('steps', ''), AppIcons.footprints, AppFeaturePalette.steps),
      ('Heart rate', value('heart_rate', ' bpm'), AppIcons.heart, AppFeaturePalette.heart),
      ('Resting', value('resting_heart_rate', ' bpm'), AppIcons.heartbeat, AppFeaturePalette.resting),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Today', style: Theme.of(context).textTheme.labelMedium),
      const SizedBox(height: 8),
      LayoutBuilder(builder: (context, constraints) {
        final columns = constraints.maxWidth < 280 || MediaQuery.textScalerOf(context).scale(1) > 1.5 ? 1 : 2;
        return Wrap(spacing: 8, runSpacing: 8, children: [
          for (final (label, text, icon, color) in entries)
            SizedBox(width: (constraints.maxWidth - (columns - 1) * 8) / columns,
              child: AppSurface(variant: AppSurfaceVariant.subtle, padding: const EdgeInsets.all(12), child: Row(children: [
                Icon(icon, color: Theme.of(context).brightness == Brightness.light ? Color.lerp(color, Colors.black, .4) : color, size: 28),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(label, style: Theme.of(context).textTheme.labelMedium),
                  Text(text, style: Theme.of(context).textTheme.titleSmall),
                ])),
              ])),
            ),
        ]);
      }),
      const SizedBox(height: 8),
      AppSurface(variant: AppSurfaceVariant.subtle, padding: const EdgeInsets.all(12), child: Row(children: [
        const Icon(AppIcons.personOutlineRounded, color: AppFeaturePalette.resting),
        const SizedBox(width: 12),
        const Expanded(child: Text('Stress · Unavailable')),
        const Tooltip(message: 'No supported Health Connect stress source. Check-in stress stays separate.', child: Icon(AppIcons.infoOutline, size: 20)),
      ])),
    ]);
  }

  Future<void> _vitals(bool enabled) async {
    final controller = ref.read(healthConnectProvider.notifier);
    final accepted = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: Text(enabled ? 'Remove heart data?' : 'Share heart data?'),
      content: Text(enabled
        ? 'Stops heart-data sharing and removes imported heart values. Sleep, steps and earlier Coach answers stay unchanged.'
        : 'Daily heart-rate and resting-heart-rate averages will be stored in your cloud account and available to your selected Coach provider. No medical conclusions. You can remove them here.'),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(enabled ? 'Remove' : 'Agree'))],
    ));
    if (accepted != true || !mounted || !identical(controller, ref.read(healthConnectProvider.notifier))) return;
    await controller.setVitals(!enabled);
    if (mounted && ref.read(healthConnectProvider).error == null) {
      if (enabled) { await controller.load(); } else { await controller.sync(); }
    }
  }

  Future<void> _connect() async {
    final controller = ref.read(healthConnectProvider.notifier);
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
    if (accepted != true || !mounted || !identical(controller, ref.read(healthConnectProvider.notifier))) return;
    await controller.connect();
    if (mounted && ref.read(healthConnectProvider).error == null) {
      await controller.sync();
    }
  }

  Future<void> _delete() async {
    final controller = ref.read(healthConnectProvider.notifier);
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
    if (accepted == true && mounted && identical(controller, ref.read(healthConnectProvider.notifier))) {
      await controller.disconnect(deleteData: true);
    }
  }
}
