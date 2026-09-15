import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/widgets/app_surface.dart';
import '../../domain/entities/period_comparison.dart';
import '../providers/insights_providers.dart';

final _mode = StateProvider((ref) => PeriodComparisonMode.rolling);
final _days = StateProvider((ref) => 7);
final _metric = StateProvider((ref) => 'sleep_hours');

/// Presentation only. Existing ninety-day evidence supplies both periods.
class PeriodComparisonCard extends ConsumerWidget {
  const PeriodComparisonCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(periodComparisonDataProvider);
    return AppSurface(
      variant: AppSurfaceVariant.subtle,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: data.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Column(
          children: [
            const Text('Comparison unavailable.'),
            TextButton.icon(
              onPressed: () {
                ref.invalidate(personalPatternsProvider);
                ref.invalidate(periodComparisonDataProvider);
              },
              icon: const Icon(AppIcons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
        data: (data) => data.enabled
            ? _content(context, ref, data)
            : const Text(
                'Enable personal pattern analysis in Settings to compare periods.',
              ),
      ),
    );
  }

  Widget _content(
    BuildContext context,
    WidgetRef ref,
    PeriodComparisonData data,
  ) {
    final theme = Theme.of(context);
    final mode = ref.watch(_mode);
    final days = ref.watch(_days);
    final metric = periodMetrics.firstWhere((m) => m.id == ref.watch(_metric));
    final comparison = PeriodComparison.build(
      points: data.points,
      today: data.today,
      metric: metric,
      mode: mode,
      days: days,
    );
    final currentColor = theme.colorScheme.primary;
    final previousColor = theme.colorScheme.primary.withValues(alpha: 0.45);
    final count = comparison.current.length;
    String period(DateTime start, {DateTime? end}) =>
        '${DateFormat.MMMd('en_US').format(start)} – '
        '${DateFormat.MMMd('en_US').format(end ?? start.add(Duration(days: count - 1)))}';
    final currentLabel = mode == PeriodComparisonMode.weekdays
        ? 'This week'
        : 'Latest $days days';
    final previousLabel = mode == PeriodComparisonMode.weekdays
        ? 'Last week'
        : 'Previous $days days';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Past comparison', style: theme.textTheme.titleLarge),
        const SizedBox(height: AppSpacing.md),
        SegmentedButton<PeriodComparisonMode>(
          showSelectedIcon: false,
          style: SegmentedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          ),
          segments: [
            ButtonSegment(
              value: PeriodComparisonMode.rolling,
              label: const Text('Rolling'),
              icon: MediaQuery.textScalerOf(context).scale(14) <= 20
                  ? const Icon(AppIcons.viewTimelineOutlined)
                  : null,
              tooltip: 'Latest days vs the preceding period',
            ),
            ButtonSegment(
              value: PeriodComparisonMode.weekdays,
              label: const Text('Weekdays'),
              icon: MediaQuery.textScalerOf(context).scale(14) <= 20
                  ? const Icon(AppIcons.calendarMonthOutlined)
                  : null,
              tooltip: 'Monday–today vs last Monday–Sunday',
            ),
          ],
          selected: {mode},
          onSelectionChanged: (value) =>
              ref.read(_mode.notifier).state = value.single,
        ),
        if (mode == PeriodComparisonMode.rolling) ...[
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.xs,
            children: [
              for (final value in [7, 14, 30])
                ChoiceChip(
                  label: Text('$value days'),
                  selected: days == value,
                  showCheckmark: false,
                  onSelected: (_) => ref.read(_days.notifier).state = value,
                ),
            ],
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        DropdownButtonFormField<String>(
          initialValue: metric.id,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Signal', isDense: true),
          items: [
            for (final value in periodMetrics)
              DropdownMenuItem(value: value.id, child: Text(value.label)),
          ],
          onChanged: (value) {
            if (value != null) ref.read(_metric.notifier).state = value;
          },
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          '${metric.unit} · ${metric.rollingSummary ? 'Trailing 7-day summary' : 'Daily values'}'
          '${data.isDemo ? ' · Example data' : ''}',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: AppSpacing.md),
        if (comparison.hasValues)
          _PeriodPlot(
            comparison: comparison,
            metric: metric,
            mode: mode,
            currentColor: currentColor,
            previousColor: previousColor,
          )
        else
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
            child: Text(
              'No recorded values in these periods.',
              textAlign: TextAlign.center,
            ),
          ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.xs,
          children: [
            _legend(
              context,
              currentColor,
              '$currentLabel · ${period(comparison.currentStart, end: comparisonDay(data.today))}',
              false,
            ),
            _legend(
              context,
              previousColor,
              '$previousLabel · ${period(comparison.previousStart)}',
              true,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Gaps = no data · ${data.timezone}',
          style: theme.textTheme.bodySmall,
        ),
        if (metric.rollingSummary)
          Text(
            metric.id == 'regularity'
                ? 'Focus completion + sport regularity; each needs 3 observations.'
                : 'Study Focus completion; needs 3 sessions.',
            style: theme.textTheme.bodySmall,
          ),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('Details'),
          children: [
            for (var i = 0; i < count; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        '${DateFormat.MMMd('en_US').format(comparison.currentStart.add(Duration(days: i)))}'
                        ' · ${_value(comparison.current[i], metric)}',
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        '${DateFormat.MMMd('en_US').format(comparison.previousStart.add(Duration(days: i)))}'
                        ' · ${_value(comparison.previous[i], metric)}',
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }

  String _value(double? value, PeriodMetric metric) => value == null
      ? '—'
      : '${value.toStringAsFixed(value == value.roundToDouble() ? 0 : 1)} ${metric.unit}';

  Widget _legend(
    BuildContext context,
    Color color,
    String label,
    bool previous,
  ) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        previous ? '┄' : '━',
        style: Theme.of(context).textTheme.titleMedium?.copyWith(color: color),
      ),
      const SizedBox(width: AppSpacing.xs),
      Flexible(
        child: Text(label, style: Theme.of(context).textTheme.bodySmall),
      ),
    ],
  );
}

class _PeriodPlot extends StatelessWidget {
  const _PeriodPlot({
    required this.comparison,
    required this.metric,
    required this.mode,
    required this.currentColor,
    required this.previousColor,
  });
  final PeriodComparison comparison;
  final PeriodMetric metric;
  final PeriodComparisonMode mode;
  final Color currentColor;
  final Color previousColor;

  @override
  Widget build(BuildContext context) {
    final count = comparison.current.length;
    final maxValue = [
      ...comparison.current,
      ...comparison.previous,
    ].whereType<double>().fold<double>(1, math.max);
    final ceiling = metric.max <= 10
        ? metric.max
        : (maxValue * 1.1).ceilToDouble();
    final style = Theme.of(context).textTheme.bodySmall!;
    return LayoutBuilder(
      builder: (context, constraints) {
        final sparseLabels =
            constraints.maxWidth < 440 ||
            MediaQuery.textScalerOf(context).scale(12) > 18;
        final indices = !sparseLabels && count == 7
            ? List.generate(7, (i) => i)
            : [0, (count - 1) ~/ 2, count - 1];
        return Column(
          children: [
            SizedBox(
              height: 200,
              child: Row(
                children: [
                  Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(ceiling.toStringAsFixed(0), style: style),
                      Text((ceiling / 2).toStringAsFixed(1), style: style),
                      Text('0', style: style),
                    ],
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Semantics(
                      label:
                          '${metric.label}, current and previous periods. Exact dates and values in Details.',
                      child: CustomPaint(
                        painter: _PeriodPainter(
                          comparison,
                          ceiling,
                          currentColor,
                          previousColor,
                          Theme.of(context).colorScheme.outlineVariant,
                        ),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final i in indices)
                  Expanded(
                    child: Text(
                      mode == PeriodComparisonMode.weekdays
                          ? const [
                              'Mon',
                              'Tue',
                              'Wed',
                              'Thu',
                              'Fri',
                              'Sat',
                              'Sun',
                            ][i]
                          : 'Day ${i + 1}',
                      style: style,
                      textAlign: i == 0
                          ? TextAlign.left
                          : i == count - 1
                          ? TextAlign.right
                          : TextAlign.center,
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _PeriodPainter extends CustomPainter {
  _PeriodPainter(
    this.data,
    this.ceiling,
    this.current,
    this.previous,
    this.grid,
  );
  final PeriodComparison data;
  final double ceiling;
  final Color current, previous, grid;

  @override
  void paint(Canvas canvas, Size size) {
    final plot = Rect.fromLTWH(
      4,
      4,
      math.max(0, size.width - 8),
      math.max(0, size.height - 8),
    );
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = plot.top + plot.height * i / 4;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), gridPaint);
    }
    void draw(List<double?> values, Color color, bool dashed) {
      final paint = Paint()
        ..color = color
        ..strokeWidth = dashed ? 2 : 3;
      Offset? before;
      for (var i = 0; i < values.length; i++) {
        final value = values[i];
        if (value == null) {
          before = null;
          continue;
        }
        final point = Offset(
          plot.left + plot.width * i / (values.length - 1),
          plot.bottom - plot.height * value / ceiling,
        );
        if (before != null) {
          if (dashed) {
            final delta = point - before;
            final distance = delta.distance;
            for (double start = 0; start < distance; start += 9) {
              canvas.drawLine(
                before + delta * (start / distance),
                before + delta * (math.min(start + 5, distance) / distance),
                paint,
              );
            }
          } else {
            canvas.drawLine(before, point, paint);
          }
        }
        canvas.drawCircle(point, dashed ? 2 : 3, paint);
        before = point;
      }
    }

    draw(data.previous, previous, true);
    draw(data.current, current, false);
  }

  @override
  bool shouldRepaint(covariant _PeriodPainter old) => true;
}
