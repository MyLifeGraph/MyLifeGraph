import 'package:flutter/material.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../domain/focus_session.dart';

enum FocusReflectionSheetOutcome { saved, deleted, skipped }

Future<FocusReflectionSheetOutcome?> showFocusReflectionSheet({
  required BuildContext context,
  required FocusSession session,
  required FocusReflection? existing,
  required Future<FocusReflection> Function(FocusReflectionDraft draft) onSave,
  required Future<void> Function(FocusReflection reflection) onDelete,
}) {
  if (session.isActive) {
    throw const FocusCommandException(
      'Only a finished Focus session can be rated.',
    );
  }
  return showModalBottomSheet<FocusReflectionSheetOutcome>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _FocusReflectionSheet(
      session: session,
      existing: existing,
      onSave: onSave,
      onDelete: onDelete,
    ),
  );
}

class _FocusReflectionSheet extends StatefulWidget {
  const _FocusReflectionSheet({
    required this.session,
    required this.existing,
    required this.onSave,
    required this.onDelete,
  });

  final FocusSession session;
  final FocusReflection? existing;
  final Future<FocusReflection> Function(FocusReflectionDraft draft) onSave;
  final Future<void> Function(FocusReflection reflection) onDelete;

  @override
  State<_FocusReflectionSheet> createState() => _FocusReflectionSheetState();
}

class _FocusReflectionSheetState extends State<_FocusReflectionSheet> {
  int? _focusQuality;
  int? _usefulProgress;
  late final Set<FocusObstacle> _obstacles;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _focusQuality = widget.existing?.focusQuality;
    _usefulProgress = widget.existing?.usefulProgress;
    _obstacles = {...?widget.existing?.obstacles};
  }

  bool get _showObstacles =>
      widget.session.status == FocusSessionStatus.abandoned ||
      (_focusQuality ?? 5) <= 2 ||
      (_usefulProgress ?? 5) <= 2;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.lg + bottomInset,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: SingleChildScrollView(
            child: Column(
              key: const ValueKey('focus-reflection-sheet'),
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.existing == null
                      ? 'Reflect on this Focus session'
                      : 'Edit Focus reflection',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  widget.session.status == FocusSessionStatus.abandoned
                      ? 'The session is already saved as abandoned. This reflection only adds context.'
                      : 'The finished session is already saved. Recovery continues while you reflect.',
                ),
                const SizedBox(height: AppSpacing.lg),
                _RatingQuestion(
                  question: 'How focused did the session feel?',
                  lowAnchor: 'Scattered',
                  middleAnchor: 'Mixed',
                  highAnchor: 'Deeply focused',
                  value: _focusQuality,
                  semanticsPrefix: 'Focus quality',
                  onChanged: _saving
                      ? null
                      : (value) => setState(() {
                            _focusQuality = value;
                            _error = null;
                            if (!_showObstacles) _obstacles.clear();
                          }),
                ),
                const SizedBox(height: AppSpacing.lg),
                _RatingQuestion(
                  question: 'How much useful progress did you make?',
                  lowAnchor: 'Very little',
                  middleAnchor: 'Some',
                  highAnchor: 'A lot',
                  value: _usefulProgress,
                  semanticsPrefix: 'Useful progress',
                  onChanged: _saving
                      ? null
                      : (value) => setState(() {
                            _usefulProgress = value;
                            _error = null;
                            if (!_showObstacles) _obstacles.clear();
                          }),
                ),
                if (_showObstacles) ...[
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    'What got in the way? Optional, choose up to two',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.xs,
                    children: [
                      for (final obstacle in FocusObstacle.values)
                        FilterChip(
                          key: ValueKey(
                            'focus-obstacle-${obstacle.code}',
                          ),
                          label: Text(obstacle.label),
                          selected: _obstacles.contains(obstacle),
                          onSelected: _saving
                              ? null
                              : (selected) {
                                  setState(() {
                                    _error = null;
                                    if (selected) {
                                      if (_obstacles.length < 2) {
                                        _obstacles.add(obstacle);
                                      }
                                    } else {
                                      _obstacles.remove(obstacle);
                                    }
                                  });
                                },
                        ),
                    ],
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      _error!,
                      key: const ValueKey('focus-reflection-error'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  alignment: WrapAlignment.end,
                  children: [
                    if (widget.existing != null)
                      TextButton(
                        key: const ValueKey('delete-focus-reflection'),
                        onPressed: _saving ? null : _delete,
                        child: const Text('Delete reflection'),
                      ),
                    TextButton(
                      key: const ValueKey('skip-focus-reflection'),
                      onPressed: _saving
                          ? null
                          : () => Navigator.of(context).pop(
                                FocusReflectionSheetOutcome.skipped,
                              ),
                      child: const Text('Not now'),
                    ),
                    FilledButton(
                      key: const ValueKey('save-focus-reflection'),
                      onPressed: _saving ||
                              _focusQuality == null ||
                              _usefulProgress == null
                          ? null
                          : _save,
                      child: _saving
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Save reflection'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    final focusQuality = _focusQuality;
    final usefulProgress = _usefulProgress;
    if (focusQuality == null || usefulProgress == null || _saving) return;
    final obstacles = _showObstacles
        ? _obstacles.toList(growable: false)
        : const <FocusObstacle>[];
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(
        FocusReflectionDraft(
          focusQuality: focusQuality,
          usefulProgress: usefulProgress,
          obstacles: obstacles,
        ),
      );
      if (mounted) {
        Navigator.of(context).pop(FocusReflectionSheetOutcome.saved);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error is FocusCommandException
            ? error.message
            : 'Could not save the reflection. Your choices are still here; try again.';
      });
    }
  }

  Future<void> _delete() async {
    final reflection = widget.existing;
    if (reflection == null || _saving) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this reflection?'),
        content: const Text(
          'The finished Focus session stays in your history. Only its reflection is deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete reflection'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onDelete(reflection);
      if (mounted) {
        Navigator.of(context).pop(FocusReflectionSheetOutcome.deleted);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error is FocusCommandException
            ? error.message
            : 'Could not delete the reflection. Try again.';
      });
    }
  }
}

class _RatingQuestion extends StatelessWidget {
  const _RatingQuestion({
    required this.question,
    required this.lowAnchor,
    required this.middleAnchor,
    required this.highAnchor,
    required this.value,
    required this.semanticsPrefix,
    required this.onChanged,
  });

  final String question;
  final String lowAnchor;
  final String middleAnchor;
  final String highAnchor;
  final int? value;
  final String semanticsPrefix;
  final ValueChanged<int>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(question, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          children: [
            for (var rating = 1; rating <= 5; rating++)
              Semantics(
                button: true,
                selected: value == rating,
                label: '$semanticsPrefix $rating of 5',
                child: ChoiceChip(
                  key: ValueKey(
                    '${semanticsPrefix.toLowerCase().replaceAll(' ', '-')}-rating-$rating',
                  ),
                  label: Text('$rating'),
                  selected: value == rating,
                  onSelected:
                      onChanged == null ? null : (_) => onChanged!(rating),
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Row(
          children: [
            Expanded(child: Text(lowAnchor)),
            Expanded(
              child: Text(middleAnchor, textAlign: TextAlign.center),
            ),
            Expanded(
              child: Text(highAnchor, textAlign: TextAlign.end),
            ),
          ],
        ),
      ],
    );
  }
}
