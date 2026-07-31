import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/navigation/app_routes.dart';
import '../../core/theme/app_icons.dart';
import '../../features/coach/application/coach_turn_notice.dart';
import '../../features/coach/presentation/providers/coach_providers.dart';

class AppHeaderActions extends ConsumerWidget {
  const AppHeaderActions({
    this.pageActions = const <Widget>[],
    this.settingsSelected = false,
    super.key,
  });

  final List<Widget> pageActions;
  final bool settingsSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notice = ref.watch(coachTurnNoticeProvider);
    return Wrap(
      key: const ValueKey('global-header-actions'),
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: [
        ...pageActions.map(
          (action) => ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            child: action,
          ),
        ),
        if (notice != null)
          _CoachNoticeButton(
            notice: notice,
            onPressed: () => _showCoachNotice(context, notice),
          ),
        _SettingsButton(selected: settingsSelected),
      ],
    );
  }
}

class _CoachNoticeButton extends StatelessWidget {
  const _CoachNoticeButton({
    required this.notice,
    required this.onPressed,
  });

  final CoachTurnNotice notice;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: notice.semanticsLabel,
      button: true,
      excludeSemantics: true,
      child: Tooltip(
        message: notice.semanticsLabel,
        child: SizedBox.square(
          dimension: 44,
          child: IconButton(
            key: const ValueKey('global-header-coach-notice'),
            onPressed: onPressed,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(
              width: 44,
              height: 44,
            ),
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(AppIcons.psychologyOutlined),
                Positioned(
                  right: -7,
                  top: -7,
                  child: ExcludeSemantics(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.error,
                        shape: BoxShape.circle,
                      ),
                      child: SizedBox.square(
                        dimension: 18,
                        child: Center(
                          child: Text(
                            '!',
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                  color: Theme.of(context).colorScheme.onError,
                                ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsButton extends StatelessWidget {
  const _SettingsButton({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final router = GoRouter.maybeOf(context);
    final tooltip = selected ? 'Settings, current page' : 'Settings';
    final button = IconButton(
      key: const ValueKey('global-header-settings'),
      tooltip: tooltip,
      onPressed: selected
          ? () {}
          : router == null
              ? null
              : () => context.push(AppRoutes.settings),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 44, height: 44),
      style: selected
          ? IconButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
            )
          : null,
      icon: Icon(selected ? AppIcons.settings : AppIcons.settingsOutlined),
    );
    if (!selected) return button;
    return Semantics(
      selected: true,
      child: button,
    );
  }
}

void _showCoachNotice(BuildContext context, CoachTurnNotice notice) {
  final messenger = ScaffoldMessenger.of(context);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        key: ValueKey('coach-turn-notice-${notice.requestId}'),
        behavior: SnackBarBehavior.floating,
        showCloseIcon: true,
        duration: const Duration(minutes: 5),
        content: Text(notice.message),
      ),
    );
}
