import 'package:flutter/material.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../domain/entities/dashboard_snapshot.dart';

class PlanItemTile extends StatelessWidget {
  const PlanItemTile({required this.item, super.key});

  final PlanItem item;

  @override
  Widget build(BuildContext context) {
    final color = item.isCompleted
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.secondary;

    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.title, style: Theme.of(context).textTheme.labelLarge),
              Text(
                '${item.time} · ${item.type}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
        Icon(
          item.isCompleted ? Icons.check_circle : Icons.radio_button_unchecked,
          color: color,
        ),
      ],
    );
  }
}
