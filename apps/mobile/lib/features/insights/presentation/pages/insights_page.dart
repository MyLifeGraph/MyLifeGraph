import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/widgets/async_value_view.dart';
import '../../../dashboard/presentation/providers/dashboard_providers.dart';
import '../../domain/entities/insight.dart';
import '../providers/insights_providers.dart';

class InsightsPage extends ConsumerWidget {
  const InsightsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final insights = ref.watch(insightsProvider);
    final snapshot = ref.watch(dashboardSnapshotProvider);

    return AsyncValueView(
      value: insights,
      data: (items) => AsyncValueView(
        value: snapshot,
        data: (data) => _InsightsHome(
          insights: items,
          sleepHours: data.recoveryScore / 10,
          screenHours: (240 - data.focusMinutesToday).clamp(60, 360) / 60,
          activityScore: data.optimizationScore,
        ),
      ),
    );
  }
}

class _InsightsHome extends StatelessWidget {
  const _InsightsHome({
    required this.insights,
    required this.sleepHours,
    required this.screenHours,
    required this.activityScore,
  });

  final List<Insight> insights;
  final double sleepHours;
  final double screenHours;
  final int activityScore;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 520;
        final pagePadding = isMobile ? AppSpacing.md : AppSpacing.lg;

        return SafeArea(
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  pagePadding,
                  isMobile ? AppSpacing.sm : AppSpacing.lg,
                  pagePadding,
                  AppSpacing.xl,
                ),
                sliver: SliverList.list(
                  children: [
                    _InsightsHeader(isMobile: isMobile),
                    SizedBox(height: isMobile ? AppSpacing.lg : AppSpacing.xl),
                    _MetricCardsRow(
                      sleepHours: sleepHours,
                      screenHours: screenHours,
                      activityScore: activityScore,
                      isMobile: isMobile,
                    ),
                    SizedBox(height: isMobile ? AppSpacing.md : AppSpacing.lg),
                    _SleepTrendCard(
                      sleepHours: sleepHours,
                      isMobile: isMobile,
                    ),
                    SizedBox(height: isMobile ? AppSpacing.md : AppSpacing.lg),
                    _DiscoveredPatternsCard(
                      insights: insights,
                      isMobile: isMobile,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _InsightsHeader extends StatelessWidget {
  const _InsightsHeader({required this.isMobile});

  final bool isMobile;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = isMobile || constraints.maxWidth < 420;
        final titleSize = isMobile ? 38.0 : 46.0;

        final copy = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'PATTERNS AND TRENDS',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontSize: isCompact ? 12 : 14,
                    letterSpacing: isCompact ? 2.5 : 4,
                  ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Insights',
              style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                    fontSize: titleSize,
                    height: 1,
                  ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'This week versus last week, discovered patterns, and recent AI notes.',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: const Color(0xFFA8B5BE),
                    height: 1.7,
                  ),
            ),
          ],
        );

        final actions = Column(
          children: [
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.md,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: () {},
              icon: const Icon(Icons.auto_awesome, size: 18),
              label: const Text('Run AI\nanalysis'),
            ),
          ],
        );

        if (isMobile) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              copy,
              const SizedBox(height: AppSpacing.md),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.md,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: () {},
                  icon: const Icon(Icons.auto_awesome, size: 18),
                  label: const Text('Run AI analysis'),
                ),
              ),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: copy),
            const SizedBox(width: AppSpacing.md),
            actions,
          ],
        );
      },
    );
  }
}

class _MetricCardsRow extends StatelessWidget {
  const _MetricCardsRow({
    required this.sleepHours,
    required this.screenHours,
    required this.activityScore,
    required this.isMobile,
  });

  final double sleepHours;
  final double screenHours;
  final int activityScore;
  final bool isMobile;

  @override
  Widget build(BuildContext context) {
    final metrics = [
      _InsightMetric(
        icon: Icons.nightlight_round,
        title: 'Sleep',
        value: '${sleepHours.toStringAsFixed(1)}h',
        compare: '0% vs last week',
      ),
      _InsightMetric(
        icon: Icons.phone_android,
        title: 'Screen time',
        value: '${screenHours.toStringAsFixed(1)}h',
        compare: '0% vs last week',
      ),
      _InsightMetric(
        icon: Icons.monitor_heart_outlined,
        title: 'Activity',
        value: '$activityScore',
        compare: '0% vs last week',
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (isMobile) {
          return GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: AppSpacing.sm,
            mainAxisSpacing: AppSpacing.sm,
            childAspectRatio: 0.56,
            children:
                metrics.map((metric) => _MetricCard(metric: metric)).toList(),
          );
        }

        if (constraints.maxWidth >= 560) {
          return Row(
            children: metrics
                .map(
                  (metric) => Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                        right: metric == metrics.last ? 0 : AppSpacing.md,
                      ),
                      child: _MetricCard(metric: metric),
                    ),
                  ),
                )
                .toList(),
          );
        }

        final cardWidth = (constraints.maxWidth * 0.42).clamp(148.0, 188.0);
        return SizedBox(
          height: 212,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: metrics.length,
            separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.md),
            itemBuilder: (context, index) => _MetricCard(
              metric: metrics[index],
              width: cardWidth,
            ),
          ),
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.metric, this.width});

  final _InsightMetric metric;
  final double? width;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 124;
        final iconSize = isCompact ? 40.0 : 48.0;

        return _InsightsPanel(
          width: width,
          padding: EdgeInsets.all(isCompact ? AppSpacing.sm : AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: iconSize,
                    height: iconSize,
                    decoration: BoxDecoration(
                      color: const Color(0xFF222B33),
                      borderRadius: BorderRadius.circular(isCompact ? 18 : 22),
                    ),
                    child: Icon(
                      metric.icon,
                      size: isCompact ? 22 : 24,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    Icons.trending_up,
                    size: isCompact ? 20 : 24,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ],
              ),
              SizedBox(height: isCompact ? AppSpacing.md : AppSpacing.lg),
              Text(
                metric.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.sm),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  metric.value,
                  style: isCompact
                      ? Theme.of(context).textTheme.titleLarge
                      : Theme.of(context).textTheme.headlineMedium,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                metric.compare,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontSize: isCompact ? 12 : null,
                    ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SleepTrendCard extends StatelessWidget {
  const _SleepTrendCard({
    required this.sleepHours,
    required this.isMobile,
  });

  final double sleepHours;
  final bool isMobile;

  @override
  Widget build(BuildContext context) {
    return _InsightsPanel(
      padding: EdgeInsets.all(isMobile ? AppSpacing.md : AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Sleep trend',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              Text('7 days', style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          _SleepTrendBar(
            sleepHours: sleepHours,
            isMobile: isMobile,
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Text(
                'Goal 8h',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFFA8B5BE),
                    ),
              ),
              const Spacer(),
              Text(
                'Today ${sleepHours.toStringAsFixed(1)}h',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SleepTrendBar extends StatelessWidget {
  const _SleepTrendBar({
    required this.sleepHours,
    required this.isMobile,
  });

  final double sleepHours;
  final bool isMobile;

  @override
  Widget build(BuildContext context) {
    final progress = (sleepHours / 8).clamp(0.03, 1.0);

    return Container(
      height: isMobile ? 120 : 150,
      padding: EdgeInsets.all(isMobile ? AppSpacing.md : AppSpacing.lg),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2C34),
        borderRadius: BorderRadius.circular(42),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Sleep duration',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFFA8B5BE),
                ),
          ),
          const Spacer(),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 12,
              backgroundColor: const Color(0xFF0D121A),
              valueColor: AlwaysStoppedAnimation<Color>(
                Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DiscoveredPatternsCard extends StatelessWidget {
  const _DiscoveredPatternsCard({
    required this.insights,
    required this.isMobile,
  });

  final List<Insight> insights;
  final bool isMobile;

  @override
  Widget build(BuildContext context) {
    return _InsightsPanel(
      padding: EdgeInsets.all(isMobile ? AppSpacing.md : AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.psychology_outlined,
                color: Theme.of(context).colorScheme.primary,
                size: 34,
              ),
              SizedBox(width: isMobile ? AppSpacing.md : AppSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Discovered patterns',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Stored in long-term memory',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: const Color(0xFFA8B5BE),
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          ...insights.map(
            (insight) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: _PatternTile(insight: insight, isMobile: isMobile),
            ),
          ),
        ],
      ),
    );
  }
}

class _PatternTile extends StatelessWidget {
  const _PatternTile({
    required this.insight,
    required this.isMobile,
  });

  final Insight insight;
  final bool isMobile;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: const Color(0xFF222C33),
        borderRadius: BorderRadius.circular(24),
      ),
      child: isMobile
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        insight.title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    _ImpactBadge(impact: insight.impact),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  insight.summary,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: const Color(0xFFA8B5BE),
                        height: 1.45,
                      ),
                ),
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        insight.title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        insight.summary,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              color: const Color(0xFFA8B5BE),
                              height: 1.45,
                            ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                _ImpactBadge(impact: insight.impact),
              ],
            ),
    );
  }
}

class _ImpactBadge extends StatelessWidget {
  const _ImpactBadge({required this.impact});

  final String impact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF101721),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        impact,
        style: Theme.of(context).textTheme.labelLarge,
      ),
    );
  }
}

class _InsightsPanel extends StatelessWidget {
  const _InsightsPanel({
    required this.child,
    this.padding = EdgeInsets.zero,
    this.width,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double? width;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: padding,
      decoration: BoxDecoration(
        color: const Color(0xFF122329),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: const Color(0xFF2A424A), width: 2),
        boxShadow: [
          BoxShadow(
            color:
                Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
            blurRadius: 28,
            spreadRadius: -18,
            offset: const Offset(0, 20),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _InsightMetric {
  const _InsightMetric({
    required this.icon,
    required this.title,
    required this.value,
    required this.compare,
  });

  final IconData icon;
  final String title;
  final String value;
  final String compare;
}
