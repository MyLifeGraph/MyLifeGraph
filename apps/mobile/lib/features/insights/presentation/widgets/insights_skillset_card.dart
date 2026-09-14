import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/widgets/app_surface.dart';
import '../../domain/entities/correlation.dart';

// Recorded ratings and explicitly labelled window summaries; never invent
// values for missing observations.
const _dimensions = <_Dimension>[
  _Dimension('sleep', 'Sleep', 'Sleep quality', 'sleep_quality', 10),
  _Dimension(
    'sport',
    'Sport',
    '0 None · 1 Light · 2 Intense',
    'sport_activity',
    2,
    minimum: 0,
  ),
  _Dimension(
    'energy',
    'Energy',
    'Check-in energy · Morning first',
    'energy_level',
    10,
  ),
  _Dimension(
    'social',
    'Social activity',
    '0 Little · 1 Some · 2 Lots',
    'social_activity',
    2,
    minimum: 0,
  ),
  _Dimension(
    'learning',
    'Learning',
    'Completed study Focus sessions (%)',
    'learning_completion_rate',
    100,
    minimum: 0,
    summary: true,
  ),
  _Dimension(
    'concentration',
    'Concentration',
    'Rated focus quality',
    'focus_quality',
    5,
  ),
  _Dimension(
    'stress',
    'Stress',
    'Stress rating · lower is calmer',
    'stress_level',
    10,
  ),
  _Dimension('mood', 'Mood', 'Mood rating', 'mood_score', 10),
  _Dimension(
    'productivity',
    'Productivity',
    'Rated useful progress',
    'useful_progress',
    5,
  ),
  _Dimension(
    'motivation',
    'Motivation',
    '0 Low · 1 Medium · 2 High',
    'study_motivation',
    2,
    minimum: 0,
  ),
  _Dimension(
    'discipline',
    'Discipline',
    'Focus completion + sport regularity (%)',
    'regularity',
    100,
    minimum: 0,
    summary: true,
  ),
];

class _Dimension {
  const _Dimension(
    this.id,
    this.label,
    this.source,
    this.metricId,
    this.maximum, {
    this.minimum = 1,
    this.summary = false,
  });
  final String id;
  final String label;
  final String? source;
  final String? metricId;
  final double maximum;
  final double minimum;
  final bool summary;

  _Reading read(CorrelationReport report) {
    final values =
        metricId == null
              ? <double>[]
              : report.points
                    .map((point) => point.values[metricId])
                    .whereType<double>()
                    .where(
                      (value) =>
                          value.isFinite &&
                          value >= minimum &&
                          value <= maximum,
                    )
                    .toList()
          ..sort();
    if (values.isEmpty) return _Reading(this, null, 0);
    final middle = values.length ~/ 2;
    final median = values.length.isOdd
        ? values[middle]
        : (values[middle - 1] + values[middle]) / 2;
    return _Reading(this, median, values.length);
  }
}

class _Reading {
  const _Reading(this.dimension, this.value, this.days);
  final _Dimension dimension;
  final double? value;
  final int days;
  double get fraction => value! / dimension.maximum;
  String get label => value == null
      ? 'No data'
      : dimension.summary
      ? '${value!.toStringAsFixed(0)}% · selected window'
      : '${value!.toStringAsFixed(1)}/${dimension.maximum.toInt()} · $days ${days == 1 ? 'day' : 'days'}';
}

/// A read-only view of the current report, not a persisted Skillset score.
class InsightsSkillsetCard extends StatelessWidget {
  const InsightsSkillsetCard({
    super.key,
    required this.report,
    required this.isDemo,
    required this.selectedIds,
    required this.onToggle,
  });

  final CorrelationReport report;
  final bool isDemo;
  final Set<String> selectedIds;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelScale = MediaQuery.textScalerOf(context).scale(12) / 12;
    final readings = _dimensions
        .where((d) => selectedIds.contains(d.id))
        .map((d) => d.read(report))
        .toList();
    final available = readings.where((r) => r.value != null).toList();
    return AppSurface(
      variant: AppSurfaceVariant.raised,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Skillset', style: theme.textTheme.titleLarge),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${isDemo ? 'Example data · ' : ''}Your signals · ${report.windowDays} days',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          ExpansionTile(
            key: const PageStorageKey('insights-skillset-dimensions'),
            tilePadding: EdgeInsets.zero,
            leading: const Icon(AppIcons.tuneOutlined),
            title: Text('Dimensions (${readings.length})'),
            children: [
              for (final dimension in _dimensions)
                CheckboxListTile(
                  key: ValueKey('skillset-select-${dimension.id}'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(dimension.label),
                  subtitle: dimension.read(report).value == null
                      ? const Text('No data in this window')
                      : null,
                  value: selectedIds.contains(dimension.id),
                  onChanged: (_) => onToggle(dimension.id),
                ),
            ],
          ),
          if (available.length >= 3)
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: AspectRatio(
                  aspectRatio: 1.12 / labelScale.clamp(1.0, 1.6),
                  child: CustomPaint(
                    key: const Key('skillset-radar'),
                    painter: _RadarPainter(
                      values: available.map((r) => r.fraction).toList(),
                      labels: available
                          .map(
                            (r) => switch (r.dimension.id) {
                              'concentration' => 'Focus',
                              'productivity' => 'Progress',
                              _ => r.dimension.label,
                            },
                          )
                          .toList(),
                      color: theme.colorScheme.primary,
                      gridColor: theme.colorScheme.outline,
                      labelStyle: theme.textTheme.labelMedium!.copyWith(
                        color: theme.colorScheme.onSurface,
                      ),
                      textScaler: MediaQuery.textScalerOf(context),
                    ),
                  ),
                ),
              ),
            )
          else
            Padding(
              key: const Key('skillset-empty'),
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
              child: Text(
                readings.isEmpty
                    ? 'Choose dimensions to see your profile.'
                    : available.isEmpty
                    ? 'No ratings in this window yet.'
                    : 'The radar needs three dimensions with ratings. Open Details for available values.',
              ),
            ),
          ExpansionTile(
            key: const PageStorageKey('insights-skillset-details'),
            tilePadding: EdgeInsets.zero,
            title: const Text('Details'),
            children: [
              if (selectedIds.contains('learning') ||
                  selectedIds.contains('discipline'))
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    tooltip: 'How these scores work',
                    icon: const Icon(AppIcons.infoOutline),
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('How it works'),
                        content: const Text(
                          'Learning: completed ÷ ended study Focus sessions, linked to exam or preparation blocks.\n\n'
                          'Discipline: average of Focus completion and days with sport ÷ days with a sport answer. Each component needs at least 3 observations; missing components are omitted.\n\n'
                          'Motivation, skipped questions and untracked days do not lower this activity score.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Close'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              for (final reading in readings)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                  child: Text(
                    '${reading.value == null ? '—' : '${available.indexOf(reading) + 1}.'} '
                    '${reading.dimension.label} · ${reading.label}'
                    '${reading.value == null ? '' : '\n${reading.dimension.source}'}',
                    key: ValueKey('skillset-value-${reading.dimension.id}'),
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Recorded ratings and activity summaries on their own scales. '
                'Not an ability score; missing dimensions are omitted from the radar.',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  const _RadarPainter({
    required this.values,
    required this.labels,
    required this.color,
    required this.gridColor,
    required this.labelStyle,
    required this.textScaler,
  });
  final List<double> values;
  final List<String> labels;
  final Color color;
  final Color gridColor;
  final TextStyle labelStyle;
  final TextScaler textScaler;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) * .33;
    Offset point(int index, double fraction) {
      final angle = -math.pi / 2 + 2 * math.pi * index / values.length;
      return center +
          Offset(math.cos(angle), math.sin(angle)) * radius * fraction;
    }

    Path polygon(List<double> fractions) {
      final path = Path()
        ..moveTo(point(0, fractions[0]).dx, point(0, fractions[0]).dy);
      for (var i = 1; i < fractions.length; i++) {
        final vertex = point(i, fractions[i]);
        path.lineTo(vertex.dx, vertex.dy);
      }
      return path..close();
    }

    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1.15
      ..style = PaintingStyle.stroke;
    for (var ring = 1; ring <= 4; ring++) {
      canvas.drawPath(polygon(List.filled(values.length, ring / 4)), grid);
    }
    for (var i = 0; i < values.length; i++) {
      canvas.drawLine(center, point(i, 1), grid);
      final label = TextPainter(
        text: TextSpan(text: '${i + 1}. ${labels[i]}', style: labelStyle),
        textScaler: textScaler,
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width * .36);
      final anchor = point(i, 1.35);
      label.paint(
        canvas,
        Offset(
          (anchor.dx - label.width / 2).clamp(0, size.width - label.width),
          (anchor.dy - label.height / 2).clamp(0, size.height - label.height),
        ),
      );
    }
    final path = polygon(values);
    canvas.drawPath(path, Paint()..color = color.withValues(alpha: .15));
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    for (var i = 0; i < values.length; i++) {
      canvas.drawCircle(point(i, values[i]), 3, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant _RadarPainter oldDelegate) =>
      oldDelegate.values != values ||
      oldDelegate.labels != labels ||
      oldDelegate.color != color ||
      oldDelegate.gridColor != gridColor ||
      oldDelegate.labelStyle != labelStyle ||
      oldDelegate.textScaler != textScaler;
}
