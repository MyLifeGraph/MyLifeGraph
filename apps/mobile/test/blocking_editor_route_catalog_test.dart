// Local screenshot harness only. All device state is synthetic; no native writes.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/theme/app_theme.dart';
import 'package:my_life_graph/core/widgets/app_backdrop.dart';
import 'package:my_life_graph/features/focus_protection/application/blocking_gateway.dart';
import 'package:my_life_graph/features/focus_protection/application/focus_protection_gateway.dart';
import 'package:my_life_graph/features/focus_protection/domain/blocking_plan.dart';
import 'package:my_life_graph/features/focus_protection/domain/focus_protection.dart';
import 'package:my_life_graph/features/focus_protection/presentation/pages/blocking_page.dart';
import 'support/ui_catalog_capture.dart';

class VisualDevice extends UnsupportedFocusProtectionGateway {
  @override
  Future<FocusProtectionStatus> readStatus() async {
    final s = await super.readStatus();
    return FocusProtectionStatus(
      platformSupported: true,
      accessibilityEnabled: true,
      notificationPolicyGranted: true,
      lease: null,
      configuration: s.configuration.copyWith(
        enabled: true,
        blockSelectedApps: true,
        consentVersions: {
          focusProtectionAppCatalogConsent: focusProtectionConsentVersion,
        },
      ),
    );
  }
}

class VisualBlocking extends BlockingGateway {
  VisualBlocking({this.allowed = true});
  final bool allowed;
  @override
  Future<BlockingSnapshot> command(
    String name, [
    Map<String, Object>? args,
  ]) async => BlockingSnapshot({
    'revision': 7,
    'plans': [
      {
        ...const BlockingPlan(
          id: 'study',
          name: 'Study',
          icon: 'study',
          apps: {'instagram', 'youtube'},
          sites: {'instagram.com'},
          focus: true,
          windows: [
            BlockingWindow(days: {1, 2, 3, 4, 5}, start: 540, end: 1080),
          ],
          budget: 45,
        ).toMap(),
        'tracking': true,
        'usedMs': 180000,
      },
      {
        ...const BlockingPlan(
          id: 'night',
          name: 'Night',
          icon: 'sleep',
          apps: {'instagram'},
          windows: [
            BlockingWindow(days: {1, 2, 3, 4, 5, 6, 7}, start: 1320, end: 420),
          ],
        ).toMap(),
      },
    ],
    'strict': {
      'enabled': false,
      'waitSeconds': 180,
      'power': true,
      'wifi': false,
      'nfc': true,
      'stayOnScreen': false,
    },
    'custom': <String, Object>{},
    'locked': false,
    'remainingMs': 0,
    'websiteConsent': allowed,
    'usageConsent': allowed,
    'usageGranted': allowed,
    'nfcAvailable': true,
    'nfcEnrolled': true,
    'nfcTags': [
      {'id': 'main', 'name': 'Main chip'},
      {'id': 'backup', 'name': 'Backup chip'},
    ],
    'wifiReady': true,
    'attemptsToday': 3,
    'attemptsTotal': 18,
  });
  @override
  Future<List<Map>> catalog() async => [
    {
      'packageName': 'instagram',
      'label': 'Instagram',
      'category': 'Social media',
    },
    {'packageName': 'youtube', 'label': 'YouTube', 'category': 'Video'},
    {'packageName': 'calculator', 'label': 'Calculator', 'category': 'Other'},
    {'packageName': 'game', 'label': 'Puzzle', 'category': 'Games'},
    {'packageName': 'notes', 'label': 'Notes', 'category': 'Other'},
  ];
  @override
  Future<Map> insights(int days) async => {
    'daily': [
      for (var i = 0; i < days; i++)
        {
          'dateEpochMs': DateTime(
            2026,
            10,
            20 - days + i + 1,
          ).millisecondsSinceEpoch,
          'milliseconds': (i % 4 + 1) * 900000,
        },
    ],
    'apps': [
      {'label': 'Instagram', 'milliseconds': 4500000},
      {'label': 'YouTube', 'milliseconds': 1800000},
    ],
  };
  @override
  Future<void> open(String name) async {}
}

Future<void> open(WidgetTester t, {bool allowed = true}) async {
  await loadCatalogFonts();
  t.view.devicePixelRatio = 1;
  t.view.physicalSize = const Size(390, 844);
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        blockingGatewayProvider.overrideWithValue(
          VisualBlocking(allowed: allowed),
        ),
        focusProtectionGatewayProvider.overrideWithValue(VisualDevice()),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.liquidGlass,
        // The production shell puts a Material/Scaffold above its child Navigator.
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: AppBackdrop(child: Scaffold(body: child!)),
        ),
        home: const Scaffold(body: BlockingPage()),
      ),
    ),
  );
  await t.pumpAndSettle();
}

Future<void> shot(WidgetTester t, String name) async {
  await t.pump(const Duration(milliseconds: 500));
  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile(
      '../../../.tools/ui-catalog/blocking-editor-sections-20261020/after-$name.png',
    ),
  );
}

Future<void> tap(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.pump(const Duration(milliseconds: 500));
  await t.tap(f);
  await t.pump(const Duration(milliseconds: 500));
}

Future<void> back(WidgetTester t) async {
  await t.binding.handlePopRoute();
  await t.pumpAndSettle();
}

Future<void> reveal(WidgetTester t, Finder f) async {
  final outer = find
      .descendant(
        of: find.byKey(const ValueKey('blocking-editor-scroll')),
        matching: find.byType(Scrollable),
      )
      .first;
  await t.scrollUntilVisible(f, 160, scrollable: outer);
  await t.pumpAndSettle();
}

void main() {
  if (!captureUiCatalog) return;
  testWidgets(
    'real Blocking route section screenshots',
    (t) async {
      await open(t);
      await tap(t, find.text('Study').first);
      await shot(t, 'plan-rules');
      await tap(t, find.byTooltip('Plan icon'));
      await shot(t, 'plan-icons');
      await tap(t, find.text('Cancel'));
      await tap(t, find.byKey(const ValueKey('blocking-editor-tab-1')));
      await shot(t, 'plan-apps');
      await tap(t, find.byKey(const ValueKey('blocking-app-calculator')));
      await shot(t, 'plan-apps-selected');
      await tap(t, find.byKey(const ValueKey('blocking-editor-tab-2')));
      await shot(t, 'plan-websites');
      await tap(t, find.byKey(const ValueKey('blocking-site-reddit.com')));
      await shot(t, 'plan-websites-selected');
      await tap(t, find.byTooltip('Close'));
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
      await open(t);
      await tap(t, find.text('Customize').last);
      await t.pumpAndSettle();
      await tap(t, find.widgetWithText(FilledButton, 'Customize'));
      await shot(t, 'custom-content');
      await tap(t, find.byKey(const ValueKey('blocking-editor-tab-1')));
      await shot(t, 'custom-style');
      await tap(t, find.byKey(const ValueKey('blocking-editor-tab-2')));
      await tap(t, find.widgetWithText(ChoiceChip, '10s'));
      await shot(t, 'custom-delay');
      await tap(t, find.byTooltip('Expand preview'));
      await shot(t, 'custom-expanded-preview');
      expect(t.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
}
