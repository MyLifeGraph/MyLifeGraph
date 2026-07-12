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
import '../widgets/daily_capture_controls.dart';

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
          icon: Icons.nights_stay_outlined,
          title: 'Evening Shutdown',
          subtitle: 'Close today with stress context and tomorrow priority',
          onTap: () => context.go(AppRoutes.quickMoodCheckIn),
        ),
        _ActionTile(
          icon: Icons.wb_sunny_outlined,
          title: 'Morning Calibration',
          subtitle: 'Sleep, current energy, and day shape',
          onTap: () => context.go(AppRoutes.morningCalibration),
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
          _ActionTile(
            icon: Icons.timer_outlined,
            title: 'Focus session',
            subtitle: 'Start a real timed block linked to a task or habit',
            onTap: () => context.go(AppRoutes.deepWork),
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

  final DailyCaptureEntry draft;
  final bool isLocal;

  @override
  Widget build(BuildContext context) {
    final signals = <String>[
      if (draft.mood != null) 'Mood ${draft.mood}',
      if (draft.energy != null) 'Energy ${draft.energy}',
      if (draft.sleepHours != null)
        'Sleep ${formatCaptureHours(draft.sleepHours!)} h',
      if (draft.stress != null) 'Stress ${draft.stress}',
    ];
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
                  'Today\'s saved captures',
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
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              _CaptureStatus(
                label: 'Evening',
                saved: draft.evening != null,
              ),
              _CaptureStatus(
                label: 'Morning',
                saved: draft.morning != null,
              ),
            ],
          ),
          if (signals.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              signals.join(' | '),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
          if (draft.morning?.dayShape != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Day shape: ${_readableCode(draft.morning!.dayShape!.code)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (draft.evening?.stressSource != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Stress: ${_readableCode(draft.evening!.stressSource!.code)} · '
              '${_readableCode(draft.evening!.stressControllability!.code)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

class _CaptureStatus extends StatelessWidget {
  const _CaptureStatus({required this.label, required this.saved});

  final String label;
  final bool saved;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .primary
            .withValues(alpha: saved ? 0.16 : 0.06),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text('$label ${saved ? 'saved' : 'not saved'}'),
    );
  }
}

String _readableCode(String value) => value.replaceAll('_', ' ');

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
