import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('student-facing presentation source stays English and avoids old terms',
      () {
    final presentationSources = Directory('lib/features')
        .listSync(recursive: true)
        .whereType<File>()
        .where(
          (file) =>
              file.path.endsWith('.dart') &&
              file.path.contains('/presentation/'),
        )
        .toList(growable: false);
    expect(presentationSources, isNotEmpty);

    final combined =
        presentationSources.map((file) => file.readAsStringSync()).join();
    expect(combined, isNot(matches(RegExp(r'[äöüÄÖÜß]'))));

    const retiredVisiblePhrases = <String>[
      "'Morning Calibration'",
      "'Evening Shutdown'",
      "'Add signal'",
      "'Stress controllability'",
      "'In-app notifications'",
      "'Retry exact",
      "'Deterministic · no LLM'",
      "'Generated from",
      "'Coach ready'",
    ];
    for (final phrase in retiredVisiblePhrases) {
      expect(combined, isNot(contains(phrase)), reason: phrase);
    }
  });

  test('capability-limited surfaces include their required plain truth', () {
    final notifications = File(
      'lib/features/notifications/presentation/pages/notification_settings_page.dart',
    ).readAsStringSync();
    expect(
      notifications,
      contains(
        'cannot send browser, phone-system, email, push, or background notifications',
      ),
    );
    expect(notifications, contains('fixed and not AI-written'));

    final coach = File(
      'lib/features/coach/presentation/pages/coach_page.dart',
    ).readAsStringSync();
    expect(coach, contains('Development-only explanations and suggestions'));
    expect(coach, contains('This is not a production service'));

    final insights = File(
      'lib/features/insights/presentation/pages/insights_page.dart',
    ).readAsStringSync();
    expect(insights, contains('EXAMPLE SKILL PROFILE'));
    expect(insights, contains('example data only'));
  });
}
