import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:my_life_graph/composition/quick_check_in_providers.dart';
import 'package:my_life_graph/composition/widgets/app_header_actions.dart';
import 'package:my_life_graph/core/theme/app_icons.dart';

import '../../../../core/capabilities/app_surface_capabilities.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_page.dart';
import '../../../../core/widgets/app_surface.dart';

class QuickActionPage extends ConsumerWidget {
  const QuickActionPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final latestCheckIn = ref.watch(latestQuickCheckInProvider);
    final loadedCheckIn = switch (latestCheckIn) {
      AsyncData(:final value) => value,
      _ => null,
    };
    final capabilities = ref.watch(appSurfaceCapabilitiesProvider);

    return AppPage(
      title: 'Quick actions',
      subtitle: 'Add a check-in or start something you planned',
      actions: const [AppHeaderActions()],
      children: [
        _ActionTile(
          icon: AppIcons.nightsStayOutlined,
          title: 'Evening check-in',
          subtitle: 'Close today with three ratings and useful context',
          completedToday: loadedCheckIn?.evening != null,
          onTap: () => context.push(AppRoutes.quickMoodCheckIn),
        ),
        _ActionTile(
          icon: AppIcons.wbSunnyOutlined,
          title: 'Morning check-in',
          subtitle: 'Add sleep timing, sleep quality, and current energy',
          completedToday: loadedCheckIn?.morning != null,
          onTap: () => context.push(AppRoutes.morningCalibration),
        ),
        ...latestCheckIn.when(
          data: (_) => const <Widget>[],
          loading: () => const [LinearProgressIndicator(minHeight: 2)],
          error: (_, __) => [
            _SavedCheckInError(
              onRetry: () => ref.invalidate(latestQuickCheckInProvider),
            ),
          ],
        ),
        if (capabilities.canUseSyncedHabits) ...[
          _ActionTile(
            icon: AppIcons.taskAltOutlined,
            title: 'Habit completion',
            subtitle: 'Track consistency signals',
            onTap: () => context.push(AppRoutes.habitCompletion),
          ),
          _ActionTile(
            icon: AppIcons.timerOutlined,
            title: 'Focus',
            subtitle: 'Start a real timed block linked to a task or habit',
            onTap: () => context.push(AppRoutes.deepWork),
          ),
        ],
      ],
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
          icon: const Icon(AppIcons.refresh),
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
    this.completedToday = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool completedToday;

  @override
  Widget build(BuildContext context) {
    final semanticLabel = completedToday
        ? '$title. $subtitle. Completed today. '
            'Opens today\'s saved answers for editing.'
        : '$title. $subtitle.';
    return Semantics(
      label: semanticLabel,
      button: true,
      onTap: onTap,
      excludeSemantics: true,
      child: AppCard(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
                const Icon(AppIcons.chevronRight),
              ],
            ),
            if (completedToday) ...[
              const SizedBox(height: AppSpacing.sm),
              const AppStatusPill(
                label: 'Completed today',
                icon: AppIcons.check,
                tone: AppStatusTone.success,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
