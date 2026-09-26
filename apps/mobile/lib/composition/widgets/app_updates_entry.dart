import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/theme/app_icons.dart';
import '../../core/widgets/app_surface.dart';
import '../../features/app_updates/application/app_updates.dart';
import '../../features/app_updates/presentation/update_dialog.dart';

class AppUpdatesEntry extends ConsumerWidget {
  const AppUpdatesEntry({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(appUpdatesSupportedProvider)) return const SizedBox.shrink();
    final state = ref.watch(appUpdatesProvider);
    return AppSurface(
      variant: AppSurfaceVariant.subtle,
      padding: EdgeInsets.zero,
      child: ListTile(
        key: const ValueKey('app-updates-entry'),
        leading: const Icon(AppIcons.downloadOutlined),
        title: const Text('Updates'),
        subtitle: state.check == UpdateCheck.available
            ? const Text('Update available')
            : null,
        trailing: const Icon(AppIcons.chevronRight),
        onTap: () => showDialog<void>(
          context: context,
          builder: (_) => const _UpdatesSettingsDialog(),
        ),
      ),
    );
  }
}

class _UpdatesSettingsDialog extends ConsumerStatefulWidget {
  const _UpdatesSettingsDialog();

  @override
  ConsumerState<_UpdatesSettingsDialog> createState() =>
      _UpdatesSettingsDialogState();
}

class _UpdatesSettingsDialogState
    extends ConsumerState<_UpdatesSettingsDialog> {
  bool _opening = false;
  bool _downloadFailed = false;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appUpdatesProvider);
    final checking = state.check == UpdateCheck.checking;
    return AlertDialog(
      title: const Text('Updates'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              state.installed == null
                  ? 'Version unavailable'
                  : 'Installed: ${state.installed!.name}',
            ),
            const SizedBox(height: AppSpacing.sm),
            if (state.check != UpdateCheck.idle)
              Text(switch (state.check) {
                UpdateCheck.checking => 'Checking…',
                UpdateCheck.current => 'Up to date',
                UpdateCheck.available => 'Available: ${state.update!.name}',
                _ => 'Could not check. Try again.',
              }),
            if (_downloadFailed)
              const Text('Could not open download. Try again.'),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        OutlinedButton.icon(
          onPressed: checking
              ? null
              : () => ref.read(appUpdatesProvider.notifier).check(manual: true),
          icon: const Icon(AppIcons.refresh),
          label: const Text('Check'),
        ),
        if (state.update != null)
          FilledButton.icon(
            onPressed: _opening
                ? null
                : () async {
                    setState(() {
                      _opening = true;
                      _downloadFailed = false;
                    });
                    final opened = await openAppUpdate(state.update!);
                    if (!mounted) return;
                    setState(() {
                      _opening = false;
                      _downloadFailed = !opened;
                    });
                  },
            icon: const Icon(AppIcons.downloadOutlined),
            label: const Text('Download'),
          ),
      ],
    );
  }
}
