import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../constants/app_spacing.dart';
import '../constants/app_radii.dart';
import '../theme/app_icons.dart';

class AppPage extends StatelessWidget {
  const AppPage({
    required this.title,
    required this.children,
    this.subtitle,
    this.actions,
    this.compactHeader = false,
    this.bottomPanel,
    this.viewportBody,
    this.outlineBody = false,
    this.outlineStartKey,
    this.backFallback,
    this.showBackForFallback = true,
    this.maxWidth = 1120,
    super.key,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;
  final List<Widget>? actions;
  final bool compactHeader;
  final Widget? bottomPanel;
  /// Opt-in bounded content below a fixed header; ordinary pages still scroll.
  final Widget? viewportBody;
  final bool outlineBody;
  final GlobalKey? outlineStartKey;
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

          final header = Padding(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  compactHeader ? AppSpacing.md : AppSpacing.lg,
                  horizontalPadding,
                  compactHeader ? 0 : AppSpacing.sm,
                ),
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
                        compact: compactHeader,
                      ),
                    ),
                  ),
              );
          if (viewportBody != null) {
            return Column(children: [
              header,
              Expanded(child: Padding(
                padding: EdgeInsets.fromLTRB(horizontalPadding, AppSpacing.md,
                    horizontalPadding, desktopShell ? AppSpacing.md : AppSpacing.xl),
                child: Center(child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: viewportBody,
                )),
              )),
            ]);
          }
          final scrollView = CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: header),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  AppSpacing.md,
                  horizontalPadding,
                  bottomPanel == null ? bottomPadding : AppSpacing.md,
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
          if (bottomPanel == null) return scrollView;
          final body = Column(
            children: [
              Expanded(child: scrollView),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: constraints.maxHeight * 0.45,
                ),
                child: SingleChildScrollView(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      horizontalPadding, AppSpacing.sm, horizontalPadding,
                      desktopShell ? AppSpacing.md : AppSpacing.xl,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: maxWidth),
                        child: bottomPanel,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
          if (!outlineBody) return body;
          return _AnchoredOutline(
            anchor: outlineStartKey,
            body: body,
            outlineBuilder: (top) => Positioned.fill(
                top: top,
                bottom: desktopShell ? AppSpacing.sm : AppSpacing.lg,
                child: IgnorePointer(
                  child: Center(
                    child: Container(
                      key: const Key('app-page-body-outline'),
                      width: maxWidth + AppSpacing.md,
                      margin: EdgeInsets.symmetric(
                        horizontal: horizontalPadding - AppSpacing.sm,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                        borderRadius: BorderRadius.circular(AppRadii.md),
                      ),
                    ),
                  ),
                ),
              ),
          );
        },
      ),
    );
  }
}

class _AnchoredOutline extends StatefulWidget {
  const _AnchoredOutline({
    required this.anchor,
    required this.body,
    required this.outlineBuilder,
  });

  final GlobalKey? anchor;
  final Widget body;
  final Widget Function(double top) outlineBuilder;

  @override
  State<_AnchoredOutline> createState() => _AnchoredOutlineState();
}

class _AnchoredOutlineState extends State<_AnchoredOutline> {
  final _bodyKey = GlobalKey();
  double? _top;
  bool _measurementScheduled = false;

  void _measureAfterLayout() {
    if (_measurementScheduled) return;
    _measurementScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measurementScheduled = false;
      if (!mounted) return;
      final body = _bodyKey.currentContext?.findRenderObject() as RenderBox?;
      final anchor = widget.anchor?.currentContext?.findRenderObject() as RenderBox?;
      if (body == null || !body.hasSize) return;
      final top = anchor == null || !anchor.hasSize
          ? AppSpacing.xs
          : (anchor.localToGlobal(Offset.zero, ancestor: body).dy - AppSpacing.sm)
              .clamp(0.0, body.size.height);
      if (_top != top) setState(() => _top = top);
    });
  }

  @override
  Widget build(BuildContext context) {
    _measureAfterLayout();
    return NotificationListener<Notification>(
      onNotification: (notification) {
        if (notification is ScrollNotification ||
            notification is SizeChangedLayoutNotification) {
          _measureAfterLayout();
        }
        return false;
      },
      child: Stack(
        key: _bodyKey,
        children: [
          widget.body,
          if (_top != null) widget.outlineBuilder(_top!),
        ],
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
    required this.compact,
  });

  final String title;
  final String? subtitle;
  final TextStyle? titleStyle;
  final bool showBack;
  final String? backFallback;
  final bool stackActions;
  final bool compact;
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
              if (subtitle != null && !compact) ...[
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
    if (compact) {
      return AppPageHeading(
        title: titleRow,
        actions: actionWrap,
        subtitle: subtitle == null ? null : Text(subtitle!),
      );
    }
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

/// Compact main-page heading; enlarged text keeps actions above the title.
class AppPageHeading extends StatelessWidget {
  const AppPageHeading({
    required this.title,
    required this.actions,
    this.subtitle,
    super.key,
  });

  final Widget title;
  final Widget actions;
  final Widget? subtitle;

  @override
  Widget build(BuildContext context) {
    final largeText = MediaQuery.textScalerOf(context).scale(16) >= 24;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (largeText) ...[
          Align(alignment: Alignment.topRight, child: actions),
          const SizedBox(height: AppSpacing.xs),
          title,
        ] else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: title),
              const SizedBox(width: AppSpacing.xs),
              actions,
            ],
          ),
        if (subtitle != null) ...[
          const SizedBox(height: AppSpacing.xs),
          subtitle!,
        ],
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
