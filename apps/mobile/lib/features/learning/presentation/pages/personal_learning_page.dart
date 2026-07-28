import 'package:flutter/material.dart';

import 'package:my_life_graph/core/theme/app_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_page.dart';
import '../providers/learning_providers.dart';

class PersonalLearningPage extends ConsumerStatefulWidget {
  const PersonalLearningPage({super.key});

  @override
  ConsumerState<PersonalLearningPage> createState() =>
      _PersonalLearningPageState();
}

class _PersonalLearningPageState extends ConsumerState<PersonalLearningPage> {
  int? _draftRevision;
  bool _reflectionPrompt = true;
  bool _analysis = true;
  bool _learnedPlanning = false;
  bool _dirty = false;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(learningSettingsProvider);
    final controller = ref.read(learningSettingsProvider.notifier);
    final preferences = state.preferences;
    final pilotEnabled =
        ref.watch(appConfigProvider).learnedFocusPlanningPilotEnabled;
    if (preferences != null &&
        _draftRevision != preferences.revision &&
        !state.isSaving) {
      _draftRevision = preferences.revision;
      _reflectionPrompt = preferences.focusReflectionPromptEnabled;
      _analysis = preferences.personalPatternAnalysisEnabled;
      _learnedPlanning = preferences.learnedFocusPlanningEnabled;
      _dirty = false;
    }
    if (state.isLoading && preferences == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (preferences == null) {
      return AppPage(
        title: 'Personal learning',
        subtitle: 'Focus reflections and transparent patterns',
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Personal learning settings could not be loaded.'),
                const SizedBox(height: AppSpacing.md),
                OutlinedButton.icon(
                  onPressed: state.isLoading ? null : controller.load,
                  icon: const Icon(AppIcons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        ],
      );
    }
    final enabled = !state.isLoading &&
        !state.isSaving &&
        !state.isClearing &&
        !state.requiresExactRetry &&
        !state.reloadRequired;
    return AppPage(
      title: 'Personal learning',
      subtitle: 'Focus reflections and transparent patterns',
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile(
                key: const ValueKey('focus-reflection-prompt-setting'),
                contentPadding: EdgeInsets.zero,
                value: _reflectionPrompt,
                onChanged: enabled
                    ? (value) => _setDraft(() => _reflectionPrompt = value)
                    : null,
                title: const Text('Ask after Focus sessions'),
                subtitle: const Text(
                  'You can still rate or edit finished sessions from Recent focus.',
                ),
              ),
              const Divider(),
              SwitchListTile(
                key: const ValueKey('personal-pattern-analysis-setting'),
                contentPadding: EdgeInsets.zero,
                value: _analysis,
                onChanged: enabled
                    ? (value) => _setDraft(() {
                          _analysis = value;
                          if (!value) _learnedPlanning = false;
                        })
                    : null,
                title: const Text('Analyze my study patterns'),
                subtitle: const Text(
                  'Uses up to 90 days of your Focus reflections and valid sleep captures. No AI model is called.',
                ),
              ),
              const Divider(),
              SwitchListTile(
                key: const ValueKey('learned-focus-planning-setting'),
                contentPadding: EdgeInsets.zero,
                value: _learnedPlanning,
                onChanged: enabled && _analysis && pilotEnabled
                    ? (value) => _setDraft(() => _learnedPlanning = value)
                    : null,
                title: const Text('Prefer learned Focus times in new plans'),
                subtitle: Text(
                  !pilotEnabled
                      ? 'This optional Planner pilot is not enabled in this build.'
                      : !_analysis
                          ? 'Turn on pattern analysis first.'
                          : 'Uses only mature timing evidence as a soft preference. Existing plans never move.',
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Sleep patterns are explanatory only. They never change your sleep target, capacity, or plan.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Focus reflection history',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.xs),
              const Text(
                'Clearing removes ratings and obstacles, but keeps finished Focus sessions.',
              ),
              const SizedBox(height: AppSpacing.md),
              OutlinedButton.icon(
                key: const ValueKey('clear-focus-reflection-history'),
                onPressed: enabled ? _confirmClear : null,
                icon: state.isClearing
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(AppIcons.deleteSweepOutlined),
                label: const Text('Clear Focus reflection history'),
              ),
              if (state.lastClearedCount != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  '${state.lastClearedCount} reflections cleared.',
                  key: const ValueKey('focus-reflections-cleared-result'),
                ),
              ],
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
                      ? 'The result could not be confirmed. Retry the exact same request or reload.'
                      : 'Personal learning settings changed or could not be saved. Reload before trying again.',
                  key: const ValueKey('personal-learning-error'),
                ),
                const SizedBox(height: AppSpacing.md),
                OutlinedButton.icon(
                  onPressed: state.isSaving || state.isClearing
                      ? null
                      : state.requiresExactRetry
                          ? controller.retryExact
                          : controller.load,
                  icon: Icon(
                    state.requiresExactRetry
                        ? AppIcons.replayOutlined
                        : AppIcons.refresh,
                  ),
                  label: Text(
                    state.requiresExactRetry
                        ? 'Retry unchanged'
                        : 'Reload settings',
                  ),
                ),
              ],
            ),
          ),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            key: const ValueKey('personal-learning-save'),
            onPressed: enabled && _dirty ? _save : null,
            icon: state.isSaving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(AppIcons.saveOutlined),
            label: const Text('Save Personal learning'),
          ),
        ),
      ],
    );
  }

  void _setDraft(VoidCallback callback) {
    setState(() {
      callback();
      _dirty = true;
    });
  }

  Future<void> _save() async {
    final saved = await ref.read(learningSettingsProvider.notifier).save(
          focusReflectionPromptEnabled: _reflectionPrompt,
          personalPatternAnalysisEnabled: _analysis,
          learnedFocusPlanningEnabled: _learnedPlanning,
        );
    if (mounted && saved) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Personal learning settings saved.')),
      );
    }
  }

  Future<void> _confirmClear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear Focus reflection history?'),
        content: const Text(
          'This permanently deletes all Focus ratings and obstacles. Finished sessions remain. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('confirm-clear-focus-reflections'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Clear reflections'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final cleared = await ref
        .read(learningSettingsProvider.notifier)
        .clearFocusReflections();
    if (mounted && cleared) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Focus reflection history cleared.')),
      );
    }
  }
}
