import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/theme/app_theme.dart';
import 'package:my_life_graph/core/widgets/app_surface.dart';
import 'package:my_life_graph/features/focus_protection/application/blocking_gateway.dart';
import 'package:my_life_graph/features/focus_protection/application/focus_protection_gateway.dart';
import 'package:my_life_graph/features/focus_protection/domain/blocking_plan.dart';
import 'package:my_life_graph/features/focus_protection/domain/focus_protection.dart';
import 'package:my_life_graph/features/focus_protection/presentation/pages/blocking_page.dart';

import 'blocking_plans_test.dart' show FakeBlockingGateway, snapshot;
import 'support/ui_catalog_capture.dart';

class _EnabledGateway extends UnsupportedFocusProtectionGateway {
  @override
  Future<FocusProtectionStatus> readStatus() async {
    final status = await super.readStatus();
    return FocusProtectionStatus(
      platformSupported: true,
      accessibilityEnabled: true,
      notificationPolicyGranted: false,
      lease: null,
      configuration: status.configuration.copyWith(
        enabled: true,
        blockSelectedApps: true,
      ),
    );
  }
}

class _StatusGateway extends FakeBlockingGateway {
  _StatusGateway({this.paused = false});
  final bool paused;
  @override
  Future<BlockingSnapshot> command(
    String name, [
    Map<String, Object>? args,
  ]) async => BlockingSnapshot({
    ...snapshot(locked: true),
    'plans': [
      {
        ...const BlockingPlan(
          id: 'active',
          name: 'Study',
          always: true,
          apps: {'example.app'},
        ).toMap(),
        'active': true,
      },
      {
        ...BlockingPlan(
          id: 'inactive',
          name: 'Night',
          enabled: !paused,
          windows: const [
            BlockingWindow(days: {1, 2, 3, 4, 5}, start: 1320, end: 420),
          ],
          apps: const {'other.app'},
        ).toMap(),
        'active': false,
      },
    ],
  });
}

class _PolishGateway extends FakeBlockingGateway {
  _PolishGateway({this.wait = 180});
  final int wait;
  @override
  Future<BlockingSnapshot> command(
    String name, [
    Map<String, Object>? args,
  ]) async => BlockingSnapshot({
    ...snapshot(),
    'strict': {'enabled': false, 'waitSeconds': wait, 'power': true},
    'plans': [
      const BlockingPlan(
        id: 'weekly',
        name: 'Study',
        apps: {'example.app'},
        windows: [
          BlockingWindow(days: {2, 1}, start: 1320, end: 420),
          BlockingWindow(days: {7, 3}, start: 600, end: 660),
        ],
      ).toMap(),
    ],
  });

  @override
  Future<Map> insights(int days) async => {
    'daily': [
      for (var i = 0; i < days; i++)
        {
          'dateEpochMs': DateTime(
            2026,
            10,
            3 - days + 1 + i,
          ).millisecondsSinceEpoch,
          'milliseconds': (i + 1) * 60000,
        },
    ],
    'apps': <Map>[],
  };
}

class _LongDurationGateway extends _PolishGateway {
  @override
  Future<Map> insights(int days) async => {
    'daily': [
      {
        'dateEpochMs': DateTime(2026, 10, 3).millisecondsSinceEpoch,
        'milliseconds': 2000 * 60000,
      },
    ],
    'apps': [
      {'label': 'Example browser', 'milliseconds': 2000 * 60000},
    ],
  };
}

Future<void> _open(
  WidgetTester tester, {
  int wait = 180,
  ThemeData? theme,
  double width = 390,
  double scale = 1,
  BlockingGateway? gateway,
  bool reduced = false,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 1000);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        blockingGatewayProvider.overrideWithValue(
          gateway ?? _PolishGateway(wait: wait),
        ),
        focusProtectionGatewayProvider.overrideWithValue(
          gateway is _StatusGateway
              ? _EnabledGateway()
              : UnsupportedFocusProtectionGateway(),
        ),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme ?? AppTheme.liquidGlass,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            alwaysUse24HourFormat: true,
            disableAnimations: reduced,
          ),
          child: child!,
        ),
        home: const Scaffold(body: BlockingPage()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final theme in [
    AppTheme.dark,
    AppTheme.light,
    AppTheme.space,
    AppTheme.liquidGlass,
  ]) {
    testWidgets(
      'long usage totals and app rows use readable units at 320px/200% ${theme.brightness}/${theme.colorScheme.primary}',
      (tester) async {
        await _open(
          tester,
          gateway: _LongDurationGateway(),
          theme: theme,
          width: 320,
          scale: 2,
        );
        await tester.tap(find.text('Insights').last);
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(find.text('Daily usage'), 150);
        expect(find.text('Total 1d 9h 20m'), findsOneWidget);
        await tester.scrollUntilVisible(find.text('Example browser'), 150);
        await tester.pumpAndSettle();
        expect(find.text('1d 9h 20m'), findsWidgets);
        expect(find.textContaining('2000m'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final (width, scale) in [(390.0, 1.0), (900.0, 1.0), (320.0, 2.0)]) {
    testWidgets('Customize actions share centered width at $width/$scale', (
      tester,
    ) async {
      await _open(tester, width: width, scale: scale);
      await tester.tap(find.text('Customize').last);
      await tester.pumpAndSettle();
      final returnButton = find.widgetWithText(
        OutlinedButton,
        'Return to MyLifeGraph',
      );
      final customizeButton = find.widgetWithText(FilledButton, 'Customize');
      await tester.scrollUntilVisible(customizeButton, 120);
      await tester.pumpAndSettle();
      final returnRect = tester.getRect(returnButton);
      final customizeRect = tester.getRect(customizeButton);
      expect(returnRect.width, closeTo(customizeRect.width, 0.1));
      expect(returnRect.center.dx, closeTo(width / 2, 0.1));
      expect(customizeRect.center.dx, closeTo(width / 2, 0.1));
      expect(returnRect.width, lessThanOrEqualTo(286));
      expect(returnRect.height, greaterThanOrEqualTo(48));
      expect(customizeRect.height, greaterThanOrEqualTo(48));
      expect(tester.widget<OutlinedButton>(returnButton).onPressed, isNull);
      expect(tester.takeException(), isNull);
    });
    testWidgets(
      'weekly detail is not repeated on compact cards at $width/$scale',
      (tester) async {
        await _open(tester, width: width, scale: scale);
        for (final label in [
          'Mo Tu · 22:00–07:00 (+1 day)',
          'We Su · 10:00–11:00',
        ]) {
          expect(find.text(label), findsNothing);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final (width, scale) in [(390.0, 1.0), (320.0, 2.0)]) {
    testWidgets('native active state is visibly distinct at $width/$scale', (
      tester,
    ) async {
      await _open(
        tester,
        gateway: _StatusGateway(),
        width: width,
        scale: scale,
      );
      await tester.scrollUntilVisible(
        find.text('Active'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('Active'), findsOneWidget);
      final active = tester.widget<AppSurface>(
        find
            .ancestor(of: find.text('Study'), matching: find.byType(AppSurface))
            .first,
      );
      expect(active.selected, isTrue);
      await tester.scrollUntilVisible(
        find.text('Night'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('Scheduled'), findsOneWidget);
      final inactive = tester.widget<AppSurface>(
        find
            .ancestor(of: find.text('Night'), matching: find.byType(AppSurface))
            .first,
      );
      expect(inactive.selected, isFalse);
      await Scrollable.ensureVisible(
        tester.element(find.byTooltip('Plan options').last),
        alignment: .5,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Plan options').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Details'));
      await tester.pumpAndSettle();
      expect(
        find.text('Mo Tu We Th Fr · 22:00–07:00 (+1 day)'),
        findsOneWidget,
      );
      expect(find.text('Device time'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'disabled native plan retains Paused rather than active styling',
    (tester) async {
      await _open(tester, gateway: _StatusGateway(paused: true));
      expect(find.text('Paused'), findsOneWidget);
      final paused = tester.widget<AppSurface>(
        find
            .ancestor(of: find.text('Night'), matching: find.byType(AppSurface))
            .first,
      );
      expect(paused.selected, isFalse);
    },
  );
  testWidgets('plan cards keep windows in details instead of the overview', (
    tester,
  ) async {
    await _open(tester);
    expect(find.text('Mo Tu · 22:00–07:00 (+1 day)'), findsNothing);
    expect(find.text('We Su · 10:00–11:00'), findsNothing);
    expect(find.text('Device time'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final (wait, label) in [
    (0, 'Immediate + Charger'),
    (10, '10s + Charger'),
    (60, '1m + Charger'),
    (180, '3m + Charger'),
    (185, '3m 5s + Charger'),
  ]) {
    testWidgets('Strict summary preserves $wait second wait', (tester) async {
      await _open(tester, wait: wait);
      await tester.tap(find.text('Strict').last);
      await tester.pumpAndSettle();
      expect(find.text(label), findsOneWidget);
      expect(find.text('Unlock method'), findsOneWidget);
      expect(find.text('Limits'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final (id, theme) in [
    ('dark', AppTheme.dark),
    ('light', AppTheme.light),
    ('space', AppTheme.space),
    ('glass', AppTheme.liquidGlass),
  ]) {
    testWidgets(
      'Blocking tab pill retains $id palette and selected semantics',
      (tester) async {
        await _open(tester, theme: theme);
        for (final label in ['Plans', 'Strict', 'Insights', 'Customize']) {
          await tester.tap(find.text(label).last);
          await tester.pumpAndSettle();
          final button = tester.widget<TextButton>(
            find.ancestor(
              of: find.text(label).last,
              matching: find.byType(TextButton),
            ),
          );
          expect(
            button.style!.backgroundColor!.resolve({}),
            theme.colorScheme.primaryContainer,
          );
          expect(
            tester
                .getSize(
                  find.ancestor(
                    of: find.text(label).last,
                    matching: find.byType(TextButton),
                  ),
                )
                .height,
            greaterThanOrEqualTo(44),
          );
          expect(
            find.ancestor(
              of: find.text(label).last,
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is Semantics && widget.properties.selected == true,
              ),
            ),
            findsOneWidget,
          );
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final scale in [1.0, 2.0]) {
    testWidgets('usage magnitudes and tabs stay readable at 320px/$scale', (
      tester,
    ) async {
      await _open(tester, width: 320, scale: scale);
      await tester.tap(find.text('Insights').last);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Daily usage'), 180);
      await tester.pumpAndSettle();
      expect(find.text('Total 28m'), findsOneWidget);
      for (var minute = 1; minute <= 7; minute++) {
        expect(
          find.textContaining(scale == 1 ? '${minute}m' : ': ${minute}m'),
          findsWidgets,
        );
      }
      await tester.scrollUntilVisible(find.text('Month'), -180);
      await tester.tap(find.text('Month'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Daily usage'), 180);
      await tester.pumpAndSettle();
      expect(find.text('Total 7h 45m'), findsOneWidget);
      expect(find.text('Peak 30m'), findsOneWidget);
      // Dense month charts retain individual values in tooltips, not 30 labels.
      expect(find.byType(Tooltip), findsWidgets);
      expect(find.text('30m'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  if (captureUiCatalog) {
    testWidgets('approved blocking polish visual catalog', (tester) async {
      await loadCatalogFonts();
      await _open(tester);
      await captureCatalog(tester, 'blocking-polish-plans');
      for (final tab in ['Strict', 'Insights', 'Customize']) {
        await tester.tap(find.text(tab).last);
        await tester.pumpAndSettle();
        await captureCatalog(tester, 'blocking-polish-${tab.toLowerCase()}');
      }
      await tester.pumpWidget(const SizedBox());
      await _open(tester, gateway: _StatusGateway(), reduced: true);
      await captureCatalog(tester, 'blocking-active-inactive');
      await tester.tap(find.text('Strict').last);
      await tester.pumpAndSettle();
      await captureCatalog(tester, 'blocking-strict-active');
    });
  }
}
