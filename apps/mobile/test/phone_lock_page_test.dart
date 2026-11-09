import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/theme/app_theme.dart';
import 'package:my_life_graph/core/widgets/app_backdrop.dart';
import 'package:my_life_graph/features/focus_protection/application/phone_lock_gateway.dart';
import 'package:my_life_graph/features/focus_protection/application/focus_protection_gateway.dart';
import 'package:my_life_graph/features/focus_protection/presentation/pages/focus_protection_settings_page.dart';
import 'package:my_life_graph/features/focus_protection/domain/phone_lock.dart';
import 'package:my_life_graph/features/focus_protection/presentation/pages/phone_lock_page.dart';
import 'support/ui_catalog_capture.dart';

class Device extends PhoneLockGateway {
  int writes = 0, controls = 0;
  bool ready = true, nfc = true, fail = false;
  bool? protection, accessibility, phoneAvailable;
  Completer<void>? controlGate;
  PhoneLockOptions? saved;
  PhoneLockStatus value = const PhoneLockStatus(
    active: false,
    id: '',
    mode: 'timer',
    ready: true,
    nfcAvailable: true,
    nfcEnrolled: true,
  );
  @override
  Future<PhoneLockStatus> status() async => value.active
      ? value
      : PhoneLockStatus(
          active: false,
          id: '',
          mode: 'timer',
          ready: ready,
          nfcAvailable: nfc,
          nfcEnrolled: nfc,
          protectionEnabled: protection,
          accessibilityEnabled: accessibility,
          phoneAvailable: phoneAvailable,
        );
  @override
  Future<PhoneLockStatus> start(
    PhoneLockOptions options,
    String requestId, {
    DateTime? focusEndsAt,
  }) async {
    writes++;
    saved = options;
    if (fail) throw StateError('persist failed');
    return value = PhoneLockStatus(
      active: true,
      id: requestId,
      mode: options.mode,
      ready: true,
      nfcAvailable: true,
      nfcEnrolled: true,
      remainingMs: 2700000,
    );
  }

  @override
  Future<void> control({bool scan = false}) async {
    controls++;
    await controlGate?.future;
  }

  @override
  Future<void> phone() async {}
}

Future<void> open(
  WidgetTester t,
  Device device, {
  PhoneLockLaunch? launch,
  double width = 390,
  double scale = 1,
  ThemeData? theme,
}) async {
  t.view.devicePixelRatio = 1;
  t.view.physicalSize = Size(width, 844);
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        phoneLockGatewayProvider.overrideWithValue(device),
        focusProtectionGatewayProvider.overrideWithValue(
          UnsupportedFocusProtectionGateway(),
        ),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme ?? AppTheme.liquidGlass,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            disableAnimations: true,
          ),
          child: AppBackdrop(child: child!),
        ),
        home: Scaffold(body: PhoneLockPage(launch: launch)),
      ),
    ),
  );
  await t.pumpAndSettle();
}

Future<void> tap(WidgetTester t, String value) async {
  final f = find.text(value).last;
  await t.ensureVisible(f);
  await t.tap(f);
  await t.pumpAndSettle();
}

void main() {
  for (final linked in [false, true]) {
    testWidgets(
      'unready ${linked ? 'Focus' : 'manual'} lock opens setup and rechecks on return',
      (t) async {
        final d = Device()..ready = false;
        await open(
          t,
          d,
          launch: linked ? const PhoneLockLaunch(focusMinutes: 50) : null,
        );
        await tap(t, 'Permissions & limits');
        expect(find.byType(FocusProtectionSettingsPage), findsOneWidget);
        expect(d.writes, 0);
        d.ready = true;
        Navigator.of(t.element(find.byType(FocusProtectionSettingsPage))).pop();
        await t.pumpAndSettle();
        final label = linked ? 'Use with Focus' : 'Review lock';
        expect(
          t
              .widget<FilledButton>(find.widgetWithText(FilledButton, label))
              .onPressed,
          isNotNull,
        );
        await tap(t, label);
        expect(find.text('Ready to lock?'), findsOneWidget);
        expect(d.writes, 0);
      },
    );
  }
  testWidgets(
    'pull refresh rechecks inactive readiness without losing the draft',
    (t) async {
      final d = Device()..ready = false;
      await open(t, d);
      await tap(t, '60 min');
      d.ready = true;
      await t
          .widget<RefreshIndicator>(find.byType(RefreshIndicator))
          .onRefresh();
      await t.pumpAndSettle();
      expect(
        t
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '60 min'))
            .selected,
        isTrue,
      );
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Review lock'),
            )
            .onPressed,
        isNotNull,
      );
      expect(d.writes, 0);
    },
  );
  testWidgets(
    'Focus sheet returns reviewed options without starting a device lock',
    (t) async {
      final d = Device();
      Object? result;
      await t.pumpWidget(
        ProviderScope(
          overrides: [phoneLockGatewayProvider.overrideWithValue(d)],
          child: MaterialApp(
            theme: AppTheme.liquidGlass,
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () async {
                    result = await Navigator.of(context).push<Object?>(
                      const PhoneLockRoutePage(
                        launch: PhoneLockLaunch(focusMinutes: 50),
                      ).createRoute(context),
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tap(t, 'Open');
      await tap(t, 'Use with Focus');
      await tap(t, 'Use with Focus');
      expect(result, isA<PhoneLockOptions>());
      expect((result as PhoneLockOptions).minutes, 50);
      expect(d.writes, 0);
    },
  );
  test('status requires real native truth and seconds round up', () {
    expect(
      () => PhoneLockStatus.fromMap({'active': false}),
      throwsFormatException,
    );
    expect(phoneLockTime(1), '00:01');
    expect(phoneLockTime(60000), '01:00');
    expect(phoneLockTime(59999), '01:00');
    expect(phoneLockTime(-1), '00:00');
    final args = PhoneLockOptions(
      mode: 'nfc',
    ).arguments('test', focusEndsAt: DateTime.utc(2026));
    expect(args.containsKey('endsAtEpochMs'), isFalse);
    final legacy = <String, Object>{
      'active': false,
      'ready': false,
      'id': '',
      'mode': 'timer',
      'remainingMs': 0,
    };
    expect(PhoneLockStatus.fromMap(legacy).protectionEnabled, isNull);
    final diagnostics = PhoneLockStatus.fromMap({
      ...legacy,
      'protectionEnabled': true,
      'accessibilityEnabled': false,
      'phoneAvailable': true,
    });
    expect(diagnostics.ready, isFalse);
    expect(diagnostics.protectionEnabled, isTrue);
    expect(diagnostics.accessibilityEnabled, isFalse);
    expect(diagnostics.phoneAvailable, isTrue);
  });
  testWidgets('cancel review writes nothing and retains selections', (t) async {
    final d = Device();
    await open(t, d);
    await tap(t, '60 min');
    await tap(t, 'Review lock');
    await tap(t, 'Cancel');
    expect(d.writes, 0);
    expect(
      t.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '60 min')).selected,
      isTrue,
    );
  });
  testWidgets('NFC requires readiness and explicit review before commit', (
    t,
  ) async {
    final d = Device();
    await open(t, d);
    await tap(t, 'NFC chip');
    await tap(t, 'Review lock');
    expect(find.textContaining('15-minute recovery'), findsOneWidget);
    expect(d.writes, 0);
    await tap(t, 'Start phone lock');
    expect(d.writes, 1);
    expect(d.saved!.mode, 'nfc');
    expect(find.text('Scan NFC chip'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets('failure retains draft and does not claim active', (t) async {
    final d = Device()..fail = true;
    await open(t, d);
    await tap(t, 'Review lock');
    await tap(t, 'Start phone lock');
    expect(find.text('Time to focus'), findsNothing);
    expect(find.text('Review lock'), findsOneWidget);
    expect(d.writes, 1);
  });
  testWidgets('missing permission offers setup without starting', (t) async {
    final d = Device()..ready = false;
    await open(t, d);
    expect(
      t
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Permissions & limits'),
          )
          .onPressed,
      isNotNull,
    );
    expect(d.writes, 0);
  });
  testWidgets('NFC without a saved chip cannot review or start a lock', (
    t,
  ) async {
    final d = Device()..nfc = false;
    await open(t, d);
    await tap(t, 'NFC chip');
    expect(
      t
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Review lock'),
          )
          .onPressed,
      isNull,
    );
    expect(find.textContaining('Enable NFC and save a chip'), findsOneWidget);
    expect(d.writes, 0);
  });
  testWidgets(
    'native prerequisite diagnostics identify the actual missing step',
    (t) async {
      final d = Device()..ready = false;
      d.protection = false;
      await open(t, d);
      expect(
        find.text('Turn on Enable protection and Block selected apps.'),
        findsOneWidget,
      );
      d.protection = true;
      d.accessibility = false;
      await t
          .widget<RefreshIndicator>(find.byType(RefreshIndicator))
          .onRefresh();
      await t.pumpAndSettle();
      expect(
        find.text('Enable MyLifeGraph in Android Accessibility.'),
        findsOneWidget,
      );
      d.accessibility = true;
      d.phoneAvailable = false;
      await t
          .widget<RefreshIndicator>(find.byType(RefreshIndicator))
          .onRefresh();
      await t.pumpAndSettle();
      expect(find.textContaining('Set up a Phone app'), findsOneWidget);
      await tap(t, 'Check again');
      expect(d.writes, 0);
      expect(find.text('Ready to lock?'), findsNothing);
    },
  );
  testWidgets('Focus setup selects duration without starting native lock', (
    t,
  ) async {
    final d = Device();
    await open(t, d, launch: const PhoneLockLaunch(focusMinutes: 50));
    expect(find.text('50 min · Focus session timer'), findsOneWidget);
    expect(find.text('25 min'), findsNothing);
    expect(d.writes, 0);
  });
  for (final scale in [1.0, 1.7]) {
    testWidgets('setup stays reachable on 320px with scale $scale', (t) async {
      await open(t, Device(), width: 320, scale: scale);
      await t.scrollUntilVisible(
        find.text('Review lock'),
        160,
        scrollable: find.byType(Scrollable).first,
      );
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });
  }
  for (final entry in {
    'dark': AppTheme.dark,
    'light': AppTheme.light,
    'space': AppTheme.space,
    'glass': AppTheme.liquidGlass,
  }.entries) {
    testWidgets(
      'missing setup remains actionable in ${entry.key} at 320px and large text',
      (t) async {
        await open(
          t,
          Device()
            ..ready = false
            ..protection = false,
          width: 320,
          scale: 1.7,
          theme: entry.value,
        );
        await t.scrollUntilVisible(
          find.text('Permissions & limits'),
          160,
          scrollable: find.byType(Scrollable).first,
        );
        expect(
          t
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Permissions & limits'),
              )
              .onPressed,
          isNotNull,
        );
        expect(t.takeException(), isNull);
      },
    );
  }
  testWidgets('active scan is single flight and keeps phone action', (t) async {
    final d = Device()
      ..value = const PhoneLockStatus(
        active: true,
        id: 'nfc1',
        mode: 'nfc',
        ready: true,
        nfcAvailable: true,
        nfcEnrolled: true,
      )
      ..controlGate = Completer<void>();
    await open(t, d);
    final scan = find.text('Scan NFC chip');
    await t.ensureVisible(scan);
    await t.tap(scan);
    await t.tap(scan);
    await t.pump();
    expect(d.controls, 1);
    expect(find.text('Phone / Emergency'), findsOneWidget);
    d.controlGate!.complete();
    await t.pumpAndSettle();
    await t.pumpWidget(const SizedBox());
  });
  if (captureUiCatalog) {
    testWidgets('phone lock real Flutter render catalog', (t) async {
      await loadCatalogFonts();
      final d = Device();
      await open(t, d);
      await captureCatalog(t, 'phone-lock-setup');
      await tap(t, 'NFC chip');
      await tap(t, 'Review lock');
      await captureCatalog(t, 'phone-lock-review');
      await tap(t, 'Cancel');
      d.value = const PhoneLockStatus(
        active: true,
        id: 'timer1',
        mode: 'timer',
        ready: true,
        nfcAvailable: true,
        nfcEnrolled: true,
        remainingMs: 2479000,
        durationMs: 2700000,
      );
      await t.pumpWidget(const SizedBox());
      await open(t, d);
      await captureCatalog(t, 'phone-lock-active');
      await t.pumpWidget(const SizedBox());
    });
    testWidgets('phone lock missing setup render catalog', (t) async {
      await loadCatalogFonts();
      await open(
        t,
        Device()
          ..ready = false
          ..protection = false,
      );
      await t.ensureVisible(find.text('Permissions & limits'));
      await captureCatalog(t, 'phone-lock-needs-setup');
    });
  }
}
