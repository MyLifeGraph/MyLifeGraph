import 'package:flutter/material.dart';

import '../../../../core/constants/app_spacing.dart';

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
    super.key,
  });

  final T? value;
  final List<CaptureChoice<T>> choices;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: choices.map((choice) {
        final selected = choice.value == value;
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: MergeSemantics(
            child: Semantics(
              label: choice.semanticLabel ?? choice.label,
              child: ChoiceChip(
                selected: selected,
                onSelected: (_) => onChanged(choice.value),
                label: ExcludeSemantics(
                  child: SizedBox(
                    width: double.infinity,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(choice.label),
                        if (choice.description != null) ...[
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            choice.description!,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                padding: const EdgeInsets.all(AppSpacing.md),
              ),
            ),
          ),
        );
      }).toList(),
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
            borderRadius: BorderRadius.circular(20),
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
                    borderRadius: BorderRadius.circular(28),
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
                                  tooltip: 'Close',
                                  onPressed: onClose,
                                  icon: const Icon(Icons.close),
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
                                icon: const Icon(Icons.arrow_back),
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
                                            ? Icons.check
                                            : Icons.arrow_forward,
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
          isError ? Icons.error_outline : Icons.check_circle_outline,
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
