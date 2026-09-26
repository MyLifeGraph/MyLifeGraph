import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:my_life_graph/composition/widgets/app_update_host.dart';
import 'package:my_life_graph/composition/widgets/app_updates_entry.dart';
import 'package:my_life_graph/core/theme/app_theme.dart';
import 'package:my_life_graph/features/app_updates/application/app_updates.dart';
import 'package:my_life_graph/features/app_updates/data/github_app_releases.dart';
import 'package:my_life_graph/features/app_updates/presentation/update_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_updates_test.dart' as fixtures;

AppUpdatesController controller({bool fail = false}) => AppUpdatesController(
  supported: true,
  readInstalled: () async => fixtures.installed,
  releases: fail
      ? GitHubAppReleases(read: (_) async => throw StateError('offline'))
      : fixtures.source(),
);

Widget app(
  AppUpdatesController state, {
  bool allowPrompt = true,
  bool supported = true,
}) => ProviderScope(
  overrides: [
    appUpdatesSupportedProvider.overrideWithValue(supported),
    appUpdatesProvider.overrideWith((_) => state),
  ],
  child: MaterialApp(
    theme: AppTheme.dark,
    home: Scaffold(
      body: AppUpdateHost(
        allowPrompt: allowPrompt,
        child: const AppUpdatesEntry(),
      ),
    ),
  ),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('startup notice works inside the real nested-router pattern', (
    tester,
  ) async {
    final state = controller();
    final router = GoRouter(
      initialLocation: '/dashboard',
      routes: [
        ShellRoute(
          builder: (context, route, child) =>
              AppUpdateHost(allowPrompt: true, child: child),
          routes: [
            GoRoute(
              path: '/dashboard',
              builder: (_, _) => const Scaffold(body: Text('Today')),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appUpdatesSupportedProvider.overrideWithValue(true),
          appUpdatesProvider.overrideWith((_) => state),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AppUpdateDialog), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
  });

  testWidgets(
    'startup prompts once; closing survives app recreation; settings still offers download',
    (tester) async {
      await tester.pumpWidget(app(controller()));
      await tester.pumpAndSettle();
      expect(find.byType(AppUpdateDialog), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(app(controller()));
      await tester.pumpAndSettle();
      expect(find.byType(AppUpdateDialog), findsNothing);
      await tester.tap(find.text('Updates'));
      await tester.pumpAndSettle();
      expect(find.text('Download'), findsOneWidget);
      expect(find.textContaining('Installed:'), findsOneWidget);
    },
  );

  testWidgets('newer build prompts once after older dismissal', (tester) async {
    SharedPreferences.setMockInitialValues({
      AppUpdatesController.noticeKey: 109,
    });
    await tester.pumpWidget(app(controller()));
    await tester.pumpAndSettle();
    expect(find.byType(AppUpdateDialog), findsOneWidget);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.byType(AppUpdateDialog), findsNothing);
    expect(
      (await SharedPreferences.getInstance()).getInt(
        AppUpdatesController.noticeKey,
      ),
      110,
    );
  });

  testWidgets(
    'errors do not interrupt startup; manual check shows honest failure',
    (tester) async {
      await tester.pumpWidget(app(controller(fail: true)));
      await tester.pumpAndSettle();
      expect(find.byType(AppUpdateDialog), findsNothing);
      await tester.tap(find.text('Updates'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Check'));
      await tester.pumpAndSettle();
      expect(find.text('Could not check. Try again.'), findsOneWidget);
      expect(find.text('Up to date'), findsNothing);
      expect(find.text('Download'), findsNothing);
    },
  );

  testWidgets('form defers prompt until a root page is visible', (
    tester,
  ) async {
    final state = controller();
    await tester.pumpWidget(app(state, allowPrompt: false));
    await tester.pumpAndSettle();
    expect(find.byType(AppUpdateDialog), findsNothing);
    expect(
      (await SharedPreferences.getInstance()).containsKey(
        AppUpdatesController.noticeKey,
      ),
      isFalse,
    );
    await tester.pumpWidget(app(state));
    await tester.pumpAndSettle();
    expect(find.byType(AppUpdateDialog), findsOneWidget);
  });

  testWidgets('unsupported platform has no update entry or popup', (
    tester,
  ) async {
    await tester.pumpWidget(app(controller(), supported: false));
    await tester.pumpAndSettle();
    expect(find.text('Updates'), findsNothing);
    expect(find.byType(AppUpdateDialog), findsNothing);
  });

  testWidgets('manual download opens external launcher directly', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      AppUpdatesController.noticeKey: 110,
    });
    const channel = MethodChannel('plugins.flutter.io/url_launcher');
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call);
      return true;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    await tester.pumpWidget(app(controller()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Updates'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Download'));
    await tester.pumpAndSettle();
    expect(calls, hasLength(1));
    expect(calls.single.arguments['useWebView'], isFalse);
    expect(
      calls.single.arguments['url'],
      contains('/MyLifeGraph/MyLifeGraph/releases/download/'),
    );
    expect(find.byType(AppUpdateDialog), findsNothing);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'update popup fits 320px at ${scale}x and handles launcher failure',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final update = (await fixtures.source().newest(fixtures.installed))!;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => AppUpdateDialog(
                      update: update,
                      open: (_) async => false,
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
        await tester.tap(find.text('Download now'));
        await tester.pumpAndSettle();
        expect(
          find.text('Could not open download. Try again.'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
