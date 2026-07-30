import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/features/focus/domain/focus_session.dart';
import 'package:my_life_graph/features/focus/presentation/widgets/focus_reflection_sheet.dart';

void main() {
  testWidgets('reflection keeps choices after save failure and retries exactly',
      (tester) async {
    var calls = 0;
    FocusReflectionDraft? lastDraft;
    await _pumpLauncher(
      tester,
      session: _terminalSession(),
      onSave: (draft) async {
        calls += 1;
        lastDraft = draft;
        if (calls == 1) {
          throw StateError('offline');
        }
        return _reflection(draft);
      },
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Reflect on this Focus session'), findsOneWidget);
    expect(
      find.text('What got in the way? Optional, choose up to two'),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('focus-quality-rating-2')));
    await tester.tap(find.byKey(const ValueKey('useful-progress-rating-4')));
    await tester.pump();
    expect(
      find.text('What got in the way? Optional, choose up to two'),
      findsOneWidget,
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('focus-obstacle-distracted')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('focus-obstacle-distracted')),
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('save-focus-reflection')),
    );
    await tester.drag(
      find.byType(SingleChildScrollView).last,
      const Offset(0, -160),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('save-focus-reflection')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('focus-reflection-error')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<ChoiceChip>(
            find.byKey(const ValueKey('focus-quality-rating-2')),
          )
          .selected,
      isTrue,
    );
    expect(
      tester
          .widget<FilterChip>(
            find.byKey(const ValueKey('focus-obstacle-distracted')),
          )
          .selected,
      isTrue,
    );

    await tester.ensureVisible(
      find.byKey(const ValueKey('save-focus-reflection')),
    );
    await tester.drag(
      find.byType(SingleChildScrollView).last,
      const Offset(0, -80),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('save-focus-reflection')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('focus-reflection-sheet')), findsNothing);
    expect(calls, 2);
    expect(lastDraft?.focusQuality, 2);
    expect(lastDraft?.usefulProgress, 4);
    expect(lastDraft?.obstacles, [FocusObstacle.distracted]);
  });

  testWidgets('obstacles are limited to two and abandoned shows them at once',
      (tester) async {
    await _pumpLauncher(
      tester,
      session: _terminalSession(status: FocusSessionStatus.abandoned),
      onSave: (draft) async => _reflection(draft),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(
      find.text('What got in the way? Optional, choose up to two'),
      findsOneWidget,
    );

    for (final code in ['tired', 'distracted', 'interrupted']) {
      await tester.ensureVisible(
        find.byKey(ValueKey('focus-obstacle-$code')),
      );
      await tester.tap(find.byKey(ValueKey('focus-obstacle-$code')));
      await tester.pump();
    }
    expect(
      tester
          .widget<FilterChip>(
            find.byKey(const ValueKey('focus-obstacle-tired')),
          )
          .selected,
      isTrue,
    );
    expect(
      tester
          .widget<FilterChip>(
            find.byKey(const ValueKey('focus-obstacle-distracted')),
          )
          .selected,
      isTrue,
    );
    expect(
      tester
          .widget<FilterChip>(
            find.byKey(const ValueKey('focus-obstacle-interrupted')),
          )
          .selected,
      isFalse,
    );
  });

  testWidgets('active sessions are rejected before a sheet opens',
      (tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (builderContext) {
            context = builderContext;
            return const SizedBox();
          },
        ),
      ),
    );
    final active = FocusSession(
      id: 'active',
      status: FocusSessionStatus.active,
      startedAt: DateTime.utc(2026, 7, 26, 8),
      plannedMinutes: 25,
      updatedAt: DateTime.utc(2026, 7, 26, 8),
    );
    expect(
      () => showFocusReflectionSheet(
        context: context,
        session: active,
        existing: null,
        onSave: (draft) async => _reflection(draft),
        onDelete: (_) async {},
      ),
      throwsA(isA<FocusCommandException>()),
    );
  });

  testWidgets('sheet remains usable at 320 pixels and 200 percent text',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pumpLauncher(
      tester,
      session: _terminalSession(),
      textScale: 2,
      onSave: (draft) async => _reflection(draft),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Scattered'), findsOneWidget);
    expect(find.text('Deeply focused'), findsOneWidget);
    expect(find.byKey(const ValueKey('skip-focus-reflection')), findsOneWidget);
    expect(find.byKey(const ValueKey('save-focus-reflection')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('both rating scales align anchors under columns 1, 3, and 5',
      (tester) async {
    await _pumpLauncher(
      tester,
      session: _terminalSession(),
      onSave: (draft) async => _reflection(draft),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    for (final prefix in ['focus-quality', 'useful-progress']) {
      for (final rating in [1, 3, 5]) {
        final chip = tester.getRect(
          find.byKey(ValueKey('$prefix-rating-$rating')),
        );
        final anchor = tester.getRect(
          find.byKey(ValueKey('$prefix-anchor-$rating')),
        );
        expect(chip.center.dx, closeTo(anchor.center.dx, 0.01));
      }
    }
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpLauncher(
  WidgetTester tester, {
  required FocusSession session,
  required Future<FocusReflection> Function(FocusReflectionDraft) onSave,
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
        ),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showFocusReflectionSheet(
              context: context,
              session: session,
              existing: null,
              onSave: onSave,
              onDelete: (_) async {},
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
}

FocusSession _terminalSession({
  FocusSessionStatus status = FocusSessionStatus.completed,
}) {
  final startedAt = DateTime.utc(2026, 7, 26, 8);
  final endedAt = startedAt.add(const Duration(minutes: 25));
  return FocusSession(
    id: 'focus-terminal',
    status: status,
    startedAt: startedAt,
    endedAt: endedAt,
    plannedMinutes: 25,
    actualMinutes: 25,
    updatedAt: endedAt,
  );
}

FocusReflection _reflection(FocusReflectionDraft draft) {
  final now = DateTime.utc(2026, 7, 26, 8, 30);
  return FocusReflection(
    focusSessionId: 'focus-terminal',
    focusQuality: draft.focusQuality,
    usefulProgress: draft.usefulProgress,
    obstacles: draft.obstacles,
    createdAt: now,
    updatedAt: now,
  );
}
