import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/features/quick_action/presentation/widgets/capture_leave_guard.dart';
import 'package:my_life_graph/features/focus/presentation/widgets/focus_time_sheet.dart';
import 'package:my_life_graph/features/health_connect/domain/health_sleep_suggestion.dart';

void main() {
  testWidgets(
    'capture asks before discarding, keeps edits, blocks while saving',
    (tester) async {
      var exits = 0;
      Future<void> pump(bool dirty, bool saving) => tester.pumpWidget(
        MaterialApp(
          home: CaptureLeaveGuard(
            dirty: dirty,
            saving: saving,
            onLeave: () => exits++,
            builder: (leave) => Scaffold(
              body: TextButton(onPressed: leave, child: const Text('Back')),
            ),
          ),
        ),
      );
      await pump(true, false);
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      expect(exits, 0);
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(exits, 0);
      await pump(true, true);
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsNothing);
      await pump(true, false);
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(exits, 1);
    },
  );

  testWidgets(
    'focus correction preserves retry identity and closes after success',
    (tester) async {
      final attempts = <(int, String)>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => FocusTimeSheet(
                    minutes: 30,
                    onSave: (minutes, id) async {
                      attempts.add((minutes, id));
                      if (attempts.length == 1) throw StateError('network');
                    },
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '20');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, false);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(attempts.length, 2);
      expect(attempts[0], attempts[1]);
      expect(attempts[0].$1, 20);
      expect(find.byType(FocusTimeSheet), findsNothing);
    },
  );

  test('watch sleep respects profile wake date, UTC instants and duration', () {
    final now = DateTime.utc(2026, 9, 25, 12);
    final values = {
      'started_at': '2026-09-24T21:00:00Z',
      'woke_at': '2026-09-25T05:00:00Z',
    };
    final sleep = HealthSleepSuggestion.parse(
      values,
      '2026-09-25',
      'Europe/Berlin',
      now,
    )!;
    expect(sleep.startedAt.hour, 23);
    expect(sleep.wokeAt.hour, 7);
    expect(
      HealthSleepSuggestion.parse(values, '2026-09-24', 'Europe/Berlin', now),
      isNull,
    );
    for (final invalid in <Map<String, dynamic>>[
      {...values, 'started_at': 12},
      {...values, 'started_at': '2026-09-24T21:00:00'},
      {...values, 'woke_at': '2026-09-26T05:00:00Z'},
      {...values, 'started_at': '2026-09-23T21:00:00Z'},
      {...values, 'woke_at': '2026-09-24T21:10:00Z'},
    ]) {
      expect(
        HealthSleepSuggestion.parse(
          invalid,
          '2026-09-25',
          'Europe/Berlin',
          now,
        ),
        isNull,
      );
    }
  });
}
