import 'package:flutter/material.dart';
import '../../../../core/constants/app_spacing.dart';
import 'daily_capture_controls.dart';

class OptionalSkillsetChoice extends StatelessWidget {
  const OptionalSkillsetChoice({
    super.key,
    required this.label,
    required this.choices,
    required this.value,
    required this.onChanged,
    this.equalWidthRow = false,
  });
  final String label;
  final List<String> choices;
  final int? value;
  final ValueChanged<int?> onChanged;
  final bool equalWidthRow;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        if (equalWidthRow) ...[
          const SizedBox(height: AppSpacing.sm),
          CaptureChoiceControl<int>(
            value: value,
            equalWidthRow: true,
            choices: [
              for (var i = 0; i < choices.length; i++)
                CaptureChoice(
                  value: i,
                  label: choices[i],
                  semanticLabel: '$label ${choices[i]}',
                ),
            ],
            onChanged: (next) => onChanged(next == value ? null : next),
          ),
        ] else
          Wrap(
            spacing: AppSpacing.xs,
            children: [
              for (var i = 0; i < choices.length; i++)
                ChoiceChip(
                  label: Text(choices[i]),
                  selected: value == i,
                  onSelected: (selected) => onChanged(selected ? i : null),
                ),
            ],
          ),
      ],
    ),
  );
}
