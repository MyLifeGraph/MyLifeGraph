import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/capabilities/app_surface_capabilities.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../domain/entities/app_notification.dart';
import '../../domain/entities/notification_action_target.dart';
import '../providers/notifications_providers.dart';

class NotificationsPage extends ConsumerWidget {
  const NotificationsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifications = ref.watch(notificationsProvider);
    final capabilities = ref.watch(appSurfaceCapabilitiesProvider);
    final resolver = NotificationActionTargetResolver(
      canUseSyncedHabits: capabilities.canUseSyncedHabits,
      canUseFocusSessions: capabilities.canUseSyncedExecution,
    );

    return notifications.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) => _NotificationsError(
        onRetry: () => ref.invalidate(notificationsProvider),
      ),
      data: (items) {
        final alerts = items
            .map(
              (notification) => _AlertItem(
                notification: notification,
                target: resolver.resolve(notification.actionUrl),
              ),
            )
            .toList();
        return _NotificationsHome(
          alerts: alerts,
          useDemoData: capabilities.isLocalDemo,
          onOpen: (target) => context.go(target.location),
        );
      },
    );
  }
}

class _NotificationsError extends StatelessWidget {
  const _NotificationsError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 36),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Could not load notifications.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationsHome extends StatelessWidget {
  const _NotificationsHome({
    required this.alerts,
    required this.useDemoData,
    required this.onOpen,
  });

  final List<_AlertItem> alerts;
  final bool useDemoData;
  final ValueChanged<NotificationActionTarget> onOpen;

  @override
  Widget build(BuildContext context) {
    final unreadCount =
        alerts.where((alert) => !alert.notification.isRead).length;
    final readCount = alerts.length - unreadCount;
    final actionableCount =
        alerts.where((alert) => alert.target != null).length;

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
                _NotificationsHeader(useDemoData: useDemoData),
                const SizedBox(height: AppSpacing.xl),
                _NotificationSummaryGrid(
                  unreadCount: unreadCount,
                  readCount: readCount,
                  actionableCount: actionableCount,
                ),
                const SizedBox(height: AppSpacing.xl),
                if (alerts.isEmpty)
                  const _EmptyNotifications()
                else
                  ...alerts.map(
                    (alert) => Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: _NotificationCard(
                        alert: alert,
                        onOpen: alert.target == null
                            ? null
                            : () => onOpen(alert.target!),
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

class _NotificationsHeader extends StatelessWidget {
  const _NotificationsHeader({required this.useDemoData});

  final bool useDemoData;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            'Notifications',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
        ),
        Container(
          key: const ValueKey('notifications-data-origin'),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(useDemoData ? 'Demo data' : 'Account data'),
        ),
      ],
    );
  }
}

class _NotificationSummaryGrid extends StatelessWidget {
  const _NotificationSummaryGrid({
    required this.unreadCount,
    required this.readCount,
    required this.actionableCount,
  });

  final int unreadCount;
  final int readCount;
  final int actionableCount;

  @override
  Widget build(BuildContext context) {
    final metrics = [
      _NotificationMetric(
        key: const ValueKey('notifications-unread-count'),
        icon: Icons.mark_email_unread_outlined,
        value: '$unreadCount',
        label: 'Unread',
        color: Theme.of(context).colorScheme.primary,
      ),
      _NotificationMetric(
        key: const ValueKey('notifications-read-count'),
        icon: Icons.drafts_outlined,
        value: '$readCount',
        label: 'Read',
        color: const Color(0xFF8EA7FF),
      ),
      _NotificationMetric(
        key: const ValueKey('notifications-action-count'),
        icon: Icons.arrow_forward,
        value: '$actionableCount',
        label: 'Actions',
        color: const Color(0xFFFFA42E),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final childAspectRatio = switch (constraints.maxWidth) {
          >= 1100 => 3.2,
          >= 720 => 2.0,
          _ => 0.82,
        };
        return GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: AppSpacing.sm,
          childAspectRatio: childAspectRatio,
          children: metrics
              .map((metric) => _NotificationMetricCard(metric: metric))
              .toList(),
        );
      },
    );
  }
}

class _NotificationMetricCard extends StatelessWidget {
  const _NotificationMetricCard({required this.metric});

  final _NotificationMetric metric;

  @override
  Widget build(BuildContext context) {
    return _NotificationsPanel(
      key: metric.key,
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

class _EmptyNotifications extends StatelessWidget {
  const _EmptyNotifications();

  @override
  Widget build(BuildContext context) {
    return const _NotificationsPanel(
      padding: EdgeInsets.all(AppSpacing.lg),
      child: Text('No notifications yet.'),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({required this.alert, required this.onOpen});

  final _AlertItem alert;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final notification = alert.notification;
    final accent = _accentForPriority(notification.priority);

    return Opacity(
      opacity: notification.isRead ? 0.68 : 1,
      child: _NotificationsPanel(
        key: ValueKey('notification-${notification.id}'),
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                _iconForType(notification.type),
                color: accent,
                size: 26,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    notification.title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      _NotificationBadge(label: notification.type),
                      _NotificationBadge(label: notification.priority),
                      _NotificationBadge(
                        key: ValueKey(
                          'notification-read-state-${notification.id}',
                        ),
                        label: notification.isRead ? 'Read' : 'Unread',
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    notification.body,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          height: 1.45,
                        ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    DateFormat('MMM d, HH:mm').format(
                      notification.createdAt.toLocal(),
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (onOpen != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    FilledButton.icon(
                      key: ValueKey('notification-open-${notification.id}'),
                      onPressed: onOpen,
                      icon: const Icon(Icons.arrow_forward),
                      label: const Text('Open'),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _iconForType(String type) {
    return switch (type.toLowerCase()) {
      'deadline' => Icons.event_busy_outlined,
      'warning' => Icons.warning_amber_outlined,
      'summary' => Icons.summarize_outlined,
      'reminder' => Icons.notifications_none,
      _ => Icons.info_outline,
    };
  }

  Color _accentForPriority(String priority) {
    return switch (priority.toLowerCase()) {
      'critical' => const Color(0xFFFF6B6B),
      'high' => const Color(0xFFFFA42E),
      'low' => const Color(0xFF5BE7C4),
      _ => const Color(0xFF20B9FF),
    };
  }
}

class _NotificationBadge extends StatelessWidget {
  const _NotificationBadge({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelMedium),
    );
  }
}

class _NotificationsPanel extends StatelessWidget {
  const _NotificationsPanel({
    required this.child,
    required this.padding,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
      child: child,
    );
  }
}

class _NotificationMetric {
  const _NotificationMetric({
    required this.key,
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  final Key key;
  final IconData icon;
  final String value;
  final String label;
  final Color color;
}

class _AlertItem {
  const _AlertItem({required this.notification, required this.target});

  final AppNotification notification;
  final NotificationActionTarget? target;
}
