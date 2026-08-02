part of '../pages/insights_page.dart';

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
      blockedWithMetricId: metricBId,
      onChanged: onMetricAChanged,
    );
    final pickerB = _MetricPicker(
      label: 'With',
      metrics: metrics,
      value: metricBId,
      blockedWithMetricId: metricAId,
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
          ButtonSegment(value: 90, label: Text('90d')),
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
    required this.blockedWithMetricId,
    required this.onChanged,
  });

  final String label;
  final List<CorrelationMetric> metrics;
  final String value;
  final String blockedWithMetricId;
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
              enabled: metric.id == value ||
                  (metric.id != blockedWithMetricId &&
                      !const CorrelationPairPolicy().isBlocked(
                        metric.id,
                        blockedWithMetricId,
                      )),
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
    final colors = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final useStackedHeader =
        isMobile || MediaQuery.textScalerOf(context).scale(14) > 18;
    final selectedMetrics = report.metrics
        .where((metric) => selectedMetricIds.contains(metric.id))
        .toList(growable: false);
    final series = _buildTrendSeries(
      report.points,
      selectedMetrics,
      brightness,
    );

    return _InsightsPanel(
      padding: EdgeInsets.all(isMobile ? AppSpacing.md : AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (useStackedHeader) ...[
            _TrendOverlayHeading(),
            const SizedBox(height: AppSpacing.md),
            _SmallInfoBadge(label: '0-100 normalized'),
          ] else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Expanded(child: _TrendOverlayHeading()),
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
                  onSelected: !selectedMetricIds.contains(metric.id) &&
                          selectedMetricIds.any(
                            (selected) =>
                                const CorrelationPairPolicy().isBlocked(
                              selected,
                              metric.id,
                            ),
                          )
                      ? null
                      : (_) => onMetricToggled(metric.id),
                  selectedColor: _trendColorForMetric(metric.id, brightness)
                      .withValues(alpha: 0.22),
                  checkmarkColor: _trendColorForMetric(metric.id, brightness),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Previous-night sleep is placed on the local wake and Focus day. '
            'Focus values include rated sessions only. Each line is normalized '
            'relative to its own range.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            height: isMobile ? 260 : 340,
            child: CustomPaint(
              painter: _TrendOverlayPainter(
                series: series,
                axisColor: colors.outline,
                gridColor: colors.outlineVariant,
                labelColor: colors.onSurfaceVariant,
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
    Brightness brightness,
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
          color: _trendColorForMetric(metric.id, brightness),
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
        color: _trendColorForMetric(metric.id, brightness),
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

class _TrendOverlayHeading extends StatelessWidget {
  const _TrendOverlayHeading();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Trend overlay',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Compare daily evidence without treating the lines as the same scale.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}

class _SmallInfoBadge extends StatelessWidget {
  const _SmallInfoBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(color: colors.outlineVariant),
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
    final colors = Theme.of(context).colorScheme;
    final olderPointColor = colors.onSurfaceVariant;
    final useStackedContent =
        isMobile || MediaQuery.textScalerOf(context).scale(14) > 18;
    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${metricA.label} vs ${metricB.label}',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          activeResult?.summary ?? 'Choose two different signals to compare.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
        ),
      ],
    );
    final badge = _CorrelationBadge(
      result: activeResult,
      metricA: metricA,
      metricB: metricB,
    );
    return _InsightsPanel(
      padding: EdgeInsets.all(isMobile ? AppSpacing.md : AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (useStackedContent) ...[
            heading,
            const SizedBox(height: AppSpacing.md),
            badge,
          ] else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: heading),
                const SizedBox(width: AppSpacing.md),
                badge,
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
                color: colors.primary,
                trendColor:
                    _resultColor(context, activeResult, metricA, metricB),
                axisColor: colors.outline,
                gridColor: colors.outlineVariant,
                labelColor: colors.onSurfaceVariant,
                pointOutlineColor: colors.surface,
                olderPointColor: olderPointColor,
              ),
              child: const SizedBox.expand(),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _PointLegend(
            olderColor: olderPointColor,
            newerColor: colors.primary,
          ),
          const SizedBox(height: AppSpacing.sm),
          if (useStackedContent)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${metricA.label} (${metricA.unit})',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '${activeResult?.sampleSize ?? values.length} shared days',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '${metricB.label} (${metricB.unit})',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            )
          else
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${metricA.label} (${metricA.unit})',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  '${activeResult?.sampleSize ?? values.length} shared days',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    '${metricB.label} (${metricB.unit})',
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
    final color = _resultColor(context, result, metricA, metricB);
    return Container(
      width: 112,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(AppRadii.lg),
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
                color: Theme.of(context).colorScheme.onSurfaceVariant,
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
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Container(
          width: 11,
          height: 11,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
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
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
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
    final color = _resultColor(context, result, metricA, metricB);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
            child: Icon(
              result.coefficient! >= 0
                  ? AppIcons.trendingUp
                  : AppIcons.trendingDown,
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
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
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
            'Tap a comparable cell to inspect it. Overlapping signals are not compared.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: AppSpacing.lg),
          LayoutBuilder(
            builder: (context, constraints) {
              final desktop = constraints.maxWidth >= 700;
              final textScale = MediaQuery.textScalerOf(context).scale(13) / 13;
              final widthScale = textScale.clamp(1.0, 2.0);
              final rowLabelScale = textScale.clamp(1.0, 1.25);
              final rowLabelWidth = (desktop ? 196.0 : 144.0) * rowLabelScale;
              final cellWidth = 88.0 * widthScale;
              final cellStride = cellWidth + AppSpacing.xs;
              final rowHeight = math.max(56.0, 70 * textScale);
              final headerHeight = math.max(
                desktop ? 72.0 : 64.0,
                70 * textScale,
              );

              return Row(
                key: const ValueKey('insights-correlation-matrix-grid'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: rowLabelWidth,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          height: headerHeight + AppSpacing.xs,
                          child: Align(
                            alignment: Alignment.bottomLeft,
                            child: Text(
                              'Metric',
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ),
                        ),
                        ...report.metrics.map(
                          (metric) => Padding(
                            padding: const EdgeInsets.only(
                              bottom: AppSpacing.xs,
                            ),
                            child: _MatrixRowLabel(
                              metricId: metric.id,
                              label: metric.label,
                              height: rowHeight,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: report.metrics
                                .map(
                                  (metric) => _MatrixHeaderCell(
                                    metricId: metric.id,
                                    label: metric.label,
                                    width: cellStride,
                                    height: headerHeight,
                                  ),
                                )
                                .toList(growable: false),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          ...report.metrics.map(
                            (rowMetric) => Padding(
                              padding: const EdgeInsets.only(
                                bottom: AppSpacing.xs,
                              ),
                              child: Row(
                                children: report.metrics.map(
                                  (columnMetric) {
                                    final result = report.resultFor(
                                      rowMetric.id,
                                      columnMetric.id,
                                    );
                                    final color = _resultColor(
                                      context,
                                      result,
                                      rowMetric,
                                      columnMetric,
                                    );
                                    final selected = _isSelectedPair(
                                      rowMetric.id,
                                      columnMetric.id,
                                    );
                                    final overlapping =
                                        const CorrelationPairPolicy().isBlocked(
                                      rowMetric.id,
                                      columnMetric.id,
                                    );
                                    final disabled =
                                        rowMetric.id == columnMetric.id ||
                                            overlapping;
                                    return _MatrixCell(
                                      cellKey: ValueKey(
                                        'insights-matrix-cell-${rowMetric.id}-${columnMetric.id}',
                                      ),
                                      rowLabel: rowMetric.label,
                                      columnLabel: columnMetric.label,
                                      result: result,
                                      color: color,
                                      selected: selected && !disabled,
                                      disabled: disabled,
                                      overlappingSignals: overlapping,
                                      width: cellWidth,
                                      height: rowHeight,
                                      onTap: disabled
                                          ? null
                                          : () => onPairSelected(
                                                rowMetric.id,
                                                columnMetric.id,
                                              ),
                                    );
                                  },
                                ).toList(growable: false),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
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
  const _MatrixHeaderCell({
    required this.metricId,
    required this.label,
    required this.width,
    required this.height,
  });

  final String metricId;
  final String label;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.xs),
      child: SizedBox(
        key: ValueKey('insights-matrix-column-$metricId'),
        width: width - AppSpacing.xs,
        height: height,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Text(
            label,
            maxLines: 4,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ),
      ),
    );
  }
}

class _MatrixRowLabel extends StatelessWidget {
  const _MatrixRowLabel({
    required this.metricId,
    required this.label,
    required this.height,
  });

  final String metricId;
  final String label;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: ValueKey('insights-matrix-row-$metricId'),
      height: height,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          label,
          maxLines: 4,
          style: Theme.of(context).textTheme.labelMedium,
        ),
      ),
    );
  }
}

class _MatrixCell extends StatelessWidget {
  const _MatrixCell({
    required this.cellKey,
    required this.rowLabel,
    required this.columnLabel,
    required this.result,
    required this.color,
    required this.selected,
    required this.disabled,
    required this.overlappingSignals,
    required this.width,
    required this.height,
    required this.onTap,
  });

  final Key cellKey;
  final String rowLabel;
  final String columnLabel;
  final CorrelationResult? result;
  final Color color;
  final bool selected;
  final bool disabled;
  final bool overlappingSignals;
  final double width;
  final double height;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final earlyEvidence = result?.status == CorrelationStatus.earlyEvidence;
    final fillColor = disabled || earlyEvidence
        ? colors.surfaceContainerHighest
        : color.withValues(
            alpha: (result?.coefficient?.abs() ?? 0.08).clamp(0.12, 0.9),
          );
    final resultDescription = switch (result) {
      null => 'No result',
      final value when value.coefficient == null => value.strengthLabel,
      final value => '${value.coefficientLabel}. ${value.strengthLabel}',
    };
    final semanticLabel = overlappingSignals
        ? '$rowLabel and $columnLabel. Not compared · overlapping signals'
        : disabled
            ? '$rowLabel, same metric'
            : '$rowLabel and $columnLabel correlation. $resultDescription';
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.xs),
      child: Semantics(
        key: cellKey,
        container: true,
        label: semanticLabel,
        button: !disabled,
        enabled: !disabled,
        selected: disabled ? null : selected,
        onTap: disabled ? null : onTap,
        child: ExcludeSemantics(
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppRadii.md),
            child: Container(
              width: width,
              height: height,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: fillColor,
                borderRadius: BorderRadius.circular(AppRadii.md),
                border: Border.all(
                  color: selected ? colors.primary : colors.outlineVariant,
                  width: selected ? 2 : 1,
                ),
              ),
              child: Text(
                overlappingSignals
                    ? 'Not compared\n· overlapping signals'
                    : disabled
                        ? '·'
                        : result?.coefficientLabel ?? '--',
                maxLines: 3,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color:
                          disabled ? colors.onSurfaceVariant : colors.onSurface,
                    ),
              ),
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
                AppIcons.psychologyOutlined,
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
                      'Stored insights and previous notes',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
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
                child: InsightsPatternTile(
                  insight: insight,
                  isMobile: isMobile,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class InsightsPatternTile extends StatelessWidget {
  const InsightsPatternTile({
    super.key,
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
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      child: isMobile
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: AppSpacing.md,
                  runSpacing: AppSpacing.sm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      insight.title,
                      key: ValueKey('insight-pattern-title-${insight.id}'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    _ConfidenceBadge(
                      key: ValueKey(
                        'insight-pattern-confidence-${insight.id}',
                      ),
                      label: insight.confidenceLabel,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  insight.summary,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                              height: 1.45,
                            ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                _ConfidenceBadge(label: insight.confidenceLabel),
              ],
            ),
    );
  }
}

class _ConfidenceBadge extends StatelessWidget {
  const _ConfidenceBadge({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Text(
        label,
        softWrap: true,
        textAlign: TextAlign.center,
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
    required this.axisColor,
    required this.gridColor,
    required this.labelColor,
    required this.pointOutlineColor,
    required this.olderPointColor,
  });

  final List<MetricPairValues> values;
  final CorrelationMetric metricA;
  final CorrelationMetric metricB;
  final Color color;
  final Color trendColor;
  final Color axisColor;
  final Color gridColor;
  final Color labelColor;
  final Color pointOutlineColor;
  final Color olderPointColor;

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
      ..color = gridColor
      ..strokeWidth = 1;
    final axisPaint = Paint()
      ..color = axisColor
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
      color: labelColor,
      fontSize: 10,
    );
    final titleStyle = TextStyle(
      color: labelColor,
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
      ..color = pointOutlineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    for (var index = 0; index < sortedValues.length; index++) {
      final value = sortedValues[index];
      final recency =
          sortedValues.length == 1 ? 1.0 : index / (sortedValues.length - 1);
      final pointPaint = Paint()
        ..color = _pointColorForRecency(recency, color, olderPointColor)
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
        trendColor != oldDelegate.trendColor ||
        axisColor != oldDelegate.axisColor ||
        gridColor != oldDelegate.gridColor ||
        labelColor != oldDelegate.labelColor ||
        pointOutlineColor != oldDelegate.pointOutlineColor ||
        olderPointColor != oldDelegate.olderPointColor;
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
    required this.labelColor,
  });

  final List<_TrendSeries> series;
  final Color axisColor;
  final Color gridColor;
  final Color labelColor;

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
      color: labelColor,
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
        gridColor != oldDelegate.gridColor ||
        labelColor != oldDelegate.labelColor;
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
    this.panelKey,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Key? panelKey;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      key: panelKey,
      padding: padding,
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadii.xl),
        border: Border.all(color: colors.outlineVariant, width: 2),
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
  BuildContext context,
  CorrelationResult? result,
  CorrelationMetric metricA,
  CorrelationMetric metricB,
) {
  final colors = Theme.of(context).colorScheme;
  final tokens = context.visualTokens;
  final coefficient = result?.coefficient;
  if (coefficient == null) {
    return colors.onSurfaceVariant;
  }
  if (result?.status == CorrelationStatus.earlyEvidence) {
    return colors.onSurfaceVariant;
  }
  if (coefficient.abs() < 0.2) {
    return tokens.attention;
  }

  final bothPositive = metricA.higherIsPositive && metricB.higherIsPositive;
  final bothRisk = !metricA.higherIsPositive && !metricB.higherIsPositive;
  final mixedValence = metricA.higherIsPositive != metricB.higherIsPositive;
  final supportive = (bothPositive && coefficient > 0) ||
      (mixedValence && coefficient < 0) ||
      (bothRisk && coefficient < 0);

  if (supportive) {
    return tokens.success;
  }
  return tokens.danger;
}

Color _pointColorForRecency(
  double recency,
  Color newestColor,
  Color olderPointColor,
) {
  final middle = Color.lerp(
    olderPointColor,
    const Color(0xFF4968B8),
    recency,
  );
  return Color.lerp(middle, newestColor, recency * 0.7) ?? newestColor;
}

Color _trendColorForMetric(String metricId, Brightness brightness) {
  if (brightness == Brightness.light) {
    return switch (metricId) {
      'sleep_hours' => const Color(0xFF3154A3),
      'focus_minutes' => const Color(0xFF18794E),
      'planned_minutes' => const Color(0xFF795900),
      'stress_level' => const Color(0xFFB3261E),
      'energy_level' => const Color(0xFF006A65),
      'mood_score' => const Color(0xFF7B1FA2),
      'screen_time_hours' => const Color(0xFF5E35B1),
      'activity_level' => const Color(0xFF2E7D32),
      'steps' => const Color(0xFF0061A4),
      'habit_completion_rate' => const Color(0xFF8A4B08),
      _ => const Color(0xFF334155),
    };
  }
  return switch (metricId) {
    'sleep_hours' => const Color(0xFF8EA7FF),
    'focus_minutes' => const Color(0xFF66D19E),
    'planned_minutes' => const Color(0xFFFFC857),
    'stress_level' => const Color(0xFFFF8F70),
    'energy_level' => const Color(0xFF2ED3C6),
    'mood_score' => const Color(0xFFE38CFF),
    'screen_time_hours' => const Color(0xFFB7A6FF),
    'activity_level' => const Color(0xFF8FE388),
    'steps' => const Color(0xFF4FB3FF),
    'habit_completion_rate' => const Color(0xFFFFB86B),
    _ => const Color(0xFFEFF4F6),
  };
}
