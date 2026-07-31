import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:my_life_graph/core/constants/app_spacing.dart';
import 'package:my_life_graph/core/theme/app_icons.dart';
import 'package:my_life_graph/core/widgets/app_page.dart';
import 'package:my_life_graph/features/coach/application/coach_turn_notice.dart';
import 'package:my_life_graph/features/coach/domain/coach.dart';
import 'package:my_life_graph/features/coach/domain/coach_repository.dart';
import 'package:my_life_graph/features/coach/presentation/pages/coach_page.dart';
import 'package:my_life_graph/features/coach/presentation/providers/coach_providers.dart';
import 'package:my_life_graph/composition/widgets/app_header_actions.dart';

import 'support/coach_fixtures.dart';

void main() {
  testWidgets(
    'draft and running turn survive navigation until the answer is read',
    (tester) async {
      final repository = _ControlledCoachRepository(
        reply: List.filled(
          32,
          'Your recorded Focus sessions show a stable afternoon pattern.',
        ).join(' '),
      );
      final router = _router();
      addTearDown(router.dispose);
      await _pumpApp(tester, router: router, repository: repository);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(CoachPage)),
      );

      await tester.enterText(
        find.byKey(const Key('coach-message-field')),
        'Compare my whole Focus history',
      );
      final requestId = container.read(coachControllerProvider).requestId;

      router.go('/today');
      await tester.pumpAndSettle();
      expect(
        container.read(coachControllerProvider).draft,
        'Compare my whole Focus history',
      );
      expect(container.read(coachControllerProvider).requestId, requestId);
      expect(repository.cancelCalls, 0);

      router.go('/coach');
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(
              find.byKey(const Key('coach-message-field')),
            )
            .controller
            ?.text,
        'Compare my whole Focus history',
      );
      expect(container.read(coachControllerProvider).requestId, requestId);

      await _scrollTo(tester, find.byKey(const Key('coach-send-button')));
      await tester.tap(find.byKey(const Key('coach-send-button')));
      await tester.pump();
      await tester.pump();
      expect(container.read(coachControllerProvider).isSending, isTrue);

      router.go('/today');
      await tester.pumpAndSettle();
      expect(repository.cancelCalls, 0);
      repository.complete();
      await tester.pumpAndSettle();

      expect(repository.cancelCalls, 0);
      expect(
        container.read(coachControllerProvider).latestResponse?.requestId,
        requestId,
      );
      expect(container.read(coachControllerProvider).draft, isEmpty);
      expect(
        container.read(coachTurnNoticeProvider)?.status,
        CoachTurnNoticeStatus.completed,
      );
      expect(
        find.byKey(const ValueKey('global-header-coach-notice')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey('global-header-coach-notice')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Your Coach answer is ready.'), findsOneWidget);
      expect(find.byIcon(Icons.close), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(container.read(coachTurnNoticeProvider), isNotNull);
      expect(
        find.byKey(const ValueKey('global-header-coach-notice')),
        findsOneWidget,
      );

      router.go('/coach');
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/coach');
      expect(find.byType(CoachPage), findsOneWidget);
      expect(container.read(coachTurnNoticeProvider), isNotNull);

      final details = await _scrollUntilBuilt(
        tester,
        find.text('Data and analysis details'),
      );
      await Scrollable.ensureVisible(
        tester.element(details),
        alignment: 0.7,
        duration: Duration.zero,
      );
      await tester.pumpAndSettle();
      expect(container.read(coachTurnNoticeProvider), isNull);
    },
  );

  testWidgets('short fully visible answer is read after its first layout',
      (tester) async {
    final repository = _ControlledCoachRepository();
    final router = _router();
    addTearDown(router.dispose);
    await _pumpApp(tester, router: router, repository: repository);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(CoachPage)),
    );

    await tester.enterText(
      find.byKey(const Key('coach-message-field')),
      'Give me the short version',
    );
    await _scrollTo(tester, find.byKey(const Key('coach-send-button')));
    await tester.tap(find.byKey(const Key('coach-send-button')));
    await tester.pump();
    repository.complete();
    await tester.pumpAndSettle();

    expect(container.read(coachTurnNoticeProvider), isNull);
  });

  testWidgets('Settings is pushed, selected, and returns to the source page',
      (tester) async {
    final repository = _ControlledCoachRepository();
    final router = _router(initialLocation: '/today');
    addTearDown(router.dispose);
    await _pumpApp(tester, router: router, repository: repository);

    final settingsButton = tester.widget<IconButton>(
      find.byKey(const ValueKey('global-header-settings')),
    );
    expect(settingsButton.onPressed, isNotNull);
    settingsButton.onPressed!.call();
    await tester.pumpAndSettle();

    expect(find.text('Settings content'), findsOneWidget);
    expect(find.byIcon(AppIcons.settings), findsOneWidget);
    expect(find.byTooltip('Settings, current page'), findsOneWidget);
    final pushedMatchCount = _imperativeMatchCount(
      router.routerDelegate.currentConfiguration.matches,
    );
    expect(pushedMatchCount, 1);

    await tester.tap(
      find.byKey(const ValueKey('global-header-settings')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Settings content'), findsOneWidget);
    expect(
      _imperativeMatchCount(
        router.routerDelegate.currentConfiguration.matches,
      ),
      pushedMatchCount,
    );

    await tester.tap(find.byKey(const ValueKey('app-page-back')));
    await tester.pumpAndSettle();
    expect(find.text('Today content'), findsOneWidget);
  });

  testWidgets('header actions retain 44 pixel targets at 320px and 200% text',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final repository = _ControlledCoachRepository();
    final router = _router(initialLocation: '/today');
    addTearDown(router.dispose);
    await _pumpApp(
      tester,
      router: router,
      repository: repository,
      textScaler: TextScaler.linear(2),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.text('Today content')),
    );
    container.read(coachTurnNoticeProvider.notifier).publish(
          profileId: 'profile-1',
          requestId: coachRequestId,
          status: CoachTurnNoticeStatus.completed,
        );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    for (final key in const [
      ValueKey('today-refresh'),
      ValueKey('global-header-coach-notice'),
      ValueKey('global-header-settings'),
    ]) {
      final size = tester.getSize(find.byKey(key));
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));
    }
  });
}

Future<void> _pumpApp(
  WidgetTester tester, {
  required GoRouter router,
  required CoachRepository repository,
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        coachActiveProfileIdProvider.overrideWithValue('profile-1'),
        coachRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

GoRouter _router({String initialLocation = '/coach'}) => GoRouter(
      initialLocation: initialLocation,
      routes: [
        GoRoute(
          path: '/coach',
          builder: (_, __) => const Scaffold(body: CoachPage()),
        ),
        GoRoute(
          path: '/today',
          builder: (_, __) => Scaffold(
            body: AppPage(
              title: 'Today',
              actions: [
                AppHeaderActions(
                  pageActions: [
                    IconButton(
                      key: const ValueKey('today-refresh'),
                      tooltip: 'Refresh Today',
                      onPressed: () {},
                      icon: const Icon(AppIcons.refreshOutlined),
                    ),
                  ],
                ),
              ],
              children: const [
                Text('Today content'),
                SizedBox(height: AppSpacing.xxl),
              ],
            ),
          ),
        ),
        GoRoute(
          path: '/settings',
          builder: (_, __) => const Scaffold(
            body: AppPage(
              title: 'Settings',
              actions: [AppHeaderActions(settingsSelected: true)],
              children: [Text('Settings content')],
            ),
          ),
        ),
      ],
    );

Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

Future<Finder> _scrollUntilBuilt(
  WidgetTester tester,
  Finder finder,
) async {
  for (var attempt = 0; attempt < 20 && finder.evaluate().isEmpty; attempt++) {
    await tester.drag(
      find.byType(Scrollable).first,
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
  }
  expect(finder, findsWidgets);
  return finder.last;
}

int _imperativeMatchCount(Iterable<RouteMatchBase> matches) {
  var count = 0;
  for (final match in matches) {
    if (match is ImperativeRouteMatch) count++;
    if (match is ShellRouteMatch) {
      count += _imperativeMatchCount(match.matches);
    }
  }
  return count;
}

class _ControlledCoachRepository implements CoachRepository {
  _ControlledCoachRepository({
    this.reply = 'A short Coach answer.',
  });

  final String reply;
  final Completer<void> _completion = Completer<void>();
  String? _requestId;
  String? _message;
  bool _responding = false;
  int cancelCalls = 0;

  void complete() {
    if (!_completion.isCompleted) _completion.complete();
  }

  @override
  Future<CoachCapabilities> getCapabilities() async =>
      CoachCapabilities.fromJson(coachCapabilitiesJson());

  @override
  Future<CoachHistory> getHistory() async {
    final requestId = _requestId;
    final message = _message;
    return CoachHistory.fromJson(
      coachHistoryJson(
        turns: requestId == null || message == null || _responding
            ? const []
            : [
                {
                  'request_id': requestId,
                  'message': message,
                  'response': coachResponseJson(
                    requestId: requestId,
                    reply: reply,
                  ),
                  'created_at': '2026-07-30T10:15:01Z',
                },
              ],
      ),
    );
  }

  @override
  Stream<CoachStreamEvent> respond({
    required String requestId,
    required String message,
  }) async* {
    _requestId = requestId;
    _message = message;
    _responding = true;
    yield CoachStartedEvent(requestId);
    yield const CoachActivityEvent('Checking relevant history …');
    await _completion.future;
    _responding = false;
    yield CoachCompletedEvent(
      CoachResponse.fromJson(
        coachResponseJson(requestId: requestId, reply: reply),
      ),
    );
  }

  @override
  Future<CoachHistoryDeleteResult> deleteHistory() async =>
      const CoachHistoryDeleteResult(true);

  @override
  void cancelActiveResponse() {
    cancelCalls++;
  }
}
