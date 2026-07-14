import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/capabilities/app_surface_capabilities.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../application/notifications_controller.dart';
import '../../domain/entities/app_notification.dart';
import '../../domain/entities/notification_action_target.dart';
import '../../domain/entities/notification_lifecycle.dart';
import '../providers/notifications_providers.dart';

class NotificationsPage extends ConsumerWidget {
  const NotificationsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(notificationsProvider);
    final controller = ref.read(notificationsProvider.notifier);
    final capabilities = ref.watch(appSurfaceCapabilitiesProvider);
    final resolver = NotificationActionTargetResolver(
      canUseSyncedHabits: capabilities.canUseSyncedHabits,
      canUseFocusSessions: capabilities.canUseSyncedExecution,
    );

    if (state.isLoading && state.items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.loadError != null && state.items.isEmpty) {
      return _NotificationsError(onRetry: controller.load);
    }
    final alerts = state.items
        .map(
          (notification) => _AlertItem(
            notification: notification,
            target: resolver.resolve(notification.actionUrl),
            actionState: state.actionFor(notification.id),
          ),
        )
        .toList(growable: false);
    return _NotificationsHome(
      alerts: alerts,
      useDemoData: capabilities.isLocalDemo,
      isRefreshing: state.isLoading,
      refreshError: state.loadError,
      canManageLifecycle: state.canManageLifecycle,
      onReload: controller.load,
      onOpen: (target) => context.go(target.location),
      onLifecycleAction: controller.performAction,
      onRetryAction: controller.retry,
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
              'Could not load inbox.',
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

class _NotificationsRefreshError extends StatelessWidget {
  const _NotificationsRefreshError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: _NotificationsPanel(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.sync_problem_outlined),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Could not refresh inbox.',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  const Text('Previously loaded items are still shown.'),
                  const SizedBox(height: AppSpacing.sm),
                  OutlinedButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Reload inbox'),
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

class _NotificationsHome extends StatelessWidget {
  const _NotificationsHome({
    required this.alerts,
    required this.useDemoData,
    required this.isRefreshing,
    required this.refreshError,
    required this.canManageLifecycle,
    required this.onReload,
    required this.onOpen,
    required this.onLifecycleAction,
    required this.onRetryAction,
  });

  final List<_AlertItem> alerts;
  final bool useDemoData;
  final bool isRefreshing;
  final Object? refreshError;
  final bool canManageLifecycle;
  final VoidCallback onReload;
  final ValueChanged<NotificationActionTarget> onOpen;
  final Future<bool> Function(
    String notificationId,
    NotificationLifecycleCommand command,
  ) onLifecycleAction;
  final Future<bool> Function(String notificationId) onRetryAction;

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
                if (isRefreshing) ...[
                  const SizedBox(height: AppSpacing.md),
                  const LinearProgressIndicator(
                    key: ValueKey('notifications-refresh-progress'),
                  ),
                ],
                if (refreshError != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  _NotificationsRefreshError(onRetry: onReload),
                ],
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
                        canManageLifecycle: canManageLifecycle,
                        onOpen: alert.target == null
                            ? null
                            : () => onOpen(alert.target!),
                        onLifecycleAction: (command) => onLifecycleAction(
                          alert.notification.id,
                          command,
                        ),
                        onRetryAction: () =>
                            onRetryAction(alert.notification.id),
                        onReload: onReload,
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
    final copy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Inbox',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          useDemoData
              ? 'These are local example items. They are not synced or sent '
                  'as notifications. Up to the latest 30 items are shown; '
                  'the counts cover only the items shown.'
              : 'Stored inbox items can be marked read or dismissed here. '
                  'This app does not send notifications yet. Up to the '
                  'latest 30 items are shown; the counts cover only the '
                  'items shown.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
    final origin = Container(
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
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 360) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              copy,
              const SizedBox(height: AppSpacing.md),
              origin,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: copy),
            const SizedBox(width: AppSpacing.md),
            origin,
          ],
        );
      },
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
    final isLight = Theme.of(context).brightness == Brightness.light;
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
        color: isLight ? const Color(0xFF3F51B5) : const Color(0xFF8EA7FF),
      ),
      _NotificationMetric(
        key: const ValueKey('notifications-action-count'),
        icon: Icons.arrow_forward,
        value: '$actionableCount',
        label: 'Open links',
        color: isLight ? const Color(0xFF8A4B08) : const Color(0xFFFFA42E),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final scaledBodySize = MediaQuery.textScalerOf(context).scale(14);
        if (constraints.maxWidth < 340 || scaledBodySize > 17) {
          return Column(
            children: [
              for (var index = 0; index < metrics.length; index++) ...[
                _NotificationMetricCard(
                  metric: metrics[index],
                  compact: true,
                ),
                if (index < metrics.length - 1)
                  const SizedBox(height: AppSpacing.sm),
              ],
            ],
          );
        }
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
  const _NotificationMetricCard({
    required this.metric,
    this.compact = false,
  });

  final _NotificationMetric metric;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final content = compact
        ? Row(
            children: [
              Icon(metric.icon, color: metric.color, size: 28),
              const SizedBox(width: AppSpacing.md),
              Text(
                metric.value,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  metric.label,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
          )
        : Column(
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
              Text(
                metric.label,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          );
    return _NotificationsPanel(
      key: metric.key,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: content,
    );
  }
}

class _EmptyNotifications extends StatelessWidget {
  const _EmptyNotifications();

  @override
  Widget build(BuildContext context) {
    return const _NotificationsPanel(
      padding: EdgeInsets.all(AppSpacing.lg),
      child: Text('Your inbox is empty.'),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({
    required this.alert,
    required this.canManageLifecycle,
    required this.onOpen,
    required this.onLifecycleAction,
    required this.onRetryAction,
    required this.onReload,
  });

  final _AlertItem alert;
  final bool canManageLifecycle;
  final VoidCallback? onOpen;
  final Future<bool> Function(NotificationLifecycleCommand command)
      onLifecycleAction;
  final Future<bool> Function() onRetryAction;
  final VoidCallback onReload;

  @override
  Widget build(BuildContext context) {
    final notification = alert.notification;
    final accent = _accentForPriority(context, notification.priority);

    final icon = Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ExcludeSemantics(
        child: Icon(
          _iconForType(notification.type),
          color: accent,
          size: 26,
        ),
      ),
    );
    final content = _NotificationCardContent(
      alert: alert,
      canManageLifecycle: canManageLifecycle,
      onOpen: onOpen,
      onLifecycleAction: onLifecycleAction,
      onRetryAction: onRetryAction,
      onReload: onReload,
    );

    return Semantics(
      container: true,
      label: '${notification.isRead ? 'Read' : 'Unread'} notification: '
          '${notification.title}',
      child: _NotificationsPanel(
        key: ValueKey('notification-${notification.id}'),
        padding: const EdgeInsets.all(AppSpacing.md),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 360 ||
                MediaQuery.textScalerOf(context).scale(14) > 18;
            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  icon,
                  const SizedBox(height: AppSpacing.md),
                  content,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                icon,
                const SizedBox(width: AppSpacing.md),
                Expanded(child: content),
              ],
            );
          },
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

  Color _accentForPriority(BuildContext context, String priority) {
    if (Theme.of(context).brightness == Brightness.light) {
      return switch (priority.toLowerCase()) {
        'critical' => const Color(0xFFB3261E),
        'high' => const Color(0xFF8A4B08),
        'low' => const Color(0xFF18794E),
        _ => const Color(0xFF0061A4),
      };
    }
    return switch (priority.toLowerCase()) {
      'critical' => const Color(0xFFFF6B6B),
      'high' => const Color(0xFFFFA42E),
      'low' => const Color(0xFF5BE7C4),
      _ => const Color(0xFF20B9FF),
    };
  }
}

class _NotificationCardContent extends StatelessWidget {
  const _NotificationCardContent({
    required this.alert,
    required this.canManageLifecycle,
    required this.onOpen,
    required this.onLifecycleAction,
    required this.onRetryAction,
    required this.onReload,
  });

  final _AlertItem alert;
  final bool canManageLifecycle;
  final VoidCallback? onOpen;
  final Future<bool> Function(NotificationLifecycleCommand command)
      onLifecycleAction;
  final Future<bool> Function() onRetryAction;
  final VoidCallback onReload;

  @override
  Widget build(BuildContext context) {
    final notification = alert.notification;
    final operation = alert.actionState;
    final isPending = operation?.isPending == true;
    final lifecycleBlocked = isPending || operation?.error != null;
    final readCommand = notification.isRead
        ? NotificationLifecycleCommand.markUnread
        : NotificationLifecycleCommand.markRead;
    final readLabel = notification.isRead ? 'Mark unread' : 'Mark read';

    return Column(
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
              key: ValueKey('notification-read-state-${notification.id}'),
              label: notification.isRead ? 'Read' : 'Unread',
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          notification.body,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.45),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          DateFormat('MMM d, HH:mm').format(notification.createdAt.toLocal()),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (notification.dueAt != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Available since '
            '${DateFormat('MMM d, HH:mm').format(notification.dueAt!.toLocal())}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        if (canManageLifecycle) ...[
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              Semantics(
                button: true,
                label: '$readLabel notification ${notification.title}',
                excludeSemantics: true,
                child: OutlinedButton.icon(
                  key: ValueKey('notification-read-toggle-${notification.id}'),
                  onPressed: lifecycleBlocked
                      ? null
                      : () => onLifecycleAction(readCommand),
                  icon: Icon(
                    notification.isRead
                        ? Icons.mark_email_unread_outlined
                        : Icons.drafts_outlined,
                  ),
                  label: Text(readLabel),
                ),
              ),
              Semantics(
                button: true,
                label: 'Dismiss notification ${notification.title}',
                excludeSemantics: true,
                child: TextButton.icon(
                  key: ValueKey('notification-dismiss-${notification.id}'),
                  onPressed: lifecycleBlocked
                      ? null
                      : () => onLifecycleAction(
                            NotificationLifecycleCommand.dismiss,
                          ),
                  icon: const Icon(Icons.close),
                  label: const Text('Dismiss'),
                ),
              ),
            ],
          ),
        ],
        if (isPending) ...[
          const SizedBox(height: AppSpacing.md),
          Semantics(
            liveRegion: true,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: AppSpacing.sm),
                Flexible(
                  child: Text(_pendingCopy(operation!.command)),
                ),
              ],
            ),
          ),
        ],
        if (operation?.error != null) ...[
          const SizedBox(height: AppSpacing.md),
          _NotificationActionError(
            notification: notification,
            operation: operation!,
            onRetry: onRetryAction,
            onReload: onReload,
          ),
        ],
        if (onOpen != null) ...[
          const SizedBox(height: AppSpacing.md),
          Semantics(
            button: true,
            label: 'Open notification ${notification.title}',
            excludeSemantics: true,
            child: FilledButton.icon(
              key: ValueKey('notification-open-${notification.id}'),
              onPressed: onOpen,
              icon: const Icon(Icons.arrow_forward),
              label: const Text('Open'),
            ),
          ),
        ],
      ],
    );
  }

  String _pendingCopy(NotificationLifecycleCommand command) {
    return switch (command) {
      NotificationLifecycleCommand.markRead => 'Marking as read…',
      NotificationLifecycleCommand.markUnread => 'Marking as unread…',
      NotificationLifecycleCommand.dismiss => 'Dismissing…',
    };
  }
}

class _NotificationActionError extends StatelessWidget {
  const _NotificationActionError({
    required this.notification,
    required this.operation,
    required this.onRetry,
    required this.onReload,
  });

  final AppNotification notification;
  final NotificationRowActionState operation;
  final Future<bool> Function() onRetry;
  final VoidCallback onReload;

  @override
  Widget build(BuildContext context) {
    final exact = operation.requiresExactRetry;
    final reloadRequired = operation.requiresReload;
    return Semantics(
      liveRegion: true,
      child: Container(
        key: ValueKey('notification-action-error-${notification.id}'),
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              exact
                  ? 'The action result is unknown. Retry sends the exact same request.'
                  : reloadRequired
                      ? 'This inbox item changed or is no longer available. Reload the inbox before acting again.'
                      : 'The inbox action could not be completed. Reload the inbox before trying again.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                if (exact)
                  Semantics(
                    button: true,
                    label: 'Retry inbox action for ${notification.title}',
                    excludeSemantics: true,
                    child: FilledButton.icon(
                      key: ValueKey(
                        'notification-action-retry-${notification.id}',
                      ),
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry exact request'),
                    ),
                  ),
                Semantics(
                  button: true,
                  label: 'Reload inbox for ${notification.title}',
                  excludeSemantics: true,
                  child: OutlinedButton(
                    key: ValueKey(
                      'notification-action-reload-${notification.id}',
                    ),
                    onPressed: onReload,
                    child: const Text('Reload inbox'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
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
  const _AlertItem({
    required this.notification,
    required this.target,
    required this.actionState,
  });

  final AppNotification notification;
  final NotificationActionTarget? target;
  final NotificationRowActionState? actionState;
}
