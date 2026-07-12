import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/widgets/async_value_view.dart';
import '../../domain/entities/correlation.dart';
import '../../domain/entities/insight.dart';
import '../../domain/services/correlation_analyzer.dart';
import '../../domain/services/coaching_observation.dart';
import '../providers/insights_providers.dart';

class InsightsPage extends ConsumerWidget {
  const InsightsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final insights = ref.watch(insightsProvider);
    final report = ref.watch(correlationReportProvider);

    return AsyncValueView(
      value: insights,
      data: (items) => AsyncValueView(
        value: report,
        data: (correlationReport) => _InsightsHome(
          insights: items,
          report: correlationReport,
        ),
      ),
    );
  }
}

class _InsightsHome extends ConsumerStatefulWidget {
  const _InsightsHome({
    required this.insights,
    required this.report,
  });

  final List<Insight> insights;
  final CorrelationReport report;

  @override
  ConsumerState<_InsightsHome> createState() => _InsightsHomeState();
}

class _InsightsHomeState extends ConsumerState<_InsightsHome> {
  String _metricAId = 'sleep_hours';
  String _metricBId = 'focus_minutes';
  final Set<String> _trendMetricIds = {
    'sleep_hours',
    'focus_minutes',
    'stress_level',
  };

  @override
  void didUpdateWidget(covariant _InsightsHome oldWidget) {
    super.didUpdateWidget(oldWidget);
    _ensureSelectedMetricsExist();
  }

  @override
  Widget build(BuildContext context) {
    _ensureSelectedMetricsExist();
    final windowDays = ref.watch(insightsWindowDaysProvider);
    final isMobile = MediaQuery.sizeOf(context).width < 620;
    final activeResult = widget.report.resultFor(_metricAId, _metricBId);
    final values = const CorrelationAnalyzer().pairValues(
      points: widget.report.points,
      metricAId: _metricAId,
      metricBId: _metricBId,
    );
    final metricA = widget.report.metricById(_metricAId);
    final metricB = widget.report.metricById(_metricBId);
    final observation = const CoachingObservationBuilder().build(widget.report);

    return SafeArea(
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              isMobile ? AppSpacing.md : AppSpacing.lg,
              isMobile ? AppSpacing.sm : AppSpacing.lg,
              isMobile ? AppSpacing.md : AppSpacing.lg,
              AppSpacing.xl,
            ),
            sliver: SliverList.list(
              children: [
                _InsightsHeader(
                  isMobile: isMobile,
                  onRefresh: () {
                    ref.invalidate(correlationReportProvider);
                    ref.invalidate(insightsProvider);
                  },
                ),
                SizedBox(height: isMobile ? AppSpacing.lg : AppSpacing.xl),
                _CoachingObservationCard(observation: observation),
                SizedBox(height: isMobile ? AppSpacing.md : AppSpacing.lg),
                _InsightsPanel(
                  padding: EdgeInsets.zero,
                  child: Material(
                    type: MaterialType.transparency,
                    child: ExpansionTile(
                      title: const Text('Advanced correlation exploration'),
                      subtitle: const Text(
                        'Inspect matrices, trends, and individual signal pairs.',
                      ),
                      childrenPadding: EdgeInsets.all(
                        isMobile ? AppSpacing.md : AppSpacing.lg,
                      ),
                      children: [
                        _ControlsPanel(
                          isMobile: isMobile,
                          windowDays: windowDays,
                          metrics: widget.report.metrics,
                          metricAId: _metricAId,
                          metricBId: _metricBId,
                          onWindowChanged: (value) {
                            ref
                                .read(insightsWindowDaysProvider.notifier)
                                .state = value;
                          },
                          onMetricAChanged: (value) {
                            if (value == null) return;
                            setState(() {
                              _metricAId = value;
                              if (_metricAId == _metricBId) {
                                _metricBId =
                                    _fallbackMetricId(except: _metricAId);
                              }
                            });
                          },
                          onMetricBChanged: (value) {
                            if (value == null) return;
                            setState(() {
                              _metricBId = value;
                              if (_metricAId == _metricBId) {
                                _metricAId =
                                    _fallbackMetricId(except: _metricBId);
                              }
                            });
                          },
                        ),
                        SizedBox(
                          height: isMobile ? AppSpacing.md : AppSpacing.lg,
                        ),
                        _TrendOverlayCard(
                          report: widget.report,
                          selectedMetricIds: _trendMetricIds,
                          onMetricToggled: (metricId) {
                            setState(() {
                              if (_trendMetricIds.contains(metricId)) {
                                if (_trendMetricIds.length > 1) {
                                  _trendMetricIds.remove(metricId);
                                }
                              } else {
                                _trendMetricIds.add(metricId);
                              }
                            });
                          },
                          isMobile: isMobile,
                        ),
                        SizedBox(
                          height: isMobile ? AppSpacing.md : AppSpacing.lg,
                        ),
                        if (isMobile) ...[
                          _CorrelationCard(
                            metricA: metricA,
                            metricB: metricB,
                            result: activeResult,
                            values: values,
                            isMobile: true,
                          ),
                          const SizedBox(height: AppSpacing.md),
                          _TopPatternsCard(
                            report: widget.report,
                            isMobile: true,
                          ),
                        ] else
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 3,
                                child: _CorrelationCard(
                                  metricA: metricA,
                                  metricB: metricB,
                                  result: activeResult,
                                  values: values,
                                  isMobile: false,
                                ),
                              ),
                              const SizedBox(width: AppSpacing.lg),
                              Expanded(
                                flex: 2,
                                child: _TopPatternsCard(
                                  report: widget.report,
                                  isMobile: false,
                                ),
                              ),
                            ],
                          ),
                        SizedBox(
                          height: isMobile ? AppSpacing.md : AppSpacing.lg,
                        ),
                        _CorrelationMatrixCard(
                          report: widget.report,
                          selectedMetricAId: _metricAId,
                          selectedMetricBId: _metricBId,
                          onPairSelected: (metricAId, metricBId) {
                            setState(() {
                              _metricAId = metricAId;
                              _metricBId = metricBId;
                            });
                          },
                        ),
                        SizedBox(
                          height: isMobile ? AppSpacing.md : AppSpacing.lg,
                        ),
                        _DiscoveredPatternsCard(
                          insights: widget.insights,
                          isMobile: isMobile,
                        ),
                      ],
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

  void _ensureSelectedMetricsExist() {
    final metricIds = widget.report.metrics.map((metric) => metric.id).toSet();
    if (!metricIds.contains(_metricAId)) {
      _metricAId = widget.report.metrics.first.id;
    }
    if (!metricIds.contains(_metricBId) || _metricAId == _metricBId) {
      _metricBId = _fallbackMetricId(except: _metricAId);
    }
  }

  String _fallbackMetricId({required String except}) {
    return widget.report.metrics
        .firstWhere(
          (metric) => metric.id != except,
          orElse: () => widget.report.metrics.first,
        )
        .id;
  }
}

class _InsightsHeader extends StatelessWidget {
  const _InsightsHeader({
    required this.isMobile,
    required this.onRefresh,
  });

  final bool isMobile;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final copy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'PATTERNS AND TRENDS',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontSize: isMobile ? 12 : 14,
                letterSpacing: isMobile ? 2.5 : 4,
              ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'Insights',
          style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                fontSize: isMobile ? 38 : 46,
                height: 1,
              ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'Start with one cautious observation. Open advanced exploration when you want the underlying correlations.',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: const Color(0xFFA8B5BE),
                height: 1.7,
              ),
        ),
      ],
    );

    final action = FilledButton.icon(
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
      onPressed: onRefresh,
      icon: const Icon(Icons.refresh, size: 18),
      label: const Text('Refresh correlations'),
    );

    if (isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          copy,
          const SizedBox(height: AppSpacing.md),
          SizedBox(width: double.infinity, child: action),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: copy),
        const SizedBox(width: AppSpacing.md),
        action,
      ],
    );
  }
}

class _CoachingObservationCard extends StatelessWidget {
  const _CoachingObservationCard({required this.observation});

  final CoachingObservation observation;

  @override
  Widget build(BuildContext context) {
    final confidence = switch (observation.confidence) {
      ObservationConfidence.insufficient => 'Insufficient',
      ObservationConfidence.emerging => 'Emerging',
      ObservationConfidence.stronger => 'Stronger',
    };
    return _InsightsPanel(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ONE OBSERVATION',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            observation.title,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(observation.summary),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              Chip(label: Text('$confidence confidence')),
              Chip(label: Text(observation.evidenceWindow)),
              Chip(label: Text(observation.dataQuality)),
            ],
          ),
          if (observation.experiment != null) ...[
            const SizedBox(height: AppSpacing.md),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .primaryContainer
                    .withAlpha(90),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(observation.experiment!),
            ),
          ],
        ],
      ),
    );
  }
}

class _ControlsPanel extends StatelessWidget {
  const _ControlsPanel({
    required this.isMobile,
    required this.windowDays,
    required this.metrics,
    required this.metricAId,
    required this.metricBId,
    required this.onWindowChanged,
    required this.onMetricAChanged,
    required this.onMetricBChanged,
  });

  final bool isMobile;
  final int windowDays;
  final List<CorrelationMetric> metrics;
  final String metricAId;
  final String metricBId;
  final ValueChanged<int> onWindowChanged;
  final ValueChanged<String?> onMetricAChanged;
  final ValueChanged<String?> onMetricBChanged;

  @override
  Widget build(BuildContext context) {
    final pickerA = _MetricPicker(
      label: 'Compare',
      metrics: metrics,
      value: metricAId,
      onChanged: onMetricAChanged,
    );
    final pickerB = _MetricPicker(
      label: 'With',
      metrics: metrics,
      value: metricBId,
      onChanged: onMetricBChanged,
    );
    final windowSelector = _WindowSelector(
      value: windowDays,
      onChanged: onWindowChanged,
    );

    return _InsightsPanel(
      padding: EdgeInsets.all(isMobile ? AppSpacing.md : AppSpacing.lg),
      child: isMobile
          ? Column(
              children: [
                windowSelector,
                const SizedBox(height: AppSpacing.md),
                pickerA,
                const SizedBox(height: AppSpacing.md),
                pickerB,
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(child: pickerA),
                const SizedBox(width: AppSpacing.md),
                Expanded(child: pickerB),
                const SizedBox(width: AppSpacing.md),
                SizedBox(width: 380, child: windowSelector),
              ],
            ),
    );
  }
}

class _WindowSelector extends StatelessWidget {
  const _WindowSelector({
    required this.value,
    required this.onChanged,
  });

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SegmentedButton<int>(
        segments: const [
          ButtonSegment(value: 7, label: Text('7d')),
          ButtonSegment(value: 14, label: Text('14d')),
          ButtonSegment(value: 30, label: Text('30d')),
          ButtonSegment(value: 90, label: Text('3M')),
          ButtonSegment(value: -1, label: Text('All')),
        ],
        selected: {value},
        onSelectionChanged: (selection) => onChanged(selection.first),
      ),
    );
  }
}

class _MetricPicker extends StatelessWidget {
  const _MetricPicker({
    required this.label,
    required this.metrics,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final List<CorrelationMetric> metrics;
  final String value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: metrics
          .map(
            (metric) => DropdownMenuItem(
              value: metric.id,
              child: Text('${metric.label} · ${metric.category}'),
            ),
          )
          .toList(),
      onChanged: onChanged,
    );
  }
}

class _TrendOverlayCard extends StatelessWidget {
  const _TrendOverlayCard({
    required this.report,
    required this.selectedMetricIds,
    required this.onMetricToggled,
    required this.isMobile,
  });

  final CorrelationReport report;
  final Set<String> selectedMetricIds;
  final ValueChanged<String> onMetricToggled;
  final bool isMobile;

  @override
  Widget build(BuildContext context) {
    final selectedMetrics = report.metrics
        .where((metric) => selectedMetricIds.contains(metric.id))
        .toList(growable: false);
    final series = _buildTrendSeries(report.points, selectedMetrics);

    return _InsightsPanel(
      padding: EdgeInsets.all(isMobile ? AppSpacing.md : AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Trend overlay',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Select multiple signals to compare their peaks over time.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: const Color(0xFFA8B5BE),
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              _SmallInfoBadge(label: '0-100 normalized'),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final metric in report.metrics)
                FilterChip(
                  label: Text(metric.label),
                  selected: selectedMetricIds.contains(metric.id),
                  onSelected: (_) => onMetricToggled(metric.id),
                  selectedColor:
                      _trendColorForMetric(metric.id).withValues(alpha: 0.22),
                  checkmarkColor: _trendColorForMetric(metric.id),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            height: isMobile ? 260 : 340,
            child: CustomPaint(
              painter: _TrendOverlayPainter(
                series: series,
                axisColor: Colors.white.withValues(alpha: 0.28),
                gridColor: Colors.white.withValues(alpha: 0.08),
              ),
              child: const SizedBox.expand(),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.xs,
            children: [
              for (final item in series)
                _LegendDot(color: item.color, label: item.metric.label),
            ],
          ),
        ],
      ),
    );
  }

  List<_TrendSeries> _buildTrendSeries(
    List<CorrelationDataPoint> points,
    List<CorrelationMetric> metrics,
  ) {
    return metrics.map((metric) {
      final rawValues = points
          .map((point) {
            final value = point.values[metric.id];
            if (value == null || !value.isFinite) {
              return null;
            }
            return _TrendPoint(date: point.date, rawValue: value);
          })
          .nonNulls
          .toList(growable: false);

      if (rawValues.isEmpty) {
        return _TrendSeries(
          metric: metric,
          color: _trendColorForMetric(metric.id),
          points: const [],
        );
      }

      final minValue =
          rawValues.map((point) => point.rawValue).reduce(math.min);
      final maxValue =
          rawValues.map((point) => point.rawValue).reduce(math.max);
      final range = math.max(maxValue - minValue, 1);

      return _TrendSeries(
        metric: metric,
        color: _trendColorForMetric(metric.id),
        points: rawValues
            .map(
              (point) => point.copyWith(
                normalizedValue: (point.rawValue - minValue) / range * 100,
              ),
            )
            .toList(growable: false),
      );
    }).toList(growable: false);
  }
}

class _SmallInfoBadge extends StatelessWidget {
  const _SmallInfoBadge({required this.label});

  final String label;

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
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelSmall),
    );
  }
}

class _CorrelationCard extends StatelessWidget {
  const _CorrelationCard({
    required this.metricA,
    required this.metricB,
    required this.result,
    required this.values,
    required this.isMobile,
  });

  final CorrelationMetric metricA;
  final CorrelationMetric metricB;
  final CorrelationResult? result;
  final List<MetricPairValues> values;
  final bool isMobile;

  @override
  Widget build(BuildContext context) {
    final activeResult = result;
    return _InsightsPanel(
      padding: EdgeInsets.all(isMobile ? AppSpacing.md : AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${metricA.label} vs ${metricB.label}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      activeResult?.summary ??
                          'Choose two different signals to compare.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: const Color(0xFFA8B5BE),
                            height: 1.4,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              _CorrelationBadge(
                result: activeResult,
                metricA: metricA,
                metricB: metricB,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            height: isMobile ? 230 : 320,
            child: CustomPaint(
              painter: _ScatterPlotPainter(
                values: values,
                metricA: metricA,
                metricB: metricB,
                color: Theme.of(context).colorScheme.primary,
                trendColor: _resultColor(activeResult, metricA, metricB),
              ),
              child: const SizedBox.expand(),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _PointLegend(
            olderColor: _olderPointColor,
            newerColor: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${metricA.label} (${metricA.unit})',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              Text(
                '${activeResult?.sampleSize ?? values.length} shared days',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFFA8B5BE),
                    ),
              ),
              Expanded(
                child: Text(
                  '${metricB.label} (${metricB.unit})',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CorrelationBadge extends StatelessWidget {
  const _CorrelationBadge({
    required this.result,
    required this.metricA,
    required this.metricB,
  });

  final CorrelationResult? result;
  final CorrelationMetric metricA;
  final CorrelationMetric metricB;

  @override
  Widget build(BuildContext context) {
    final label = result?.coefficientLabel ?? '--';
    final caption = result?.strengthLabel ?? 'No pair';
    final color = _resultColor(result, metricA, metricB);
    return Container(
      width: 112,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            caption,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
    );
  }
}

class _PointLegend extends StatelessWidget {
  const _PointLegend({
    required this.olderColor,
    required this.newerColor,
  });

  final Color olderColor;
  final Color newerColor;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _LegendDot(color: olderColor, label: 'Older days'),
        _LegendDot(color: newerColor, label: 'Newer days'),
        Text(
          'Each dot is one day',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: const Color(0xFFA8B5BE),
              ),
        ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({
    required this.color,
    required this.label,
  });

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 11,
          height: 11,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _TopPatternsCard extends StatelessWidget {
  const _TopPatternsCard({
    required this.report,
    required this.isMobile,
  });

  final CorrelationReport report;
  final bool isMobile;

  @override
  Widget build(BuildContext context) {
    final topResults = report.rankedResults.take(5).toList(growable: false);

    return _InsightsPanel(
      padding: EdgeInsets.all(isMobile ? AppSpacing.md : AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Top patterns', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Strongest relationships in the selected window.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFFA8B5BE),
                ),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (topResults.isEmpty)
            Text(
              'No meaningful pattern found in this window yet.',
              style: Theme.of(context).textTheme.bodyMedium,
            )
          else
            ...topResults.map(
              (result) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: _TopPatternTile(report: report, result: result),
              ),
            ),
        ],
      ),
    );
  }
}

class _TopPatternTile extends StatelessWidget {
  const _TopPatternTile({
    required this.report,
    required this.result,
  });

  final CorrelationReport report;
  final CorrelationResult result;

  @override
  Widget build(BuildContext context) {
    final metricA = report.metricById(result.metricAId);
    final metricB = report.metricById(result.metricBId);
    final color = _resultColor(result, metricA, metricB);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: const Color(0xFF222C33),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              result.coefficient! >= 0
                  ? Icons.trending_up
                  : Icons.trending_down,
              color: color,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${metricA.label} × ${metricB.label}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  result.strengthLabel,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFFA8B5BE),
                      ),
                ),
              ],
            ),
          ),
          Text(
            result.coefficientLabel,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: color,
                ),
          ),
        ],
      ),
    );
  }
}

class _CorrelationMatrixCard extends StatelessWidget {
  const _CorrelationMatrixCard({
    required this.report,
    required this.selectedMetricAId,
    required this.selectedMetricBId,
    required this.onPairSelected,
  });

  final CorrelationReport report;
  final String selectedMetricAId;
  final String selectedMetricBId;
  final void Function(String metricAId, String metricBId) onPairSelected;

  @override
  Widget build(BuildContext context) {
    return _InsightsPanel(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Correlation matrix',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Tap any cell to inspect that pair.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFFA8B5BE),
                ),
          ),
          const SizedBox(height: AppSpacing.lg),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const SizedBox(width: 116),
                    ...report.metrics.map(
                      (metric) => _MatrixHeaderCell(label: metric.label),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                ...report.metrics.map(
                  (rowMetric) => Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                    child: Row(
                      children: [
                        _MatrixRowLabel(label: rowMetric.label),
                        ...report.metrics.map(
                          (columnMetric) {
                            final result = report.resultFor(
                              rowMetric.id,
                              columnMetric.id,
                            );
                            final color = _resultColor(
                              result,
                              rowMetric,
                              columnMetric,
                            );
                            final selected = _isSelectedPair(
                              rowMetric.id,
                              columnMetric.id,
                            );
                            return _MatrixCell(
                              result: result,
                              color: color,
                              selected: selected,
                              disabled: rowMetric.id == columnMetric.id,
                              onTap: rowMetric.id == columnMetric.id
                                  ? null
                                  : () => onPairSelected(
                                        rowMetric.id,
                                        columnMetric.id,
                                      ),
                            );
                          },
                        ),
                      ],
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

  bool _isSelectedPair(String metricAId, String metricBId) {
    return (metricAId == selectedMetricAId && metricBId == selectedMetricBId) ||
        (metricAId == selectedMetricBId && metricBId == selectedMetricAId);
  }
}

class _MatrixHeaderCell extends StatelessWidget {
  const _MatrixHeaderCell({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72,
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.labelSmall,
      ),
    );
  }
}

class _MatrixRowLabel extends StatelessWidget {
  const _MatrixRowLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 116,
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelMedium,
      ),
    );
  }
}

class _MatrixCell extends StatelessWidget {
  const _MatrixCell({
    required this.result,
    required this.color,
    required this.selected,
    required this.disabled,
    required this.onTap,
  });

  final CorrelationResult? result;
  final Color color;
  final bool selected;
  final bool disabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final fillColor = disabled
        ? const Color(0xFF182126)
        : color.withValues(
            alpha: (result?.coefficient?.abs() ?? 0.08).clamp(0.12, 0.9),
          );
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.xs),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 64,
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: fillColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? Theme.of(context).colorScheme.primary
                  : Colors.white.withValues(alpha: 0.08),
              width: selected ? 2 : 1,
            ),
          ),
          child: Text(
            disabled ? '·' : result?.coefficientLabel ?? '--',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: disabled ? const Color(0xFF6E7D84) : Colors.white,
                ),
          ),
        ),
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
                      'Stored insights and previous AI notes',
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
          if (insights.isEmpty)
            Text(
              'No stored patterns yet.',
              style: Theme.of(context).textTheme.bodyMedium,
            )
          else
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
        borderRadius: BorderRadius.circular(18),
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

class _ScatterPlotPainter extends CustomPainter {
  const _ScatterPlotPainter({
    required this.values,
    required this.metricA,
    required this.metricB,
    required this.color,
    required this.trendColor,
  });

  final List<MetricPairValues> values;
  final CorrelationMetric metricA;
  final CorrelationMetric metricB;
  final Color color;
  final Color trendColor;

  @override
  void paint(Canvas canvas, Size size) {
    const yTitleWidth = 24.0;
    const yTickWidth = 44.0;
    const yAxisGap = 8.0;
    const leftInset = yTitleWidth + yTickWidth + yAxisGap;
    const rightInset = 14.0;
    const topInset = 14.0;
    const bottomInset = 42.0;
    final plotLeft = leftInset;
    final plotRight = size.width - rightInset;
    final plotTop = topInset;
    final plotBottom = size.height - bottomInset;
    final plotWidth = math.max(plotRight - plotLeft, 1).toDouble();
    final plotHeight = math.max(plotBottom - plotTop, 1).toDouble();

    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..strokeWidth = 1;
    final axisPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.28)
      ..strokeWidth = 1.2;

    canvas.drawLine(
      Offset(plotLeft, plotTop),
      Offset(plotLeft, plotBottom),
      axisPaint,
    );
    canvas.drawLine(
      Offset(plotLeft, plotBottom),
      Offset(plotRight, plotBottom),
      axisPaint,
    );

    final labelStyle = TextStyle(
      color: Colors.white.withValues(alpha: 0.62),
      fontSize: 10,
    );
    final titleStyle = TextStyle(
      color: Colors.white.withValues(alpha: 0.78),
      fontSize: 11,
      fontWeight: FontWeight.w600,
    );

    for (var index = 0; index <= 4; index++) {
      final progress = index / 4;
      final y = plotBottom - progress * plotHeight;
      final x = plotLeft + progress * plotWidth;
      canvas.drawLine(Offset(plotLeft, y), Offset(plotRight, y), gridPaint);
      canvas.drawLine(Offset(x, plotTop), Offset(x, plotBottom), gridPaint);
    }

    if (values.length < 2) {
      _drawAxisTitles(
        canvas,
        size,
        metricA: metricA,
        metricB: metricB,
        titleStyle: titleStyle,
      );
      return;
    }

    final sortedValues = values.toList(growable: false)
      ..sort((a, b) => a.date.compareTo(b.date));
    final minX = values.map((value) => value.metricAValue).reduce(math.min);
    final maxX = values.map((value) => value.metricAValue).reduce(math.max);
    final minY = values.map((value) => value.metricBValue).reduce(math.min);
    final maxY = values.map((value) => value.metricBValue).reduce(math.max);
    final rangeX = math.max(maxX - minX, 1);
    final rangeY = math.max(maxY - minY, 1);

    for (var index = 0; index <= 4; index++) {
      final progress = index / 4;
      final tickX = minX + progress * rangeX;
      final tickY = minY + progress * rangeY;
      final x = plotLeft + progress * plotWidth;
      final y = plotBottom - progress * plotHeight;
      _drawText(
        canvas,
        _formatTick(tickX),
        Offset(x - 22, plotBottom + 8),
        labelStyle,
        maxWidth: 44,
        textAlign: TextAlign.center,
      );
      _drawText(
        canvas,
        _formatTick(tickY),
        Offset(yTitleWidth, y - 7),
        labelStyle,
        maxWidth: yTickWidth,
        textAlign: TextAlign.right,
      );
    }

    _drawAxisTitles(
      canvas,
      size,
      metricA: metricA,
      metricB: metricB,
      titleStyle: titleStyle,
    );

    Offset pointFor(MetricPairValues value) {
      final x = plotLeft + (value.metricAValue - minX) / rangeX * plotWidth;
      final y = plotBottom - (value.metricBValue - minY) / rangeY * plotHeight;
      return Offset(x, y);
    }

    final outlinePaint = Paint()
      ..color = const Color(0xFF071015).withValues(alpha: 0.75)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    for (var index = 0; index < sortedValues.length; index++) {
      final value = sortedValues[index];
      final recency =
          sortedValues.length == 1 ? 1.0 : index / (sortedValues.length - 1);
      final pointPaint = Paint()
        ..color = _pointColorForRecency(recency, color)
        ..style = PaintingStyle.fill;
      final point = pointFor(value);
      final radius = index == sortedValues.length - 1 ? 6.2 : 4.6;
      canvas.drawCircle(point, radius, pointPaint);
      canvas.drawCircle(point, radius, outlinePaint);
    }

    final trend = _trendLine(values);
    if (trend == null) {
      return;
    }
    final start = pointFor(
      MetricPairValues(
        date: values.first.date,
        metricAValue: minX,
        metricBValue: trend.slope * minX + trend.intercept,
      ),
    );
    final end = pointFor(
      MetricPairValues(
        date: values.last.date,
        metricAValue: maxX,
        metricBValue: trend.slope * maxX + trend.intercept,
      ),
    );
    final trendPaint = Paint()
      ..color = trendColor
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(start, end, trendPaint);
  }

  _TrendLine? _trendLine(List<MetricPairValues> values) {
    final meanX = values
            .map((value) => value.metricAValue)
            .reduce((value, element) => value + element) /
        values.length;
    final meanY = values
            .map((value) => value.metricBValue)
            .reduce((value, element) => value + element) /
        values.length;

    var numerator = 0.0;
    var denominator = 0.0;
    for (final value in values) {
      final diffX = value.metricAValue - meanX;
      numerator += diffX * (value.metricBValue - meanY);
      denominator += diffX * diffX;
    }
    if (denominator == 0) {
      return null;
    }
    final slope = numerator / denominator;
    return _TrendLine(slope: slope, intercept: meanY - slope * meanX);
  }

  @override
  bool shouldRepaint(covariant _ScatterPlotPainter oldDelegate) {
    return values != oldDelegate.values ||
        metricA != oldDelegate.metricA ||
        metricB != oldDelegate.metricB ||
        color != oldDelegate.color ||
        trendColor != oldDelegate.trendColor;
  }

  void _drawAxisTitles(
    Canvas canvas,
    Size size, {
    required CorrelationMetric metricA,
    required CorrelationMetric metricB,
    required TextStyle titleStyle,
  }) {
    _drawText(
      canvas,
      '${metricA.label} (${metricA.unit})',
      Offset(size.width / 2 - 80, size.height - 15),
      titleStyle,
      maxWidth: 160,
      textAlign: TextAlign.center,
    );
    canvas.save();
    canvas.translate(2, size.height / 2 + 80);
    canvas.rotate(-math.pi / 2);
    _drawText(
      canvas,
      '${metricB.label} (${metricB.unit})',
      Offset.zero,
      titleStyle,
      maxWidth: 160,
      textAlign: TextAlign.center,
    );
    canvas.restore();
  }

  void _drawText(
    Canvas canvas,
    String text,
    Offset offset,
    TextStyle style, {
    required double maxWidth,
    TextAlign textAlign = TextAlign.left,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textAlign: textAlign,
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '...',
    )..layout(maxWidth: maxWidth);
    painter.paint(canvas, offset);
  }

  String _formatTick(double value) {
    final absValue = value.abs();
    if (absValue >= 10000) {
      return '${(value / 1000).toStringAsFixed(0)}k';
    }
    if (absValue >= 1000) {
      return '${(value / 1000).toStringAsFixed(1)}k';
    }
    if (absValue >= 100) {
      return value.toStringAsFixed(0);
    }
    if (absValue >= 10) {
      return value.toStringAsFixed(1);
    }
    return value.toStringAsFixed(1);
  }
}

class _TrendOverlayPainter extends CustomPainter {
  const _TrendOverlayPainter({
    required this.series,
    required this.axisColor,
    required this.gridColor,
  });

  final List<_TrendSeries> series;
  final Color axisColor;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    const leftInset = 44.0;
    const rightInset = 14.0;
    const topInset = 18.0;
    const bottomInset = 42.0;
    final plotLeft = leftInset;
    final plotRight = size.width - rightInset;
    final plotTop = topInset;
    final plotBottom = size.height - bottomInset;
    final plotWidth = math.max(plotRight - plotLeft, 1).toDouble();
    final plotHeight = math.max(plotBottom - plotTop, 1).toDouble();

    final axisPaint = Paint()
      ..color = axisColor
      ..strokeWidth = 1.2;
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;

    canvas.drawLine(
      Offset(plotLeft, plotTop),
      Offset(plotLeft, plotBottom),
      axisPaint,
    );
    canvas.drawLine(
      Offset(plotLeft, plotBottom),
      Offset(plotRight, plotBottom),
      axisPaint,
    );

    final labelStyle = TextStyle(
      color: Colors.white.withValues(alpha: 0.62),
      fontSize: 10,
    );
    for (var index = 0; index <= 4; index++) {
      final progress = index / 4;
      final y = plotBottom - progress * plotHeight;
      final x = plotLeft + progress * plotWidth;
      canvas.drawLine(Offset(plotLeft, y), Offset(plotRight, y), gridPaint);
      canvas.drawLine(Offset(x, plotTop), Offset(x, plotBottom), gridPaint);
      _drawText(
        canvas,
        '${(progress * 100).round()}',
        Offset(4, y - 7),
        labelStyle,
        maxWidth: 34,
        textAlign: TextAlign.right,
      );
    }

    final allDates = series
        .expand((item) => item.points.map((point) => point.date))
        .toList(growable: false);
    if (allDates.isEmpty) {
      _drawText(
        canvas,
        'Select signals with data to compare trends.',
        Offset(plotLeft, plotTop + 24),
        labelStyle,
        maxWidth: plotWidth,
      );
      return;
    }

    allDates.sort();
    final firstDate = allDates.first;
    final lastDate = allDates.last;
    final totalDays = math.max(lastDate.difference(firstDate).inDays, 1);

    Offset pointFor(_TrendPoint point) {
      final x = plotLeft +
          point.date.difference(firstDate).inDays / totalDays * plotWidth;
      final y = plotBottom - point.normalizedValue / 100 * plotHeight;
      return Offset(x, y);
    }

    for (final item in series) {
      if (item.points.length < 2) {
        continue;
      }
      final path = Path();
      for (var index = 0; index < item.points.length; index++) {
        final offset = pointFor(item.points[index]);
        if (index == 0) {
          path.moveTo(offset.dx, offset.dy);
        } else {
          path.lineTo(offset.dx, offset.dy);
        }
      }

      final linePaint = Paint()
        ..color = item.color
        ..strokeWidth = 2.8
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      canvas.drawPath(path, linePaint);

      final pointPaint = Paint()
        ..color = item.color
        ..style = PaintingStyle.fill;
      for (final point in item.points) {
        canvas.drawCircle(pointFor(point), 2.7, pointPaint);
      }

      final peak = item.peak;
      if (peak != null) {
        final peakPoint = pointFor(peak);
        final peakPaint = Paint()
          ..color = item.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2;
        canvas.drawCircle(peakPoint, 6.5, peakPaint);
      }
    }

    final dateStyle = labelStyle.copyWith(fontWeight: FontWeight.w600);
    _drawText(
      canvas,
      _shortDate(firstDate),
      Offset(plotLeft, plotBottom + 10),
      dateStyle,
      maxWidth: 72,
    );
    _drawText(
      canvas,
      _shortDate(lastDate),
      Offset(plotRight - 72, plotBottom + 10),
      dateStyle,
      maxWidth: 72,
      textAlign: TextAlign.right,
    );
    _drawText(
      canvas,
      'normalized intensity',
      Offset(0, 0),
      labelStyle,
      maxWidth: 140,
    );
  }

  void _drawText(
    Canvas canvas,
    String text,
    Offset offset,
    TextStyle style, {
    required double maxWidth,
    TextAlign textAlign = TextAlign.left,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textAlign: textAlign,
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '...',
    )..layout(maxWidth: maxWidth);
    painter.paint(canvas, offset);
  }

  String _shortDate(DateTime date) {
    return '${date.month}/${date.day}';
  }

  @override
  bool shouldRepaint(covariant _TrendOverlayPainter oldDelegate) {
    return series != oldDelegate.series ||
        axisColor != oldDelegate.axisColor ||
        gridColor != oldDelegate.gridColor;
  }
}

class _TrendSeries {
  const _TrendSeries({
    required this.metric,
    required this.color,
    required this.points,
  });

  final CorrelationMetric metric;
  final Color color;
  final List<_TrendPoint> points;

  _TrendPoint? get peak {
    if (points.isEmpty) {
      return null;
    }
    return points.reduce(
      (value, element) =>
          value.normalizedValue >= element.normalizedValue ? value : element,
    );
  }
}

class _TrendPoint {
  const _TrendPoint({
    required this.date,
    required this.rawValue,
    this.normalizedValue = 0,
  });

  final DateTime date;
  final double rawValue;
  final double normalizedValue;

  _TrendPoint copyWith({double? normalizedValue}) {
    return _TrendPoint(
      date: date,
      rawValue: rawValue,
      normalizedValue: normalizedValue ?? this.normalizedValue,
    );
  }
}

class _TrendLine {
  const _TrendLine({
    required this.slope,
    required this.intercept,
  });

  final double slope;
  final double intercept;
}

class _InsightsPanel extends StatelessWidget {
  const _InsightsPanel({
    required this.child,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: const Color(0xFF122329),
        borderRadius: BorderRadius.circular(24),
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

Color _resultColor(
  CorrelationResult? result,
  CorrelationMetric metricA,
  CorrelationMetric metricB,
) {
  final coefficient = result?.coefficient;
  if (coefficient == null) {
    return const Color(0xFF7D8B91);
  }
  if (coefficient.abs() < 0.2) {
    return const Color(0xFFFFC857);
  }

  final bothPositive = metricA.higherIsPositive && metricB.higherIsPositive;
  final bothRisk = !metricA.higherIsPositive && !metricB.higherIsPositive;
  final mixedValence = metricA.higherIsPositive != metricB.higherIsPositive;
  final supportive = (bothPositive && coefficient > 0) ||
      (mixedValence && coefficient < 0) ||
      (bothRisk && coefficient < 0);

  if (supportive) {
    return const Color(0xFF66D19E);
  }
  return const Color(0xFFFF8F70);
}

const _olderPointColor = Color(0xFF6E7D84);

Color _pointColorForRecency(double recency, Color newestColor) {
  final middle = Color.lerp(_olderPointColor, const Color(0xFF8EA7FF), recency);
  return Color.lerp(middle, newestColor, recency * 0.7) ?? newestColor;
}

Color _trendColorForMetric(String metricId) {
  return switch (metricId) {
    'sleep_hours' => const Color(0xFF8EA7FF),
    'focus_minutes' => const Color(0xFF66D19E),
    'workload_score' => const Color(0xFFFFC857),
    'stress_level' => const Color(0xFFFF8F70),
    'energy_level' => const Color(0xFF2ED3C6),
    'mood_score' => const Color(0xFFE38CFF),
    'screen_time_hours' => const Color(0xFFB7A6FF),
    'activity_level' => const Color(0xFF8FE388),
    'steps' => const Color(0xFF4FB3FF),
    'habit_completion_rate' => const Color(0xFFFFB86B),
    'recovery_score' => const Color(0xFFB7F07A),
    _ => const Color(0xFFEFF4F6),
  };
}
