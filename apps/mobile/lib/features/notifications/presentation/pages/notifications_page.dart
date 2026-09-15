import 'package:flutter/material.dart';

import 'package:my_life_graph/core/constants/app_radii.dart';

import 'package:my_life_graph/core/theme/app_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/capabilities/app_surface_capabilities.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../../../core/theme/app_visual_tokens.dart';
import '../../../../core/widgets/app_surface.dart';
import '../../application/notifications_controller.dart';
import '../../domain/entities/app_notification.dart';
import '../../domain/entities/notification_action_target.dart';
import '../../domain/entities/notification_lifecycle.dart';
import '../../../../composition/notifications_providers.dart';

class NotificationsPage extends StatelessWidget {
  const NotificationsPage({super.key});

  @override
  Widget build(BuildContext context) => SafeArea(
    bottom: false,
    child: Column(
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: BackButton(
            onPressed: () {
              final router = GoRouter.maybeOf(context);
              if (router?.canPop() ?? false) {
                router!.pop();
              } else {
                router?.go(AppRoutes.dashboard);
              }
            },
          ),
        ),
        const Expanded(child: _NotificationsContent()),
      ],
    ),
  );
}

class _NotificationsContent extends ConsumerWidget {
  const _NotificationsContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(notificationsProvider);
    final controller = ref.read(notificationsProvider.notifier);
    final capabilities = ref.watch(appSurfaceCapabilitiesProvider);
    final resolver = NotificationActionTargetResolver(
      canUseSyncedHabits: capabilities.canUseSyncedHabits,
      canUseFocusSessions: capabilities.canUseSyncedExecution,
      canUseWeeklyReview: capabilities.canUseWeeklyReview,
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
      onOpen: (target) => GoRouter.of(context).push(target.location),
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
            const Icon(AppIcons.cloudOffOutlined, size: 36),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Could not load inbox.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(AppIcons.refresh),
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
            const Icon(AppIcons.syncProblemOutlined),
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
                    icon: const Icon(AppIcons.refresh),
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
              AppSpacing.sm,
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
              ? 'Local examples · not synced or sent. Counts cover up to 30 shown items.'
              : 'Latest 30 items · counts cover this list.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
    final origin = Container(
      key: const ValueKey('notifications-data-origin'),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadii.sm),
      ),
      child: Text(useDemoData ? 'Demo data' : 'Account data',
          style: Theme.of(context).textTheme.bodySmall),
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
    final tokens = context.visualTokens;
    final metrics = [
      _NotificationMetric(
        key: const ValueKey('notifications-unread-count'),
        icon: AppIcons.markEmailUnreadOutlined,
        value: '$unreadCount',
        label: 'Unread',
        color: Theme.of(context).colorScheme.primary,
      ),
      _NotificationMetric(
        key: const ValueKey('notifications-read-count'),
        icon: AppIcons.draftsOutlined,
        value: '$readCount',
        label: 'Read',
        color: tokens.info,
      ),
      _NotificationMetric(
        key: const ValueKey('notifications-action-count'),
        icon: AppIcons.arrowForward,
        value: '$actionableCount',
        label: 'Open links',
        color: tokens.attention,
      ),
    ];

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var index = 0; index < metrics.length; index++) ...[
            Expanded(child: _NotificationMetricCard(metric: metrics[index])),
            if (index < metrics.length - 1) const SizedBox(width: AppSpacing.sm),
          ],
        ],
      ),
    );
  }
}

class _NotificationMetricCard extends StatelessWidget {
  const _NotificationMetricCard({
    required this.metric,
  });

  final _NotificationMetric metric;

  @override
  Widget build(BuildContext context) {
    final content = Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(metric.icon, color: metric.color, size: 18),
                  const SizedBox(width: AppSpacing.xs),
                  Flexible(child: Text(metric.value,
                    style: Theme.of(context).textTheme.titleMedium)),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                metric.label,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          );
    return _NotificationsPanel(
      key: metric.key,
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: content,
    );
  }
}

class _EmptyNotifications extends StatelessWidget {
  const _EmptyNotifications();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: true,
      child: const _NotificationsPanel(
        padding: EdgeInsets.all(AppSpacing.lg),
        child: Text('Your inbox is empty.'),
      ),
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
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppRadii.sm),
      ),
      child: ExcludeSemantics(
        child: Icon(
          _iconForType(notification.type),
          color: accent,
          size: 20,
        ),
      ),
    );
    final content = _NotificationCardContent(
      categoryIcon: icon,
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
        onTap: onOpen,
        padding: const EdgeInsets.all(AppSpacing.md),
        child: content,
      ),
    );
  }

  IconData _iconForType(String type) {
    return switch (type.toLowerCase()) {
      'deadline' => AppIcons.eventBusyOutlined,
      'warning' => AppIcons.warningAmberOutlined,
      'summary' => AppIcons.summarizeOutlined,
      'reminder' => AppIcons.notificationsNone,
      _ => AppIcons.notificationsNone,
    };
  }

  Color _accentForPriority(BuildContext context, String priority) {
    final tokens = context.visualTokens;
    return switch (priority.toLowerCase()) {
      'critical' => tokens.danger,
      'high' => tokens.attention,
      'low' => tokens.success,
      _ => tokens.info,
    };
  }
}

class _NotificationCardContent extends StatelessWidget {
  const _NotificationCardContent({
    required this.categoryIcon,
    required this.alert,
    required this.canManageLifecycle,
    required this.onOpen,
    required this.onLifecycleAction,
    required this.onRetryAction,
    required this.onReload,
  });

  final Widget categoryIcon;
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
    final lifecycleBlocked = isPending ||
        operation?.error != null ||
        operation?.committedRequiresReload == true;
    final readCommand = notification.isRead
        ? NotificationLifecycleCommand.markUnread
        : NotificationLifecycleCommand.markRead;
    final readLabel = notification.isRead ? 'Mark unread' : 'Mark read';

    // Disabled controls and gaps must not activate the card underneath.
    final actions = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {},
      excludeFromSemantics: true,
      child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (canManageLifecycle)
          Semantics(
            button: true,
            enabled: !lifecycleBlocked,
            label: '$readLabel notification ${notification.title}',
            excludeSemantics: true,
            child: SizedBox.square(
              dimension: 44,
              child: IconButton(
                key: ValueKey('notification-read-toggle-${notification.id}'),
                tooltip: readLabel,
                iconSize: 20,
                onPressed: lifecycleBlocked
                    ? null
                    : () => onLifecycleAction(readCommand),
                icon: Icon(notification.isRead
                    ? AppIcons.markEmailUnreadOutlined
                    : AppIcons.draftsOutlined),
              ),
            ),
          ),
        if (canManageLifecycle)
          Semantics(
            button: true,
            enabled: !lifecycleBlocked,
            label: 'Dismiss notification ${notification.title}',
            excludeSemantics: true,
            child: SizedBox.square(
              dimension: 44,
              child: IconButton(
                key: ValueKey('notification-dismiss-${notification.id}'),
                tooltip: 'Dismiss',
                iconSize: 20,
                onPressed: lifecycleBlocked
                    ? null
                    : () => onLifecycleAction(NotificationLifecycleCommand.dismiss),
                icon: const Icon(AppIcons.close),
              ),
            ),
          ),
        if (onOpen != null)
          Semantics(
            button: true,
            label: 'Open notification ${notification.title}',
            excludeSemantics: true,
            child: SizedBox.square(
              dimension: 44,
              child: IconButton.filledTonal(
                key: ValueKey('notification-open-${notification.id}'),
                tooltip: alert.target!.openLabel,
                iconSize: 20,
                onPressed: onOpen,
                icon: const Icon(AppIcons.arrowForward),
              ),
            ),
          ),
      ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final title = Text(notification.title,
                style: Theme.of(context).textTheme.titleMedium);
            if (!canManageLifecycle && onOpen == null) return title;
            if (constraints.maxWidth < 250 ||
                MediaQuery.textScalerOf(context).scale(14) > 18) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  title,
                  Align(alignment: Alignment.centerRight, child: actions),
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: title),
                const SizedBox(width: AppSpacing.xs),
                actions,
              ],
            );
          },
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            categoryIcon,
            _NotificationBadge(label: notification.type),
            _NotificationBadge(label: notification.priority),
            _NotificationBadge(
              key: ValueKey('notification-read-state-${notification.id}'),
              label: notification.isRead ? 'Read' : 'Unread',
            ),
            if (notification.isDeterministicallyGenerated)
              const _NotificationBadge(label: 'Rule-based reminder'),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          notification.body,
          style: Theme.of(context).textTheme.bodyMedium,
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
        if (notification.generationProvenance != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Based on ${_sourceLabel(notification.generationProvenance!.sourceKind)} '
            'for ${notification.deliveryDate} in '
            '${notification.generationProvenance!.timezone}.',
            key: ValueKey('notification-provenance-${notification.id}'),
            style: Theme.of(context).textTheme.bodySmall,
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
        if (operation?.committedRequiresReload == true) ...[
          const SizedBox(height: AppSpacing.md),
          Semantics(
            liveRegion: true,
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(AppRadii.sm),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Change saved. Inbox could not reload.',
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  OutlinedButton.icon(
                    onPressed: onRetryAction,
                    icon: const Icon(AppIcons.refresh),
                    label: const Text('Reload Inbox'),
                  ),
                ],
              ),
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

  String _sourceLabel(String sourceKind) {
    return switch (sourceKind) {
      'daily_state' => 'your current check-in state',
      'weekly_review' => 'the completed Weekly Review',
      _ => 'saved app data',
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
          borderRadius: BorderRadius.circular(AppRadii.sm),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              exact
                  ? 'The result could not be confirmed. The item is unchanged here; retry without changing the action.'
                  : reloadRequired
                      ? 'This inbox item changed or is no longer available. Reload the inbox before acting again.'
                      : 'The inbox action could not be completed. Reload the inbox before trying again.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
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
                      icon: const Icon(AppIcons.refresh),
                      label: const Text('Retry unchanged'),
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
        borderRadius: BorderRadius.circular(AppRadii.sm),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelMedium),
    );
  }
}

class _NotificationsPanel extends StatelessWidget {
  const _NotificationsPanel({
    required this.child,
    required this.padding,
    this.onTap,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return AppSurface(
      variant: onTap == null
          ? AppSurfaceVariant.subtle
          : AppSurfaceVariant.interactive,
      onTap: onTap,
      padding: padding,
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
