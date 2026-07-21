import 'package:flutter/material.dart';

import '../constants/app_spacing.dart';

class AppPage extends StatelessWidget {
  const AppPage({
    required this.title,
    required this.children,
    this.subtitle,
    this.actions,
    this.maxWidth = 1120,
    super.key,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;
  final List<Widget>? actions;
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
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineMedium,
                                ),
                                if (subtitle != null) ...[
                                  const SizedBox(height: AppSpacing.xs),
                                  ConstrainedBox(
                                    constraints:
                                        const BoxConstraints(maxWidth: 720),
                                    child: Text(
                                      subtitle!,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          if (actions != null) ...actions!,
                        ],
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
