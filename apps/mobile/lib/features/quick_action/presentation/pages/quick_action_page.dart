import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_page.dart';

class QuickActionPage extends StatelessWidget {
  const QuickActionPage({super.key});

  @override
  Widget build(BuildContext context) {
    return AppPage(
      title: 'Add signal',
      subtitle: 'Capture the context your future recommendations need',
      children: [
        _ActionTile(
          icon: Icons.mood_outlined,
          title: 'Mood check-in',
          subtitle: 'Energy, stress, clarity',
          onTap: () => context.go(AppRoutes.quickMoodCheckIn),
        ),
        const _ActionTile(
          icon: Icons.fitness_center_outlined,
          title: 'Lifestyle entry',
          subtitle: 'Sleep, movement, nutrition',
        ),
        _ActionTile(
          icon: Icons.task_alt_outlined,
          title: 'Habit completion',
          subtitle: 'Track consistency signals',
          onTap: () => context.go(AppRoutes.habitCompletion),
        ),
        const _ActionTile(
          icon: Icons.note_alt_outlined,
          title: 'Reflection note',
          subtitle: 'Add qualitative context',
        ),
      ],
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      child: Row(
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: AppSpacing.xs),
                Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
          const Icon(Icons.chevron_right),
        ],
      ),
    );
  }
}
