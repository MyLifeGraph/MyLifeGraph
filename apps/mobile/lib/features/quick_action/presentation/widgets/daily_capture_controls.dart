import 'package:flutter/material.dart';

import 'package:my_life_graph/core/constants/app_radii.dart';

import 'package:my_life_graph/core/theme/app_icons.dart';
import 'package:my_life_graph/core/theme/app_motion_tokens.dart';

import '../../../../core/constants/app_spacing.dart';

const _captureInfoControlSize = 44.0;
const _captureInfoIconSize = 20.0;

/// Non-persisted disclosure for explanatory Daily Capture copy.
///
/// Each instance owns its open state. The description is absent from both the
/// widget and semantics trees while closed, and the control follows the
/// product-wide 44 logical-pixel action-target rule.
class CaptureInfoDisclosure extends StatefulWidget {
  const CaptureInfoDisclosure({
    required this.heading,
    required this.description,
    this.headingStyle,
    this.descriptionStyle,
    super.key,
  });

  final String heading;
  final String description;
  final TextStyle? headingStyle;
  final TextStyle? descriptionStyle;

  @override
  State<CaptureInfoDisclosure> createState() => _CaptureInfoDisclosureState();
}

class _CaptureInfoDisclosureState extends State<CaptureInfoDisclosure> {
  bool _expanded = false;

  @override
  void didUpdateWidget(CaptureInfoDisclosure oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.heading != widget.heading) {
      _expanded = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final motion = context.motionTokens;
    final duration = motion.stateFor(context);
    final actionLabel =
        '${_expanded ? 'Hide' : 'Show'} information about ${widget.heading}';
    final infoButton = SizedBox.square(
      key: ValueKey('capture-info-control-${widget.heading}'),
      dimension: _captureInfoControlSize,
      child: Semantics(
        button: true,
        expanded: _expanded,
        label: actionLabel,
        onTap: _toggle,
        child: ExcludeSemantics(
          child: IconButton(
            tooltip: actionLabel,
            color: Theme.of(context).colorScheme.primary,
            onPressed: _toggle,
            icon: const Icon(
              AppIcons.infoOutline,
              size: _captureInfoIconSize,
            ),
          ),
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Text(
                  widget.heading,
                  style: widget.headingStyle ??
                      Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ),
            infoButton,
          ],
        ),
        ExcludeSemantics(
          excluding: !_expanded,
          child: AnimatedSwitcher(
            duration: duration,
            reverseDuration: duration,
            switchInCurve: motion.curve,
            switchOutCurve: motion.curve,
            transitionBuilder: (child, animation) {
              final curved = CurvedAnimation(
                parent: animation,
                curve: motion.curve,
                reverseCurve: motion.curve,
              );
              return SizeTransition(
                sizeFactor: curved,
                alignment: AlignmentDirectional.topStart,
                child: FadeTransition(opacity: curved, child: child),
              );
            },
            child: _expanded
                ? Padding(
                    key: ValueKey(
                      'capture-info-description-${widget.heading}',
                    ),
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: Text(
                      widget.description,
                      style: widget.descriptionStyle ??
                          Theme.of(context).textTheme.bodyMedium,
                    ),
                  )
                : SizedBox(
                    key: ValueKey(
                      'capture-info-description-closed-${widget.heading}',
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  void _toggle() => setState(() => _expanded = !_expanded);
}

class CaptureChoice<T> {
  const CaptureChoice({
    required this.value,
    required this.label,
    this.semanticLabel,
    this.description,
  });

  final T value;
  final String label;
  final String? semanticLabel;
  final String? description;
}

class CaptureChoiceControl<T> extends StatelessWidget {
  const CaptureChoiceControl({
    required this.value,
    required this.choices,
    required this.onChanged,
    this.equalWidthRow = false,
    super.key,
  });

  final T? value;
  final List<CaptureChoice<T>> choices;
  final ValueChanged<T> onChanged;
  final bool equalWidthRow;

  @override
  Widget build(BuildContext context) {
    if (equalWidthRow) {
      return IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var index = 0; index < choices.length; index++) ...[
              if (index > 0) const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: _EqualChoiceButton<T>(
                  choice: choices[index],
                  selected: choices[index].value == value,
                  onChanged: onChanged,
                ),
              ),
            ],
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: choices.map((choice) {
        final selected = choice.value == value;
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: MergeSemantics(
                  child: Semantics(
                    label: choice.semanticLabel ?? choice.label,
                    child: ChoiceChip(
                      selected: selected,
                      onSelected: (_) => onChanged(choice.value),
                      label: ExcludeSemantics(
                        child: SizedBox(
                          width: double.infinity,
                          child: Text(choice.label),
                        ),
                      ),
                      padding: const EdgeInsets.all(AppSpacing.md),
                    ),
                  ),
                ),
              ),
              if (choice.description != null) ...[
                const SizedBox(width: AppSpacing.xs),
                _ChoiceInfoButton(
                  label: choice.label,
                  description: choice.description!,
                ),
              ],
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _EqualChoiceButton<T> extends StatelessWidget {
  const _EqualChoiceButton({
    required this.choice,
    required this.selected,
    required this.onChanged,
  });

  final CaptureChoice<T> choice;
  final bool selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: Semantics(
        label: choice.semanticLabel ?? choice.label,
        child: ChoiceChip(
          selected: selected,
          onSelected: (_) => onChanged(choice.value),
          label: ExcludeSemantics(
            child: SizedBox(
              width: double.infinity,
              child: Text(
                choice.label,
                textAlign: TextAlign.center,
                softWrap: true,
              ),
            ),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xs,
            vertical: AppSpacing.md,
          ),
        ),
      ),
    );
  }
}

class _ChoiceInfoButton extends StatefulWidget {
  const _ChoiceInfoButton({
    required this.label,
    required this.description,
  });

  final String label;
  final String description;

  @override
  State<_ChoiceInfoButton> createState() => _ChoiceInfoButtonState();
}

class _ChoiceInfoButtonState extends State<_ChoiceInfoButton> {
  final _tooltipKey = GlobalKey<TooltipState>();

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      key: _tooltipKey,
      message: widget.description,
      triggerMode: TooltipTriggerMode.tap,
      child: Semantics(
        button: true,
        label: 'More information about ${widget.label}: ${widget.description}',
        child: ExcludeSemantics(
          child: IconButton(
            key: ValueKey('capture-choice-info-${widget.label}'),
            onPressed: () => _tooltipKey.currentState?.ensureTooltipVisible(),
            icon: const Icon(AppIcons.infoOutline),
          ),
        ),
      ),
    );
  }
}

class CaptureRatingControl extends StatelessWidget {
  const CaptureRatingControl({
    required this.value,
    required this.semanticPrefix,
    required this.onChanged,
    super.key,
  });

  final int? value;
  final String semanticPrefix;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(AppRadii.xl),
          ),
          child: Column(
            children: [
              Text(
                value == null ? 'Not set' : '$value / 10',
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                value == null
                    ? 'Choose a value to continue.'
                    : 'This selected value will be saved.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: List.generate(10, (index) {
            final rating = index + 1;
            final selected = rating == value;
            return Semantics(
              button: true,
              selected: selected,
              label: '$semanticPrefix $rating of 10',
              onTap: () => onChanged(rating),
              child: ExcludeSemantics(
                child: SizedBox.square(
                  dimension: 48,
                  child: selected
                      ? FilledButton(
                          onPressed: () => onChanged(rating),
                          child: Text('$rating'),
                        )
                      : OutlinedButton(
                          onPressed: () => onChanged(rating),
                          child: Text('$rating'),
                        ),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }
}

class CaptureSleepHoursControl extends StatelessWidget {
  const CaptureSleepHoursControl({
    required this.value,
    required this.onChanged,
    super.key,
  });

  final double? value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value == null ? 'Not set' : '${formatCaptureHours(value!)} h',
          style: Theme.of(context).textTheme.headlineLarge,
        ),
        const SizedBox(height: AppSpacing.sm),
        Semantics(
          label: 'Morning sleep hours',
          value: value == null ? 'Not set' : formatCaptureHours(value!),
          child: Slider(
            value: value ?? 7,
            min: 0,
            max: 12,
            divisions: 24,
            semanticFormatterCallback: (next) =>
                '${formatCaptureHours(next)} hours',
            onChanged: onChanged,
          ),
        ),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: const [4.0, 5.5, 7.0, 8.5, 10.0].map((hours) {
            final label = '${formatCaptureHours(hours)} h';
            return Semantics(
              button: true,
              selected: hours == value,
              label: 'morning sleep $label',
              onTap: () => onChanged(hours),
              child: ExcludeSemantics(
                child: OutlinedButton(
                  onPressed: () => onChanged(hours),
                  child: Text(label),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

String formatCaptureHours(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : value.toStringAsFixed(1);

class CaptureClockControl extends StatelessWidget {
  const CaptureClockControl({
    required this.label,
    required this.semanticLabel,
    required this.value,
    required this.onChanged,
    this.fallback = const TimeOfDay(hour: 23, minute: 0),
    this.quickValues = const [],
    super.key,
  });

  final String label;
  final String semanticLabel;
  final String? value;
  final ValueChanged<String> onChanged;
  final TimeOfDay fallback;
  final List<String> quickValues;

  @override
  Widget build(BuildContext context) {
    final parsed = _parseTimeOfDay(value);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          label: semanticLabel,
          value: value ?? 'Not set',
          child: OutlinedButton.icon(
            onPressed: () async {
              final selected = await showTimePicker(
                context: context,
                initialTime: parsed ?? fallback,
                helpText: label,
              );
              if (selected == null) {
                return;
              }
              onChanged(
                '${selected.hour.toString().padLeft(2, '0')}:'
                '${selected.minute.toString().padLeft(2, '0')}',
              );
            },
            icon: const Icon(AppIcons.schedule),
            label: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    value ?? 'Set time',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (quickValues.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: quickValues.map((quickValue) {
              assert(_parseTimeOfDay(quickValue) != null);
              return Semantics(
                button: true,
                selected: value == quickValue,
                label: '$semanticLabel preset $quickValue',
                onTap: () => onChanged(quickValue),
                child: ExcludeSemantics(
                  child: OutlinedButton(
                    onPressed: () => onChanged(quickValue),
                    child: Text(quickValue),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ],
    );
  }
}

class CaptureSleepTargetControl extends StatelessWidget {
  const CaptureSleepTargetControl({
    required this.value,
    required this.onChanged,
    super.key,
  });

  final int? value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final selected = value ?? 480;
    return Column(
      children: [
        Text(
          formatCaptureMinutes(selected),
          style: Theme.of(context).textTheme.headlineLarge,
        ),
        const SizedBox(height: AppSpacing.sm),
        Semantics(
          label: 'Sleep target',
          value: formatCaptureMinutes(selected),
          child: Slider(
            value: selected.toDouble(),
            min: 300,
            max: 720,
            divisions: 28,
            semanticFormatterCallback: (next) =>
                formatCaptureMinutes(next.round()),
            onChanged: (next) => onChanged((next / 15).round() * 15),
          ),
        ),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: const [360, 420, 480, 540].map((minutes) {
            return Semantics(
              button: true,
              selected: selected == minutes,
              label: 'sleep target ${formatCaptureMinutes(minutes)}',
              child: ExcludeSemantics(
                child: OutlinedButton(
                  onPressed: () => onChanged(minutes),
                  child: Text(formatCaptureMinutes(minutes)),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

String formatCaptureMinutes(int minutes) {
  final hours = minutes ~/ 60;
  final remainder = minutes % 60;
  if (remainder == 0) {
    return '$hours h';
  }
  return '$hours h ${remainder.toString().padLeft(2, '0')} min';
}

TimeOfDay? _parseTimeOfDay(String? value) {
  if (value == null ||
      !RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d$').hasMatch(value)) {
    return null;
  }
  final parts = value.split(':');
  return TimeOfDay(hour: int.parse(parts.first), minute: int.parse(parts.last));
}

class CaptureFlowScaffold extends StatelessWidget {
  const CaptureFlowScaffold({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.progress,
    required this.child,
    required this.canGoBack,
    required this.canContinue,
    required this.isLastStep,
    required this.isLoading,
    required this.isSaving,
    required this.saveLabel,
    required this.onClose,
    required this.onBack,
    required this.onNext,
    this.statusMessage,
    this.errorMessage,
    this.loadErrorMessage,
    this.onRetryLoad,
    this.secondaryLoadActionLabel,
    this.onSecondaryLoadAction,
    super.key,
  });

  final String eyebrow;
  final String title;
  final String subtitle;
  final double progress;
  final Widget child;
  final bool canGoBack;
  final bool canContinue;
  final bool isLastStep;
  final bool isLoading;
  final bool isSaving;
  final String saveLabel;
  final String? statusMessage;
  final String? errorMessage;
  final String? loadErrorMessage;
  final VoidCallback? onRetryLoad;
  final String? secondaryLoadActionLabel;
  final VoidCallback? onSecondaryLoadAction;
  final VoidCallback onClose;
  final VoidCallback onBack;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: Container(
                  decoration: BoxDecoration(
                    color: colors.surfaceContainer,
                    borderRadius: BorderRadius.circular(AppRadii.xl),
                    border: Border.all(color: colors.outlineVariant),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            LinearProgressIndicator(value: progress),
                            const SizedBox(height: AppSpacing.lg),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        eyebrow,
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelLarge
                                            ?.copyWith(color: colors.primary),
                                      ),
                                      const SizedBox(height: AppSpacing.sm),
                                      Text(
                                        title,
                                        style: Theme.of(context)
                                            .textTheme
                                            .headlineMedium,
                                      ),
                                      const SizedBox(height: AppSpacing.sm),
                                      Text(
                                        subtitle,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyLarge,
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  key: const ValueKey('capture-flow-back'),
                                  tooltip: 'Back',
                                  onPressed: canGoBack ? onBack : onClose,
                                  icon: const Icon(AppIcons.arrowBack),
                                ),
                              ],
                            ),
                            if (statusMessage != null) ...[
                              const SizedBox(height: AppSpacing.md),
                              CaptureInlineMessage(
                                message: statusMessage!,
                                isError: false,
                              ),
                            ],
                            if (errorMessage != null) ...[
                              const SizedBox(height: AppSpacing.md),
                              CaptureInlineMessage(
                                message: errorMessage!,
                                isError: true,
                              ),
                            ],
                            if (loadErrorMessage != null) ...[
                              const SizedBox(height: AppSpacing.md),
                              CaptureInlineMessage(
                                message: loadErrorMessage!,
                                isError: true,
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              Wrap(
                                spacing: AppSpacing.sm,
                                runSpacing: AppSpacing.sm,
                                children: [
                                  if (onRetryLoad != null)
                                    OutlinedButton.icon(
                                      onPressed: isLoading ? null : onRetryLoad,
                                      icon: const Icon(AppIcons.refresh),
                                      label: const Text('Retry load'),
                                    ),
                                  if (secondaryLoadActionLabel != null &&
                                      onSecondaryLoadAction != null)
                                    TextButton(
                                      onPressed: isLoading
                                          ? null
                                          : onSecondaryLoadAction,
                                      child: Text(secondaryLoadActionLabel!),
                                    ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        child: isLoading
                            ? const Center(child: CircularProgressIndicator())
                            : child,
                      ),
                      const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        child: Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: canGoBack ? onBack : null,
                                icon: const Icon(AppIcons.arrowBack),
                                label: const Text('Back'),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.md),
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: isLoading || isSaving || !canContinue
                                    ? null
                                    : onNext,
                                icon: isSaving
                                    ? const SizedBox.square(
                                        dimension: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : Icon(
                                        isLastStep
                                            ? AppIcons.check
                                            : AppIcons.arrowForward,
                                      ),
                                label: Text(
                                  isSaving
                                      ? 'Saving...'
                                      : isLastStep
                                          ? saveLabel
                                          : 'Next',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class CaptureInlineMessage extends StatelessWidget {
  const CaptureInlineMessage({
    required this.message,
    required this.isError,
    super.key,
  });

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final color = isError
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.primary;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          isError ? AppIcons.errorOutline : AppIcons.checkCircleOutline,
          color: color,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            message,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: color,
                ),
          ),
        ),
      ],
    );
  }
}
