import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/composition/widgets/app_header_actions.dart';
import 'package:my_life_graph/core/capabilities/app_surface_capabilities.dart';
import 'package:my_life_graph/core/theme/app_theme.dart';
import 'package:my_life_graph/features/focus_protection/application/blocking_gateway.dart';
import 'package:my_life_graph/features/focus_protection/application/focus_protection_gateway.dart';
import 'package:my_life_graph/features/focus_protection/domain/blocking_plan.dart';
import 'package:my_life_graph/features/focus_protection/presentation/pages/blocking_page.dart';
import 'support/ui_catalog_capture.dart';

Map<String, Object> snapshot({bool locked = false}) => {
  'revision': 3,
  'plans': [
    const BlockingPlan(
      id: 'one',
      name: 'Study',
      apps: {'example.app'},
      focus: true,
      windows: [
        BlockingWindow(days: {1, 2}, start: 1320, end: 420),
      ],
    ).toMap(),
  ],
  'strict': {'enabled': locked, 'waitSeconds': 180},
  'custom': <String, Object>{},
  'locked': locked,
  'remainingMs': 180000,
  'websiteConsent': true,
  'usageGranted': true,
  'usageConsent': true,
  'nfcAvailable': false,
  'nfcEnrolled': false,
  'wifiReady': false,
  'attemptsToday': 3,
  'attemptsTotal': 12,
};

class FakeBlockingGateway extends BlockingGateway {
  FakeBlockingGateway({this.locked = false, this.failFirstSave = false});
  final bool locked;
  final bool failFirstSave;
  int saveAttempts = 0;
  Map<String, Object> custom = {};
  final calls = <String>[];
  @override
  Future<BlockingSnapshot> command(
    String name, [
    Map<String, Object>? args,
  ]) async {
    calls.add(name);
    if (name == 'save') {
      if (++saveAttempts == 1 && failFirstSave) {
        throw StateError('Save failed. Try again.');
      }
      custom = Map<String, Object>.from(args!['custom'] as Map);
    }
    return BlockingSnapshot({...snapshot(locked: locked), 'custom': custom});
  }

  @override
  Future<Map> insights(int days) async => {
    'daily': [
      {'dateEpochMs': 1790899200000, 'milliseconds': 300000},
      {'dateEpochMs': 1790985600000, 'milliseconds': 600000},
    ],
    'apps': [
      {'label': 'Example', 'milliseconds': 600000},
    ],
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('non-Android header never loads Android account capabilities', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          focusProtectionPlatformSupportedProvider.overrideWithValue(false),
          appSurfaceCapabilitiesProvider.overrideWith(
            (ref) =>
                throw StateError('Must not read Android capabilities here'),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const Scaffold(body: AppHeaderActions()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('App blocking'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('blocking shield is limited to eligible Android accounts', (
    tester,
  ) async {
    for (final eligible in [true, false]) {
      await tester.pumpWidget(
        ProviderScope(
          key: ValueKey(eligible),
          overrides: [
            focusProtectionPlatformSupportedProvider.overrideWithValue(true),
            appSurfaceCapabilitiesProvider.overrideWithValue(
              AppSurfaceCapabilities(
                isLocalDemo: !eligible,
                canUseSyncedHabits: eligible,
                canUseDeviceFocusProtection: eligible,
              ),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.dark,
            home: const Scaffold(body: AppHeaderActions()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('header-island-toggle')));
      await tester.pumpAndSettle();
      expect(
        find.byTooltip('App blocking'),
        eligible ? findsOneWidget : findsNothing,
      );
      expect(tester.takeException(), isNull);
    }
  });
  test(
    'native gateway rejects incompatible contracts and preserves save revision',
    () async {
      const channel = MethodChannel('test/blocking-v2');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final gateway = BlockingGateway(channel: channel);
      var version = 'old';
      MethodCall? received;
      messenger.setMockMethodCallHandler(channel, (call) async {
        received = call;
        return {...snapshot(), 'contractVersion': version};
      });
      await expectLater(gateway.command('status'), throwsFormatException);
      version = blockingPlansContractVersion;
      final value = await gateway.command('save', {
        'revision': 3,
        'plans': snapshot()['plans']!,
        'custom': <String, Object>{},
      });
      expect(value.revision, 3);
      expect(received!.method, 'save');
      expect((received!.arguments as Map)['revision'], 3);
      expect(value.usageConsent, isTrue);
    },
  );
  if (captureUiCatalog) {
    testWidgets('blocking visual catalog', (tester) async {
      await loadCatalogFonts();
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final width in [390.0, 900.0]) {
        tester.view.physicalSize = Size(width, 844);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              blockingGatewayProvider.overrideWithValue(FakeBlockingGateway()),
              focusProtectionGatewayProvider.overrideWithValue(
                UnsupportedFocusProtectionGateway(),
              ),
            ],
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: AppTheme.liquidGlass,
              home: const Scaffold(body: BlockingPage()),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await captureCatalog(tester, 'blocking-plans-${width.toInt()}');
        for (final tab in ['Strict', 'Insights', 'Customize']) {
          await tester.tap(find.text(tab).last);
          await tester.pumpAndSettle();
          await captureCatalog(
            tester,
            'blocking-${tab.toLowerCase()}-${width.toInt()}',
          );
        }
        await tester.pumpWidget(const SizedBox());
      }
    });
  }
  test(
    'plan roundtrip retains combinations and never writes transient status',
    () {
      final map = snapshot()['plans'] as List;
      final p = BlockingPlan.fromMap({
        ...map.first as Map,
        'active': true,
        'usedMs': 234,
      });
      expect(p.focus, isTrue);
      expect(p.windows.single.days, {1, 2});
      expect(p.toMap().containsKey('active'), isFalse);
      expect(p.toMap().containsKey('usedMs'), isFalse);
      expect(p.copyWith(enabled: false).windows.single.end, 420);
      expect(p.copyWith(enabled: false).sites, p.sites);
    },
  );
  for (final width in [320.0, 390.0, 900.0]) {
    testWidgets('four blocking tabs render without overflow at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final gateway = FakeBlockingGateway();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            blockingGatewayProvider.overrideWithValue(gateway),
            focusProtectionGatewayProvider.overrideWithValue(
              UnsupportedFocusProtectionGateway(),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.liquidGlass,
            home: const Scaffold(body: BlockingPage()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Quick Block'), findsOneWidget);
      expect(find.text('Study'), findsOneWidget);
      for (final tab in ['Strict', 'Insights', 'Customize', 'Plans']) {
        await tester.tap(find.text(tab).last);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: tab);
      }
    });
  }
  testWidgets('strict disables plan editing and exposes real unlock gate', (
    tester,
  ) async {
    final gateway = FakeBlockingGateway(locked: true);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          blockingGatewayProvider.overrideWithValue(gateway),
          focusProtectionGatewayProvider.overrideWithValue(
            UnsupportedFocusProtectionGateway(),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const Scaffold(body: BlockingPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final start = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Start').first,
    );
    expect(start.onPressed, isNull);
    await tester.tap(find.text('Strict').last);
    await tester.pump();
    expect(find.text('Unblock'), findsOneWidget);
    expect(find.text('Unlock'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'editing keeps Focus, overnight windows, budget and website targets',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      BlockingPlan? saved;
      const original = BlockingPlan(
        id: 'edit',
        name: 'Study',
        apps: {'game.app'},
        sites: {'x.com'},
        focus: true,
        budget: 45,
        windows: [
          BlockingWindow(days: {1, 2}, start: 1320, end: 420),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.liquidGlass,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  saved = await showModalBottomSheet<BlockingPlan>(
                    context: context,
                    isScrollControlled: true,
                    useSafeArea: true,
                    builder: (_) => const BlockingPlanEditor(
                      plan: original,
                      catalog: [
                        {
                          'packageName': 'game.app',
                          'label': 'Game',
                          'category': 'Games',
                        },
                      ],
                      usageGranted: true,
                      websiteAllowed: true,
                    ),
                  );
                },
                child: const Text('Edit'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.widgetWithText(SwitchListTile, 'Always'));
      await tester.tap(find.widgetWithText(SwitchListTile, 'Always'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.widgetWithText(FilledButton, 'Save'),
        350,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Save').last);
      await tester.pumpAndSettle();
      expect(saved!.id, original.id);
      expect(saved!.focus, isTrue);
      expect(saved!.always, isTrue);
      expect(saved!.budget, 45);
      expect(saved!.windows.single.end, 420);
      expect(saved!.sites, {'x.com'});
      expect(saved!.apps, {'game.app'});
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('blocking tabs remain scrollable at 200 percent text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          blockingGatewayProvider.overrideWithValue(FakeBlockingGateway()),
          focusProtectionGatewayProvider.overrideWithValue(
            UnsupportedFocusProtectionGateway(),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.liquidGlass,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: const Scaffold(body: BlockingPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final tab in ['Strict', 'Insights', 'Customize', 'Plans']) {
      await tester.tap(find.text(tab).last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: tab);
    }
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('failed native save keeps the editable draft for retry', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    var attempts = 0;
    BlockingPlan? saved;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.liquidGlass,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              child: const Text('Edit'),
              onPressed: () async {
                saved = await showModalBottomSheet<BlockingPlan>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => BlockingPlanEditor(
                    plan: const BlockingPlan(
                      id: 'retry',
                      name: 'Study',
                      apps: {'game.app'},
                      focus: true,
                    ),
                    catalog: const [],
                    usageGranted: true,
                    websiteAllowed: true,
                    onSave: (plan) async {
                      attempts++;
                      if (attempts == 1) {
                        throw StateError('Save failed. Try again.');
                      }
                    },
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'My edited plan');
    tester.view.viewInsets = const FakeViewPadding(bottom: 250);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    tester.view.resetViewInsets();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.widgetWithText(FilledButton, 'Save'),
      350,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save').last);
    await tester.pumpAndSettle();
    expect(find.text('Save failed. Try again.'), findsOneWidget);
    expect(find.byType(BlockingPlanEditor), findsOneWidget);
    expect(saved, isNull);
    await tester.scrollUntilVisible(
      find.widgetWithText(FilledButton, 'Save'),
      150,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save').last);
    await tester.pumpAndSettle();
    expect(saved!.name, 'My edited plan');
    expect(attempts, 2);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Customize retains values after failed save and retries', (
    tester,
  ) async {
    final gateway = FakeBlockingGateway(failFirstSave: true);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          blockingGatewayProvider.overrideWithValue(gateway),
          focusProtectionGatewayProvider.overrideWithValue(
            UnsupportedFocusProtectionGateway(),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.liquidGlass,
          home: const Scaffold(body: BlockingPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Customize').last);
    await tester.pumpAndSettle();
    expect(
      tester
          .widgetList<Icon>(find.byType(Icon))
          .where(
            (icon) => icon.icon == blockingIcon('shield') && icon.size == 64,
          ),
      hasLength(1),
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Customize'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<BottomSheet>(find.byType(BottomSheet)).enableDrag,
      isFalse,
    );
    await tester.enterText(find.byType(TextField).first, 'Stay with your goal');
    final save = find.widgetWithText(FilledButton, 'Save');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.text('Block screen'), findsOneWidget);
    expect(find.text('Stay with your goal'), findsOneWidget);
    expect(gateway.saveAttempts, 1);
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.text('Block screen'), findsNothing);
    expect(gateway.custom['title'], 'Stay with your goal');
    expect(gateway.saveAttempts, 2);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 400));
  });
  testWidgets('Customize persists one-second return delay on reopen', (
    tester,
  ) async {
    final gateway = FakeBlockingGateway();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          blockingGatewayProvider.overrideWithValue(gateway),
          focusProtectionGatewayProvider.overrideWithValue(
            UnsupportedFocusProtectionGateway(),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.liquidGlass,
          home: const Scaffold(body: BlockingPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Customize').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Customize'));
    await tester.pumpAndSettle();
    final delay = find.byType(DropdownButtonFormField<int>);
    await tester.ensureVisible(delay);
    await tester.tap(delay);
    await tester.pumpAndSettle();
    await tester.tap(find.text('1s').last);
    await tester.pumpAndSettle();
    final save = find.widgetWithText(FilledButton, 'Save');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(gateway.custom['waitSeconds'], 1);
    await tester.tap(find.widgetWithText(FilledButton, 'Customize'));
    await tester.pumpAndSettle();
    expect(tester.widget<DropdownButtonFormField<int>>(delay).initialValue, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
  for (final (tone, label, icon) in [
    ('glass', 'Liquid Glass', 'shield'),
    ('dark', 'Dark', 'work'),
    ('light', 'Light', 'games'),
    ('space', 'Space', 'sleep'),
  ]) {
    testWidgets('Customize saves and reopens $tone background and $icon icon', (
      tester,
    ) async {
      final gateway = FakeBlockingGateway();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            blockingGatewayProvider.overrideWithValue(gateway),
            focusProtectionGatewayProvider.overrideWithValue(
              UnsupportedFocusProtectionGateway(),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.liquidGlass,
            home: const Scaffold(body: BlockingPage()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Customize').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Customize'));
      await tester.pumpAndSettle();
      final fields = find.byType(DropdownButtonFormField<String>);
      await tester.ensureVisible(fields.first);
      await tester.tap(fields.first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(icon).last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(fields.last);
      await tester.tap(fields.last);
      await tester.pumpAndSettle();
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
      final save = find.widgetWithText(FilledButton, 'Save');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(gateway.custom['tone'], tone);
      expect(gateway.custom['icon'], icon);
      await tester.tap(find.widgetWithText(FilledButton, 'Customize'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<DropdownButtonFormField<String>>(fields.first)
            .initialValue,
        icon,
      );
      expect(
        tester
            .widget<DropdownButtonFormField<String>>(fields.last)
            .initialValue,
        tone,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  }
  test('offline page cannot access network or rewrite the browser', () {
    final page = File(
      'android/app/src/main/kotlin/com/mylifegraph/app/LocalBlockPageActivity.kt',
    ).readAsStringSync();
    expect(page, contains('settings.javaScriptEnabled = false'));
    expect(page, contains('settings.blockNetworkLoads = true'));
    expect(page, contains('settings.allowFileAccess = false'));
    expect(page, contains('TextUtils.htmlEncode'));
    expect(page, contains('Intent.CATEGORY_HOME'));
    final native = File(
      'android/app/src/main/kotlin/com/mylifegraph/app/BlockingPlans.kt',
    ).readAsStringSync();
    expect(native, contains('Settings.Global.BOOT_COUNT'));
    expect(native, contains('SystemClock.elapsedRealtime()'));
    expect(native, contains('Settings changed. Reload and try again.'));
    expect(native, contains('Start unlocking first.'));
    final service = File(
      'android/app/src/main/kotlin/com/mylifegraph/app/FocusBlockAccessibilityService.kt',
    ).readAsStringSync();
    expect(
      service,
      contains(
        'if (!plans.websiteObservationEnabled()) { currentHost = null; return }',
      ),
    );
  });
}
