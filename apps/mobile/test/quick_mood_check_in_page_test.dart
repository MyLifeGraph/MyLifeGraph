import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:my_life_graph/features/quick_action/domain/quick_check_in.dart';
import 'package:my_life_graph/features/quick_action/presentation/pages/quick_mood_check_in_page.dart';
import 'package:my_life_graph/features/quick_action/presentation/providers/quick_check_in_providers.dart';

void main() {
  testWidgets('failed save retains exact draft and retry succeeds',
      (tester) async {
    final store = _FailOnceQuickCheckInStore();
    await _pumpPage(tester, store);

    expect(_nextButton(tester).onPressed, isNull);
    await _completeDraft(tester);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(
      find.text('Could not save. Your choices are still here. Try again.'),
      findsWidgets,
    );
    expect(store.attempts, hasLength(1));
    expect(store.attempts.single.mood, 2);
    expect(store.attempts.single.energy, 9);
    expect(store.attempts.single.sleepHours, 5.5);
    expect(store.attempts.single.stress, 8);
    expect(store.attempts.single.contextNote, 'Exact retry note');

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Dashboard destination'), findsOneWidget);
    expect(store.attempts, hasLength(2));
    expect(store.attempts[1].captureId, store.attempts[0].captureId);
    expect(store.attempts[1].toJson(), store.attempts[0].toJson());
  });

  testWidgets('saving state prevents a duplicate in-flight write',
      (tester) async {
    final store = _PendingQuickCheckInStore();
    await _pumpPage(tester, store);
    await _completeDraft(tester);

    await tester.tap(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pump();

    expect(store.calls, 1);
    store.complete();
    await tester.pumpAndSettle();
    expect(find.text('Dashboard destination'), findsOneWidget);
  });
}

Future<void> _pumpPage(
  WidgetTester tester,
  QuickCheckInStore store,
) async {
  final router = GoRouter(
    initialLocation: '/quick-mood-check-in',
    routes: [
      GoRoute(
        path: '/quick-mood-check-in',
        builder: (_, __) => const QuickMoodCheckInPage(),
      ),
      GoRoute(
        path: '/dashboard',
        builder: (_, __) => const Scaffold(
          body: Text('Dashboard destination'),
        ),
      ),
      GoRoute(
        path: '/quick-action',
        builder: (_, __) => const Scaffold(body: Text('Quick action')),
      ),
    ],
  );
  addTearDown(router.dispose);
  tester.view.physicalSize = const Size(1200, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(
    ProviderScope(
      overrides: [quickCheckInStoreProvider.overrideWithValue(store)],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _completeDraft(WidgetTester tester) async {
  await tester.tap(find.bySemanticsLabel('mood 2 of 10'));
  await tester.pump();
  await tester.tap(find.text('Next'));
  await tester.pumpAndSettle();

  await tester.tap(find.bySemanticsLabel('energy 9 of 10'));
  await tester.pump();
  await tester.tap(find.text('Next'));
  await tester.pumpAndSettle();

  final sleepSlider = tester.widget<Slider>(find.byType(Slider));
  sleepSlider.onChanged!(5.5);
  await tester.pump();
  await tester.tap(find.text('Next'));
  await tester.pumpAndSettle();

  await tester.tap(find.bySemanticsLabel('stress 8 of 10'));
  await tester.pump();
  await tester.tap(find.text('Next'));
  await tester.pumpAndSettle();

  await tester.enterText(find.byType(TextField), 'Exact retry note');
}

FilledButton _nextButton(WidgetTester tester) {
  return tester.widget<FilledButton>(find.byType(FilledButton));
}

class _FailOnceQuickCheckInStore implements QuickCheckInStore {
  final List<QuickCheckInDraft> attempts = [];

  @override
  QuickCheckInSaveTarget get target => QuickCheckInSaveTarget.guest;

  @override
  Future<QuickCheckInDraft?> loadToday(DateTime today) async => null;

  @override
  Future<void> save(QuickCheckInDraft draft) async {
    attempts.add(draft.normalized());
    if (attempts.length == 1) {
      throw StateError('planned failure');
    }
  }
}

class _PendingQuickCheckInStore implements QuickCheckInStore {
  final Completer<void> _completer = Completer<void>();
  int calls = 0;

  @override
  QuickCheckInSaveTarget get target => QuickCheckInSaveTarget.guest;

  @override
  Future<QuickCheckInDraft?> loadToday(DateTime today) async => null;

  @override
  Future<void> save(QuickCheckInDraft draft) {
    calls++;
    return _completer.future;
  }

  void complete() => _completer.complete();
}
