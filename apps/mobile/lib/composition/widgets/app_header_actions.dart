import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/constants/app_radii.dart';
import '../../core/navigation/app_routes.dart';
import '../../core/theme/app_icons.dart';
import '../../core/theme/app_visual_tokens.dart';
import '../../core/widgets/app_surface.dart';
import '../../features/coach/application/coach_turn_notice.dart';
import '../../features/coach/presentation/providers/coach_providers.dart';
import '../../core/capabilities/app_surface_capabilities.dart';
import '../../features/focus_protection/application/focus_protection_gateway.dart';

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
    final actions = Wrap(
      key: const ValueKey('global-header-actions'),
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 0,
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
        if (!settingsSelected) ...[
          IconButton(
            key: const ValueKey('global-header-inbox'),
            tooltip: 'Inbox',
            onPressed: GoRouter.maybeOf(context) == null
                ? null
                : () => context.push(AppRoutes.alerts),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 44, height: 44),
            icon: const Icon(AppIcons.inboxOutlined),
          ),
          if (ref.watch(focusProtectionPlatformSupportedProvider) &&
              ref
                  .watch(appSurfaceCapabilitiesProvider)
                  .canUseDeviceFocusProtection)
            IconButton(
              key: const ValueKey('global-header-blocking'),
              tooltip: 'App blocking',
              onPressed: GoRouter.maybeOf(context) == null
                  ? null
                  : () => context.push(AppRoutes.focusProtection),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 44, height: 44),
              icon: const Icon(AppIcons.shieldOutlined),
            ),
          const _SettingsButton(selected: false),
        ],
      ],
    );
    if (settingsSelected && notice == null && pageActions.isEmpty) {
      return actions;
    }
    return AppSurface(
      key: const ValueKey('header-action-island'),
      variant: AppSurfaceVariant.raised,
      radius: AppRadii.pill,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: 2,
      ),
      child: IconButtonTheme(
        data: IconButtonThemeData(
          style: (IconButtonTheme.of(context).style ?? const ButtonStyle())
              .copyWith(
                backgroundColor: const WidgetStatePropertyAll(
                  Colors.transparent,
                ),
                // One shared glass surface, not a tiny glass tile per icon.
                backgroundBuilder: (context, states, child) =>
                    child ?? const SizedBox.shrink(),
                shape: const WidgetStatePropertyAll(CircleBorder()),
                side: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.focused)
                      ? BorderSide(color: context.visualTokens.focus, width: 2)
                      : BorderSide.none,
                ),
              ),
        ),
        child: actions,
      ),
    );
  }
}

class _CoachNoticeButton extends StatelessWidget {
  const _CoachNoticeButton({required this.notice, required this.onPressed});

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
            constraints: const BoxConstraints.tightFor(width: 44, height: 44),
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
                            style: Theme.of(context).textTheme.labelSmall
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
    return Semantics(selected: true, child: button);
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
