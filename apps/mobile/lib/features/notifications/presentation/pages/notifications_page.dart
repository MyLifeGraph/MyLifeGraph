import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../../../core/supabase/supabase_providers.dart';
import '../../../../core/supabase/supabase_tables.dart';
import '../../../../core/widgets/async_value_view.dart';
import '../../domain/entities/app_notification.dart';
import '../providers/notifications_providers.dart';

enum _AlertTarget {
  dailyCheckIn,
  deepWork,
}

class NotificationsPage extends ConsumerStatefulWidget {
  const NotificationsPage({super.key});

  @override
  ConsumerState<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends ConsumerState<NotificationsPage> {
  final Set<String> _doneIds = {};

  @override
  Widget build(BuildContext context) {
    final notifications = ref.watch(notificationsProvider);

    return AsyncValueView(
      value: notifications,
      data: (items) => _AlertsHome(
        alerts: _alertsFromNotifications(items),
        doneIds: _doneIds,
        onOpen: _openAlert,
        onDone: (id) {
          setState(() {
            _doneIds.add(id);
          });
          _markAlertRead(id);
        },
      ),
    );
  }

  Future<void> _markAlertRead(String id) async {
    final client = ref.read(supabaseClientProvider);
    if (client == null) {
      return;
    }
    try {
      await client
          .from(SupabaseTables.notifications)
          .update({'is_read': true}).eq('id', id);
      ref.invalidate(notificationsProvider);
    } catch (_) {
      return;
    }
  }

  List<_AlertItem> _alertsFromNotifications(List<AppNotification> items) {
    return items.map((notification) {
      final target = notification.id.contains('focus')
          ? _AlertTarget.deepWork
          : _AlertTarget.dailyCheckIn;

      return _AlertItem(
        id: notification.id,
        title: switch (notification.id) {
          'focus_window' => 'Deadline approaching',
          'recovery_check' => 'Sleep debt warning',
          _ => notification.title,
        },
        body: switch (notification.id) {
          'focus_window' =>
            'Prepare product review is due soon. Plan one protected deep-work session before the deadline pressure peaks.',
          'recovery_check' =>
            'Your latest sleep entry is below your usual recovery range. Keep today\'s plan lighter if possible.',
          _ => notification.body,
        },
        priority: notification.isRead ? 'medium' : 'high',
        accent: target == _AlertTarget.deepWork
            ? const Color(0xFFFFA42E)
            : const Color(0xFF20B9FF),
        icon: target == _AlertTarget.deepWork
            ? Icons.error_outline
            : Icons.health_and_safety_outlined,
        target: target,
      );
    }).toList();
  }

  void _openAlert(_AlertItem alert) {
    context.go(
      alert.target == _AlertTarget.deepWork
          ? AppRoutes.deepWork
          : AppRoutes.dailyCheckIn,
    );
  }
}

class _AlertsHome extends StatelessWidget {
  const _AlertsHome({
    required this.alerts,
    required this.doneIds,
    required this.onOpen,
    required this.onDone,
  });

  final List<_AlertItem> alerts;
  final Set<String> doneIds;
  final ValueChanged<_AlertItem> onOpen;
  final ValueChanged<String> onDone;

  @override
  Widget build(BuildContext context) {
    final unreadCount =
        alerts.where((alert) => !doneIds.contains(alert.id)).length;
    final deadlineCount =
        alerts.where((alert) => alert.target == _AlertTarget.deepWork).length;

    return SafeArea(
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.xl,
            ),
            sliver: SliverList.list(
              children: [
                const _AlertsHeader(),
                const SizedBox(height: AppSpacing.xl),
                _AlertSummaryGrid(
                  unreadCount: unreadCount,
                  deadlineCount: deadlineCount,
                ),
                const SizedBox(height: AppSpacing.xl),
                ...alerts.map(
                  (alert) => Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.md),
                    child: _AlertCard(
                      alert: alert,
                      isDone: doneIds.contains(alert.id),
                      onOpen: () => onOpen(alert),
                      onDone: () => onDone(alert.id),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AlertsHeader extends StatelessWidget {
  const _AlertsHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'REMINDER AGENT',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontSize: 13,
                      letterSpacing: 4,
                    ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'Alerts',
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                      fontSize: 52,
                      height: 1,
                    ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'Timetable-aware nudges for deadlines, recovery, screen time, sleep, and low-energy days.',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: const Color(0xFFA8B5BE),
                      height: 1.55,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AlertSummaryGrid extends StatelessWidget {
  const _AlertSummaryGrid({
    required this.unreadCount,
    required this.deadlineCount,
  });

  final int unreadCount;
  final int deadlineCount;

  @override
  Widget build(BuildContext context) {
    final metrics = [
      _AlertMetric(
        icon: Icons.notifications_none,
        value: '$unreadCount',
        label: 'Unread',
        color: Theme.of(context).colorScheme.primary,
      ),
      _AlertMetric(
        icon: Icons.event_busy_outlined,
        value: '$deadlineCount',
        label: 'Deadlines',
        color: const Color(0xFFFFA42E),
      ),
      const _AlertMetric(
        icon: Icons.health_and_safety_outlined,
        value: 'On',
        label: 'Coaching',
        color: Color(0xFF20B9FF),
      ),
    ];

    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: AppSpacing.sm,
      childAspectRatio: 0.82,
      children:
          metrics.map((metric) => _AlertMetricCard(metric: metric)).toList(),
    );
  }
}

class _AlertMetricCard extends StatelessWidget {
  const _AlertMetricCard({required this.metric});

  final _AlertMetric metric;

  @override
  Widget build(BuildContext context) {
    return _AlertsPanel(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(metric.icon, color: metric.color, size: 30),
          const Spacer(),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              metric.value,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(metric.label, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _AlertCard extends StatelessWidget {
  const _AlertCard({
    required this.alert,
    required this.isDone,
    required this.onOpen,
    required this.onDone,
  });

  final _AlertItem alert;
  final bool isDone;
  final VoidCallback onOpen;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: isDone ? 0.45 : 1,
      duration: const Duration(milliseconds: 180),
      child: _AlertsPanel(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: alert.accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(alert.icon, color: alert.accent, size: 30),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        alert.title,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      _PriorityBadge(priority: alert.priority),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    alert.body,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: const Color(0xFFA8B5BE),
                          height: 1.55,
                        ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      FilledButton(
                        onPressed: onOpen,
                        child: const Text('Open'),
                      ),
                      OutlinedButton.icon(
                        onPressed: isDone ? null : onDone,
                        icon: const Icon(Icons.check),
                        label: Text(isDone ? 'Done' : 'Done'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PriorityBadge extends StatelessWidget {
  const _PriorityBadge({required this.priority});

  final String priority;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF242B34),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(priority, style: Theme.of(context).textTheme.labelLarge),
    );
  }
}

class _AlertsPanel extends StatelessWidget {
  const _AlertsPanel({
    required this.child,
    required this.padding,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: const Color(0xFF122329),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFF2A424A), width: 2),
      ),
      child: child,
    );
  }
}

class _AlertMetric {
  const _AlertMetric({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color color;
}

class _AlertItem {
  const _AlertItem({
    required this.id,
    required this.title,
    required this.body,
    required this.priority,
    required this.accent,
    required this.icon,
    required this.target,
  });

  final String id;
  final String title;
  final String body;
  final String priority;
  final Color accent;
  final IconData icon;
  final _AlertTarget target;
}
