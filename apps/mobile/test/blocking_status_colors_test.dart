import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/theme/app_theme.dart';
import 'package:my_life_graph/core/theme/app_visual_tokens.dart';
import 'package:my_life_graph/core/widgets/app_surface.dart';
import 'package:my_life_graph/features/focus_protection/application/blocking_gateway.dart';
import 'package:my_life_graph/features/focus_protection/application/focus_protection_gateway.dart';
import 'package:my_life_graph/features/focus_protection/domain/blocking_plan.dart';
import 'package:my_life_graph/features/focus_protection/domain/focus_protection.dart';
import 'package:my_life_graph/features/focus_protection/presentation/pages/blocking_page.dart';

import 'blocking_plans_test.dart' show snapshot;

class _Ready extends UnsupportedFocusProtectionGateway {
  @override
  Future<FocusProtectionStatus> readStatus() async {
    final s = await super.readStatus();
    return FocusProtectionStatus(
      platformSupported: true,
      accessibilityEnabled: true,
      notificationPolicyGranted: false,
      lease: null,
      configuration: s.configuration.copyWith(
        enabled: true,
        blockSelectedApps: true,
      ),
    );
  }
}

Map<String, Object> _budget({
  bool active = false,
  bool tracking = true,
  bool enabled = true,
  int used = 41000,
  int pausedUntil = 0,
  bool weekly = false,
}) => {
  ...BlockingPlan(
    id: 'games',
    name: 'Games',
    icon: 'games',
    apps: const {'example.game'},
    budget: 45,
    enabled: enabled,
    pausedUntil: pausedUntil,
    windows: weekly ? const [BlockingWindow()] : const [],
  ).toMap(),
  'active': active,
  'tracking': tracking,
  'usedMs': used,
};

Future<void> _open(
  WidgetTester tester, {
  required ThemeData theme,
  double scale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 1000);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        // Use the production MethodChannel decoder, not a prebuilt snapshot.
        blockingGatewayProvider.overrideWithValue(const BlockingGateway()),
        focusProtectionGatewayProvider.overrideWithValue(_Ready()),
      ],
      child: MaterialApp(
        theme: theme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: const Scaffold(body: BlockingPage()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

AppSurface _card(WidgetTester tester) => tester.widget<AppSurface>(
  find
      .ancestor(of: find.text('Games'), matching: find.byType(AppSurface))
      .first,
);

void main() {
  const channel = MethodChannel('com.mylifegraph.app/blocking_v2');
  TestWidgetsFlutterBinding.ensureInitialized();
  var plan = _budget();
  var access = true;
  var reads = 0;
  var failNext = false;
  Completer<Map<String, Object>>? delayed;
  setUp(() {
    plan = _budget();
    access = true;
    reads = 0;
    failNext = false;
    delayed = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method != 'status') {
            throw StateError('Unexpected write: ${call.method}');
          }
          reads++;
          if (failNext) {
            failNext = false;
            throw PlatformException(
              code: 'temporary',
              message: 'QA status unavailable',
            );
          }
          if (delayed case final pending?) {
            return pending.future;
          }
          return {
            ...snapshot(),
            'contractVersion': blockingPlansContractVersion,
            'plans': [plan],
            'usageGranted': access,
          };
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  for (final (name, theme) in [
    ('dark', AppTheme.dark),
    ('light', AppTheme.light),
    ('space', AppTheme.space),
    ('glass', AppTheme.liquidGlass),
  ]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('native tracking and exhausted transition $name $scale', (
        tester,
      ) async {
        await _open(tester, theme: theme, scale: scale);
        final tokens = Theme.of(
          tester.element(find.text('Games')),
        ).extension<AppVisualTokens>()!;
        expect(find.text('Tracking'), findsOneWidget);
        expect(find.text('Scheduled'), findsNothing);
        expect(find.text('All day · 44m 19s left'), findsOneWidget);
        expect(_card(tester).statusOutline, tokens.success);
        expect(tester.widget<Icon>(find.byIcon(blockingIcon('games'))).color,
          tokens.success);
        expect(
          tester.widget<AppStatusPill>(find.byType(AppStatusPill).first).tone,
          AppStatusTone.success,
        );
        final before = tester.getSize(find.byType(AppStatusPill).first);
        plan = _budget(active: true, tracking: false, used: 45 * 60000);
        await tester.pump(const Duration(seconds: 1));
        await tester.pumpAndSettle();
        expect(reads, greaterThan(1));
        expect(find.text('Active'), findsOneWidget);
        expect(find.text('All day · 0m 0s left'), findsOneWidget);
        expect(_card(tester).statusOutline, tokens.danger);
        expect(tester.widget<Icon>(find.byIcon(blockingIcon('games'))).color,
          tokens.danger);
        expect(
          tester.widget<AppStatusPill>(find.byType(AppStatusPill).first).tone,
          AppStatusTone.danger,
        );
        // Existing longer labels may wrap at enlarged text. Color must not
        // add geometry; do not require different labels to have equal height.
        if (scale == 1) {
          expect(
            tester.getSize(find.byType(AppStatusPill).first).height,
            before.height,
          );
        }
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets(
    'remaining minutes never invent native tracking or bypass denied usage',
    (tester) async {
      plan = _budget(tracking: false);
      await _open(tester, theme: AppTheme.liquidGlass);
      expect(find.text('Scheduled'), findsOneWidget);
      expect(_card(tester).statusOutline, isNull);
      access = false;
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.text('Usage unavailable'), findsOneWidget);
      expect(find.textContaining('44m'), findsNothing);
      expect(_card(tester).statusOutline, isNull);
    },
  );

  testWidgets('blocking OR rule wins over simultaneously available budget', (
    tester,
  ) async {
    plan = _budget(active: true, tracking: true, weekly: true);
    await _open(tester, theme: AppTheme.liquidGlass);
    final tokens = Theme.of(
      tester.element(find.text('Games')),
    ).extension<AppVisualTokens>()!;
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('Tracking'), findsNothing);
    expect(_card(tester).statusOutline, tokens.danger);
    expect(find.textContaining('left'), findsNothing);
  });

  testWidgets(
    'transient status failure retains tracking then recovers to blocking',
    (tester) async {
      await _open(tester, theme: AppTheme.liquidGlass);
      failNext = true;
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.textContaining('QA status unavailable'), findsOneWidget);
      expect(find.text('Tracking'), findsOneWidget);
      expect(
        tester.widget<AppStatusPill>(find.byType(AppStatusPill).first).tone,
        AppStatusTone.success,
      );
      plan = _budget(active: true, tracking: false, used: 45 * 60000);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.textContaining('QA status unavailable'), findsNothing);
      expect(find.text('Active'), findsOneWidget);
      expect(
        tester.widget<AppStatusPill>(find.byType(AppStatusPill).first).tone,
        AppStatusTone.danger,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('late tracking reply cannot replace a newer blocking refresh', (
    tester,
  ) async {
    await _open(tester, theme: AppTheme.liquidGlass);
    final stale = Completer<Map<String, Object>>();
    delayed = stale;
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    delayed = null;
    plan = _budget(active: true, tracking: false, used: 45 * 60000);
    unawaited(
      tester
          .widget<RefreshIndicator>(find.byType(RefreshIndicator))
          .onRefresh(),
    );
    await tester.pumpAndSettle();
    expect(find.text('Active'), findsOneWidget);
    stale.complete({
      ...snapshot(),
      'contractVersion': blockingPlansContractVersion,
      'plans': [_budget()],
      'usageGranted': true,
    });
    await tester.pumpAndSettle();
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('Tracking'), findsNothing);
    expect(
      tester.widget<AppStatusPill>(find.byType(AppStatusPill).first).tone,
      AppStatusTone.danger,
    );
    expect(tester.takeException(), isNull);
  });

  for (final temporary in [false, true]) {
    testWidgets('native paused budget stays neutral temporary=$temporary', (
      tester,
    ) async {
      plan = _budget(
        tracking: false,
        enabled: temporary,
        pausedUntil: temporary
            ? DateTime.now()
                  .add(const Duration(hours: 1))
                  .millisecondsSinceEpoch
            : 0,
      );
      await _open(tester, theme: AppTheme.liquidGlass);
      expect(find.text('Paused'), findsOneWidget);
      expect(find.text('Tracking'), findsNothing);
      expect(_card(tester).statusOutline, isNull);
    });
  }
}
