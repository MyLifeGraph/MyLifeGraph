import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../coach_credentials_providers.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/navigation/app_routes.dart';
import '../../core/theme/app_icons.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/app_info_disclosure.dart';
import '../../features/coach/application/coach_credentials_controller.dart';
import '../../features/coach/domain/coach.dart';

class CoachProviderSettingsCard extends ConsumerStatefulWidget {
  const CoachProviderSettingsCard({
    this.initiallyExpanded = false,
    this.showOpenCoach = true,
    this.compact = false,
    this.directSelection = false,
    this.onSelected,
    this.enabled = true,
    this.onChanged,
    this.availabilityDetails,
    super.key,
  });

  final bool initiallyExpanded;
  final bool showOpenCoach;
  final bool compact;
  final bool directSelection;
  final ValueChanged<CoachProviderName>? onSelected;
  final bool enabled;
  final VoidCallback? onChanged;
  final String? availabilityDetails;

  @override
  ConsumerState<CoachProviderSettingsCard> createState() =>
      _CoachProviderSettingsCardState();
}

class _CoachProviderSettingsCardState
    extends ConsumerState<CoachProviderSettingsCard> {
  final _openAiController = TextEditingController();
  final _geminiController = TextEditingController();

  @override
  void dispose() {
    _openAiController.dispose();
    _geminiController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    late final CoachCredentials credentials;
    try {
      credentials = ref.watch(coachCredentialsProvider);
    } on StateError {
      return AppCard(
        padding: EdgeInsets.zero,
        child: ListTile(
          leading: const Icon(AppIcons.forumOutlined),
          title: const Text('Coach'),
          subtitle: const Text('Read-only Coach and provider keys.'),
          trailing: const Icon(AppIcons.chevronRight),
          onTap: () => context.push(AppRoutes.coach),
        ),
      );
    }
    final selected = credentials.provider;
    final isByok = const {
      CoachProviderName.openai,
      CoachProviderName.gemini,
    }.contains(selected);
    final input = selected == CoachProviderName.gemini
        ? _geminiController
        : _openAiController;
    final hasKey = selected != null && isByok && credentials.hasKey(selected);
    final subtitle = selected == CoachProviderName.operatorCodexPilot
        ? 'Project Coach selected; no personal API key required.'
        : isByok
        ? 'Personal API-key provider selected.'
        : 'Choose Project Coach or use your own API key.';
    final dropdown = DropdownButtonFormField<CoachProviderName>(
      key: const ValueKey('coach-provider-selection'),
      initialValue: selected,
      isExpanded: true,
      itemHeight: null,
      selectedItemBuilder: widget.compact
          ? (context) => const [Text('Standard'), Text('OpenAI'), Text('Gemini')]
          : null,
      decoration: InputDecoration(
        labelText: widget.compact ? 'Choose Coach' : 'Coach mode',
        hintText: widget.compact ? 'Select' : 'Choose a mode',
      ),
      items: const [
        DropdownMenuItem(
          value: CoachProviderName.operatorCodexPilot,
          child: Text('Standard (provided)'),
        ),
        DropdownMenuItem(
          value: CoachProviderName.openai,
          child: Text('OpenAI (your key)'),
        ),
        DropdownMenuItem(
          value: CoachProviderName.gemini,
          child: Text('Gemini (your key)'),
        ),
      ],
      onChanged: credentials.busy || !widget.enabled
          ? null
          : (value) {
              if (value != null) {
                ref.read(coachCredentialsProvider.notifier).select(value);
                widget.onChanged?.call();
              }
            },
    );
    final controls = <Widget>[
      if (widget.directSelection)
        for (final option in const {
          CoachProviderName.operatorCodexPilot: 'Standard (provided)',
          CoachProviderName.openai: 'OpenAI (your key)',
          CoachProviderName.gemini: 'Gemini (your key)',
        }.entries)
          AppInfoDisclosure(
            topic: option.value,
            useDialog: true,
            keyPrefix: 'coach-mode-${option.key.code}',
            description: (option.key == CoachProviderName.operatorCodexPilot
                ? 'Project Coach uses a temporary read-only snapshot on the VPS. '
                  'Only your question and queried results reach the shared pilot '
                  'account. Limits: 5 questions per account and 15 total per UTC day. '
                  'No personal API key is required. No automatic provider fallback.'
                : 'Uses your own ${option.key == CoachProviderName.openai ? 'OpenAI' : 'Gemini'} key. '
                  'Requests may cost money. Your question and relevant read-only '
                  'query results are sent to this provider. On web, keys exist '
                  'only in this tab and disappear on reload. No automatic provider fallback.') +
                (selected == option.key && widget.availabilityDetails != null
                    ? '\n\n${widget.availabilityDetails}' : ''),
            headerBuilder: (context, infoButton) => Row(children: [
              Expanded(child: ListTile(
                key: ValueKey('coach-select-${option.key.code}'),
                contentPadding: EdgeInsets.zero,
                title: Text(option.value),
                selected: selected == option.key,
                trailing: selected == option.key
                    ? const Icon(AppIcons.check) : null,
                enabled: !credentials.busy && widget.enabled,
                onTap: () {
                  ref.read(coachCredentialsProvider.notifier).select(option.key);
                  widget.onChanged?.call();
                  widget.onSelected?.call(option.key);
                },
              )),
              infoButton,
            ]),
          )
      else if (widget.compact)
        AppInfoDisclosure(
          topic: 'Coach modes',
          useDialog: true,
          keyPrefix: 'coach-modes',
          description:
              'Project Coach uses a temporary read-only snapshot on the VPS. '
              'Only your question and queried results reach the shared pilot '
              'account. Limits: 5 questions per account and 15 total per UTC day. '
              'Personal OpenAI/Gemini requests may cost money and send relevant '
              'read-only query results to that provider. On web, keys live only '
              'in this tab and disappear on reload. No automatic provider fallback.'
              '\n\n${widget.availabilityDetails ?? ''}',
          headerBuilder: (context, infoButton) => Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: dropdown),
              infoButton,
            ],
          ),
        )
      else
        dropdown,
      if (selected == CoachProviderName.operatorCodexPilot &&
          !widget.compact) ...[
        const SizedBox(height: AppSpacing.sm),
        const Text(
          'The project VPS creates a temporary read-only snapshot of your '
          'app data. Restricted Coach tools send your question and only '
          'the results they query to the shared pilot Codex account. It '
          'has limited shared capacity: '
          'up to 5 turns per account and 15 dispatched turns in total per '
          'UTC day. Busy or unavailable never falls back to your key.',
        ),
      ] else if (isByok) ...[
        const SizedBox(height: AppSpacing.sm),
        if (selected == CoachProviderName.gemini) ...[
          DropdownButtonFormField<String>(
            key: ValueKey('coach-gemini-model-${credentials.geminiModel}'),
            initialValue: credentials.geminiModel,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Model', isDense: true),
            items: [for (final model in coachGeminiModels.entries)
              DropdownMenuItem(value: model.key, child: Text(model.value)),
            ],
            onChanged: credentials.busy || !widget.enabled ? null : (value) async {
              if (value == null) return;
              await ref.read(coachCredentialsProvider.notifier).selectGeminiModel(value);
              if (mounted) widget.onChanged?.call();
            },
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        TextField(
          key: ValueKey('coach-key-${selected!.code}'),
          controller: input,
          obscureText: true,
          enableSuggestions: false,
          autocorrect: false,
          decoration: InputDecoration(
            labelText: hasKey ? 'Replacement API key' : 'API key',
            helperText: hasKey
                ? 'A tested key is saved on this device.'
                : 'No key is saved for this provider.',
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            FilledButton(
              key: const ValueKey('coach-key-test-save'),
              onPressed: credentials.busy || !widget.enabled
                  ? null
                  : () async {
                      final saved = await ref
                          .read(coachCredentialsProvider.notifier)
                          .testAndSave(selected, input.text);
                      if (saved && context.mounted) {
                        input.clear();
                        widget.onChanged?.call();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Provider key tested and saved.'),
                          ),
                        );
                      }
                    },
              child: Text(hasKey ? 'Test and replace' : 'Test and save'),
            ),
            if (hasKey)
              OutlinedButton(
                key: const ValueKey('coach-key-delete'),
                onPressed: credentials.busy || !widget.enabled
                    ? null
                    : () async {
                        await ref
                            .read(coachCredentialsProvider.notifier)
                            .delete(selected);
                        widget.onChanged?.call();
                      },
                child: const Text('Delete key'),
              ),
          ],
        ),
      ] else if (!widget.compact) ...[
        const SizedBox(height: AppSpacing.sm),
        const Text(
          'Standard uses Project Coach. The app never switches providers '
          'after an error.',
        ),
      ],
      if (widget.compact && selected != null &&
          (!widget.directSelection || isByok)) ...[
        const SizedBox(height: AppSpacing.xs),
        Text(
          isByok
              ? 'May cost money · Sends read-only query results to your provider.'
              : 'Shared project account · Read-only query results.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
      if (credentials.error case final error?) ...[
        const SizedBox(height: AppSpacing.sm),
        Text(
          error,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.error,
          ),
        ),
      ],
      if (!widget.compact) const SizedBox(height: AppSpacing.sm),
      if (widget.showOpenCoach && !widget.compact)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => context.push(AppRoutes.coach),
            child: const Text('Open Coach'),
          ),
        ),
      if (!widget.compact)
        Text(
          'Personal provider requests may cost money. Relevant results from '
          'your read-only Coach query are sent only to the mode you select. '
          'On web, personal keys exist only in this tab and are cleared by '
          'reload.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
    ];
    if (widget.compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: controls,
      );
    }
    return AppCard(
      padding: EdgeInsets.zero,
      child: ExpansionTile(
        initiallyExpanded: widget.initiallyExpanded,
        key: const ValueKey('settings-coach-provider'),
        leading: const Icon(AppIcons.forumOutlined),
        title: const Text('Coach'),
        subtitle: Text(subtitle),
        childrenPadding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          0,
          AppSpacing.md,
          AppSpacing.md,
        ),
        children: controls,
      ),
    );
  }
}
