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
