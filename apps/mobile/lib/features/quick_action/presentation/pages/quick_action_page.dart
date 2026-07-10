import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/capabilities/app_surface_capabilities.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_page.dart';
import '../../domain/quick_check_in.dart';
import '../providers/quick_check_in_providers.dart';

class QuickActionPage extends ConsumerWidget {
  const QuickActionPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final latestCheckIn = ref.watch(latestQuickCheckInProvider);
    final saveTarget = ref.watch(quickCheckInStoreProvider).target;
    final capabilities = ref.watch(appSurfaceCapabilitiesProvider);

    return AppPage(
      title: 'Add signal',
      subtitle: 'Capture the context your future recommendations need',
      children: [
        _ActionTile(
          icon: Icons.mood_outlined,
          title: 'Daily check-in',
          subtitle: 'Mood, energy, sleep, and stress',
          onTap: () => context.go(AppRoutes.quickMoodCheckIn),
        ),
        ...latestCheckIn.when(
          data: (draft) => draft == null
              ? const <Widget>[]
              : [
                  _SavedCheckInSummary(
                    draft: draft,
                    isLocal: saveTarget == QuickCheckInSaveTarget.guest,
                  ),
                ],
          loading: () => const [LinearProgressIndicator(minHeight: 2)],
          error: (_, __) => [
            _SavedCheckInError(
              onRetry: () => ref.invalidate(latestQuickCheckInProvider),
            ),
          ],
        ),
        if (capabilities.canUseSyncedHabits) ...[
          _ActionTile(
            icon: Icons.task_alt_outlined,
            title: 'Habit completion',
            subtitle: 'Track consistency signals',
            onTap: () => context.go(AppRoutes.habitCompletion),
          ),
          _ActionTile(
            icon: Icons.repeat_on_outlined,
            title: 'Habit management',
            subtitle: 'Create, edit, and pause targets',
            onTap: () => context.go(AppRoutes.habitManagement),
          ),
        ],
      ],
    );
  }
}

class _SavedCheckInSummary extends StatelessWidget {
  const _SavedCheckInSummary({
    required this.draft,
    required this.isLocal,
  });

  final QuickCheckInDraft draft;
  final bool isLocal;

  @override
  Widget build(BuildContext context) {
    final sleepHours = draft.sleepHours!;
    final sleep = sleepHours == sleepHours.roundToDouble()
        ? sleepHours.toInt().toString()
        : sleepHours.toStringAsFixed(1);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle_outline, size: 20),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Today\'s saved check-in',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Text(
                isLocal ? 'Local' : 'Synced',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Mood ${draft.mood} | Energy ${draft.energy} | '
            'Sleep $sleep h | Stress ${draft.stress}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class _SavedCheckInError extends StatelessWidget {
  const _SavedCheckInError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            'Today\'s saved check-in could not be loaded.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        IconButton(
          tooltip: 'Retry loading check-in',
          onPressed: onRetry,
          icon: const Icon(Icons.refresh),
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
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

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
