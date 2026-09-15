import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_icons.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/widgets/app_card.dart';
import '../../features/coach/application/speech_settings.dart';
import '../../features/coach/domain/speech_models.dart';

Future<void> showSpeechSettings(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => const _SpeechSettingsSheet(),
    );

class SpeechSettingsEntry extends ConsumerWidget {
  const SpeechSettingsEntry({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(speechSettingsProvider);
    return AppCard(
      padding: EdgeInsets.zero,
      child: ListTile(
        leading: const Icon(AppIcons.microphone),
        title: const Text('Speech to text'),
        subtitle: Text(settings.label),
        trailing: const Icon(AppIcons.chevronRight),
        onTap: () => showSpeechSettings(context),
      ),
    );
  }
}

class SpeechSourceButton extends ConsumerWidget {
  const SpeechSourceButton({this.enabled = true, super.key});
  final bool enabled;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(speechSettingsProvider);
    return IconButton(
      tooltip: 'Speech to text: ${settings.label}',
      onPressed: enabled ? () => showSpeechSettings(context) : null,
      icon: Icon(
        settings.source == 'server'
            ? AppIcons.publicOutlined
            : AppIcons.downloadOutlined,
      ),
    );
  }
}

class _SpeechSettingsSheet extends ConsumerStatefulWidget {
  const _SpeechSettingsSheet({this.modelsOnly = false});
  final bool modelsOnly;
  @override
  ConsumerState<_SpeechSettingsSheet> createState() =>
      _SpeechSettingsSheetState();
}

class _SpeechSettingsSheetState extends ConsumerState<_SpeechSettingsSheet> {
  bool? _local;

  Future<void> _openModels() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => const _SpeechSettingsSheet(modelsOnly: true),
  );
  Future<void> _download(SpeechSettings settings, SpeechModel model) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Download ${model.label}?'),
        content: Text(
          '${(model.bytes / 1000000).ceil()} MB from Hugging Face. Use Wi-Fi and keep the app open.'
          '${model.id == 'parakeet-v3' ? ' Parakeet needs considerably more memory and may be slow on older phones.' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Download'),
          ),
        ],
      ),
    );
    if (accepted == true && mounted) await settings.download(model);
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(speechSettingsProvider);
    final local = _local ?? settings.source != 'server';
    return SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.md,
          0,
          AppSpacing.md,
          AppSpacing.lg + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                BackButton(onPressed: () => Navigator.of(context).pop()),
                Expanded(
                  child: Text(
                    widget.modelsOnly ? 'On-device models' : 'Speech to text',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            if (!widget.modelsOnly)
              SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: false,
                    label: Text('Server'),
                    icon: Icon(AppIcons.publicOutlined),
                  ),
                  ButtonSegment(
                    value: true,
                    label: Text('On-device'),
                    icon: Icon(AppIcons.downloadOutlined),
                  ),
                ],
                selected: {local},
                onSelectionChanged: settings.loading
                    ? null
                    : (value) {
                        setState(() => _local = value.single);
                        if (value.single) {
                          _openModels();
                        } else {
                          settings.select('server');
                        }
                      },
              ),
            const SizedBox(height: AppSpacing.sm),
            if (settings.loading)
              const LinearProgressIndicator()
            else if (!widget.modelsOnly && !local)
              const ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Parakeet · provided'),
                subtitle: Text('Audio is transcribed on our server.'),
              )
            else if (!widget.modelsOnly)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(AppIcons.microphone),
                title: Text(
                  settings.source == 'server' ? 'Choose model' : settings.label,
                ),
                trailing: const Icon(AppIcons.chevronRight),
                onTap: _openModels,
              )
            else ...[
              if (!settings.supported)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: Text(
                    'Download and activation require the 64-bit Android app.',
                  ),
                ),
              Text(
                'Multilingual · audio stays on this device',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              for (final model in speechModels)
                AppCard(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  child: Column(
                    children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          settings.source == model.id
                              ? AppIcons.checkCircleOutline
                              : AppIcons.radioButtonUnchecked,
                        ),
                        title: Text(model.label),
                        subtitle: Text('${(model.bytes / 1000000).ceil()} MB'),
                        onTap:
                            settings.supported &&
                                settings.installed.contains(model.id)
                            ? () => settings.select(model.id)
                            : null,
                        trailing: settings.downloading == model.id
                            ? IconButton(
                                tooltip: 'Cancel download',
                                onPressed: settings.store.cancelDownload,
                                icon: const Icon(AppIcons.close),
                              )
                            : settings.installed.contains(model.id)
                            ? IconButton(
                                tooltip: settings.source == model.id
                                    ? 'Select another source before removing'
                                    : 'Remove downloaded model',
                                onPressed:
                                    settings.source == model.id ||
                                        settings.downloading != null
                                    ? null
                                    : () => settings.remove(model),
                                icon: const Icon(AppIcons.deleteOutline),
                              )
                            : IconButton(
                                tooltip: 'Download ${model.label}',
                                onPressed:
                                    settings.supported &&
                                        settings.downloading == null
                                    ? () => _download(settings, model)
                                    : null,
                                icon: const Icon(AppIcons.downloadOutlined),
                              ),
                      ),
                      if (settings.downloading == model.id)
                        LinearProgressIndicator(value: settings.progress),
                    ],
                  ),
                ),
            ],
            if (settings.error != null)
              Text(
                settings.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
    );
  }
}
