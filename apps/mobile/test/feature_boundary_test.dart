import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('features cannot import another feature data or presentation internals',
      () {
    const allowed = <String, String>{
      'quick_action/presentation/pages/quick_mood_check_in_page.dart -> '
              'focus/presentation/widgets/focus_reflection_sheet.dart':
          'Evening Capture intentionally embeds the Focus-owned reflection '
              'sheet; the widget is the explicit reusable UI seam and carries '
              'no Focus repository or provider access.',
    };
    final features = Directory('lib/features');
    final violations = <String>[];
    final observedExceptions = <String>{};

    for (final entity in features.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final sourceFile = entity.absolute.uri;
      final sourcePath = _relativeFeaturePath(sourceFile);
      final sourceFeature = sourcePath.split('/').first;
      final source = entity.readAsStringSync();
      for (final match in _importPattern.allMatches(source)) {
        final targetPath = _targetFeaturePath(
          sourceFile: sourceFile,
          importValue: match.group(1)!,
        );
        if (targetPath == null) continue;
        final segments = targetPath.split('/');
        if (segments.length < 3 || segments.first == sourceFeature) continue;
        if (segments[1] != 'data' && segments[1] != 'presentation') continue;

        final dependency = '$sourcePath -> $targetPath';
        if (allowed.containsKey(dependency)) {
          observedExceptions.add(dependency);
        } else {
          violations.add(dependency);
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason: 'Cross-feature data/presentation imports must move to app '
          'composition or use a narrow application/domain port. Add an '
          'exception only with a concrete architectural rationale.',
    );
    expect(
      observedExceptions,
      allowed.keys.toSet(),
      reason: 'Every allowlisted exception must still exist exactly; remove '
          'stale exceptions together with the dependency.',
    );
    expect(
      allowed.values.every((reason) => reason.trim().length >= 40),
      isTrue,
      reason: 'Boundary exceptions require a useful rationale.',
    );
  });

  test('extracted page widgets stay presentation-only and feature-private', () {
    const parts = <String, String>{
      'lib/features/insights/presentation/widgets/'
              'insights_summary_widgets.dart':
          "part of '../pages/insights_page.dart';",
      'lib/features/insights/presentation/widgets/'
              'insights_exploration_widgets.dart':
          "part of '../pages/insights_page.dart';",
      'lib/features/deadline_plans/presentation/widgets/'
              'deadline_plan_card.dart':
          "part of '../pages/deadline_plans_page.dart';",
      'lib/features/deadline_plans/presentation/widgets/'
              'deadline_plan_editor_sheet.dart':
          "part of '../pages/deadline_plans_page.dart';",
      'lib/features/deadline_plans/presentation/widgets/'
              'deadline_plan_support_widgets.dart':
          "part of '../pages/deadline_plans_page.dart';",
    };
    final forbidden = <String, RegExp>{
      'Riverpod access': RegExp(
        r'\b(?:WidgetRef|ConsumerWidget|ConsumerState|ProviderRef)\b|\bref\.',
      ),
      'repository or controller access': RegExp(
        r'\b(?:Repository|Controller)\b|\b(?:insights|deadlinePlan)Provider\b',
      ),
      'route ownership': RegExp(r'\bGoRouter\b|\bAppRoutes\.|\bcontext\.go\('),
      'direct persistence': RegExp(
        r'\.(?:insert|upsert|update|delete|propose|confirm|complete|cancel)\(',
      ),
    };

    for (final entry in parts.entries) {
      final file = File(entry.key);
      expect(file.existsSync(), isTrue, reason: '${entry.key} must exist.');
      final source = file.readAsStringSync();
      expect(source, startsWith(entry.value));
      for (final rule in forbidden.entries) {
        expect(
          rule.value.hasMatch(source),
          isFalse,
          reason: '${entry.key} must not take on ${rule.key}.',
        );
      }
    }

    final insightsPage = File(
      'lib/features/insights/presentation/pages/insights_page.dart',
    ).readAsStringSync();
    final deadlinePage = File(
      'lib/features/deadline_plans/presentation/pages/deadline_plans_page.dart',
    ).readAsStringSync();
    expect(insightsPage, contains('ref.watch(insightsProvider)'));
    expect(deadlinePage, contains('ref.watch(deadlinePlanControllerProvider)'));
    expect(deadlinePage, contains('context.go(AppRoutes.planner)'));
    expect(insightsPage, isNot(contains('class _ControlsPanel')));
    expect(deadlinePage, isNot(contains('class _DeadlinePlanCard')));
  });
}

final _importPattern = RegExp(
  r'''^import\s+['"]([^'"]+)['"];''',
  multiLine: true,
);

String _relativeFeaturePath(Uri file) {
  const marker = 'lib/features/';
  final value = file.toFilePath().replaceAll(r'\', '/');
  final index = value.indexOf(marker);
  if (index < 0) throw StateError('Feature path is outside lib/features.');
  return value.substring(index + marker.length);
}

String? _targetFeaturePath({
  required Uri sourceFile,
  required String importValue,
}) {
  const packagePrefix = 'package:my_life_graph/features/';
  if (importValue.startsWith(packagePrefix)) {
    return importValue.substring(packagePrefix.length);
  }
  if (!importValue.startsWith('.')) return null;
  final target = sourceFile.resolve(importValue).toFilePath().replaceAll(
        r'\',
        '/',
      );
  const marker = 'lib/features/';
  final index = target.indexOf(marker);
  return index < 0 ? null : target.substring(index + marker.length);
}
