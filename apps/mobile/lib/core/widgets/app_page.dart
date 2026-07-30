import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../constants/app_spacing.dart';
import '../theme/app_icons.dart';

class AppPage extends StatelessWidget {
  const AppPage({
    required this.title,
    required this.children,
    this.subtitle,
    this.actions,
    this.backFallback,
    this.showBackForFallback = true,
    this.maxWidth = 1120,
    super.key,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;
  final List<Widget>? actions;
  final String? backFallback;
  final bool showBackForFallback;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final horizontalPadding = switch (constraints.maxWidth) {
            < 600 => AppSpacing.md,
            < 1000 => AppSpacing.lg,
            _ => AppSpacing.xl,
          };
          final desktopShell = MediaQuery.sizeOf(context).width >= 1100;
          final bottomPadding = desktopShell ? AppSpacing.xxl : 116.0;
          final pageTitleStyle = constraints.maxWidth >= 900
              ? Theme.of(context).textTheme.headlineLarge
              : Theme.of(context).textTheme.headlineMedium;
          final scaledBodySize = MediaQuery.textScalerOf(context).scale(16);
          final stackHeaderActions =
              constraints.maxWidth < 600 || scaledBodySize >= 24;
          final router = GoRouter.maybeOf(context);
          final hasImperativeHistory =
              router != null && _hasImperativeHistory(router);
          final showBack = hasImperativeHistory ||
              (backFallback != null && showBackForFallback);

          return CustomScrollView(
            slivers: [
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  AppSpacing.lg,
                  horizontalPadding,
                  AppSpacing.sm,
                ),
                sliver: SliverToBoxAdapter(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: maxWidth),
                      child: _AppPageHeader(
                        title: title,
                        subtitle: subtitle,
                        titleStyle: pageTitleStyle,
                        showBack: showBack,
                        backFallback: backFallback,
                        stackActions: stackHeaderActions,
                        actions: actions,
                      ),
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  AppSpacing.md,
                  horizontalPadding,
                  bottomPadding,
                ),
                sliver: SliverList.separated(
                  itemBuilder: (context, index) => Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: maxWidth),
                      child: children[index],
                    ),
                  ),
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: AppSpacing.md),
                  itemCount: children.length,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AppPageHeader extends StatelessWidget {
  const _AppPageHeader({
    required this.title,
    required this.subtitle,
    required this.titleStyle,
    required this.showBack,
    required this.backFallback,
    required this.stackActions,
    required this.actions,
  });

  final String title;
  final String? subtitle;
  final TextStyle? titleStyle;
  final bool showBack;
  final String? backFallback;
  final bool stackActions;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    final titleRow = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showBack) ...[
          IconButton(
            key: const ValueKey('app-page-back'),
            tooltip: 'Back',
            onPressed: () {
              final activeRouter = GoRouter.maybeOf(context);
              if (activeRouter != null && _hasImperativeHistory(activeRouter)) {
                final navigator = Navigator.maybeOf(context);
                if (navigator?.canPop() ?? false) {
                  navigator!.pop();
                } else if (backFallback != null) {
                  activeRouter.go(backFallback!);
                }
              } else if (backFallback != null) {
                activeRouter?.go(backFallback!);
              }
            },
            icon: const Icon(AppIcons.arrowBack),
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: titleStyle),
              if (subtitle != null) ...[
                const SizedBox(height: AppSpacing.xs),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Text(
                    subtitle!,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
    final pageActions = actions;
    if (pageActions == null || pageActions.isEmpty) return titleRow;
    final actionWrap = Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: pageActions,
    );
    if (stackActions) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          titleRow,
          const SizedBox(height: AppSpacing.sm),
          Align(alignment: Alignment.centerRight, child: actionWrap),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: titleRow),
        const SizedBox(width: AppSpacing.sm),
        Flexible(child: actionWrap),
      ],
    );
  }
}

bool _hasImperativeHistory(GoRouter router) {
  bool containsImperative(Iterable<RouteMatchBase> matches) {
    for (final match in matches) {
      if (match is ImperativeRouteMatch) return true;
      if (match is ShellRouteMatch && containsImperative(match.matches)) {
        return true;
      }
    }
    return false;
  }

  return containsImperative(
    router.routerDelegate.currentConfiguration.matches,
  );
}
