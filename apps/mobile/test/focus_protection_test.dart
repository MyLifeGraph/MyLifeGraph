import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/features/focus_protection/application/focus_protection_gateway.dart';
import 'package:my_life_graph/features/focus_protection/domain/focus_protection.dart';
import 'package:my_life_graph/features/focus_protection/presentation/pages/focus_protection_settings_page.dart';

void main() {
  test('typed status parses all supported warnings and lease state', () {
    final status = FocusProtectionStatus.fromMap({
      'platformSupported': true,
      'accessibilityEnabled': false,
      'notificationPolicyGranted': false,
      'configuration': {
        'enabled': true,
        'blockSelectedApps': true,
        'silenceNotifications': true,
        'selectedPackages': ['video.app'],
        'consentVersions': {'app_catalog': 1},
      },
      'lease': {
        'sessionId': 'session-1',
        'startedAtEpochMs': 1,
        'endsAtEpochMs': 2,
        'state': 'emergency_released',
      },
      'activeMechanisms': ['app_blocking'],
      'warnings': [
        'accessibility_disabled',
        'notification_policy_missing',
        'dnd_unsupported',
        'no_apps_selected',
        'zen_rule_missing_or_overridden',
        'native_failure',
      ],
    });

    expect(status.configuration.selectedPackages, {'video.app'});
    expect(status.activeMechanisms, {'app_blocking'});
    expect(
      status.lease?.state,
      FocusProtectionLeaseState.emergencyReleased,
    );
    expect(status.warnings, FocusProtectionWarning.values.toSet());
  });

  test('native read failure does not invent a disabled configuration', () {
    final unknown = FocusProtectionStatus.nativeFailure();
    final known = FocusProtectionStatus.nativeFailure(
      configuration: FocusProtectionConfiguration.disabled(),
    );

    expect(unknown.configurationKnown, isFalse);
    expect(known.configurationKnown, isTrue);
  });

  testWidgets('app catalog disclosure can be declined without side effects',
      (tester) async {
    final gateway = _FakeGateway(_status());
    await _pumpSettings(tester, gateway);

    await tester.scrollUntilVisible(
      find.text('Choose apps'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Choose apps'));
    await tester.pumpAndSettle();
    expect(find.text('Allow installed-app lookup?'), findsOneWidget);
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();

    expect(gateway.listCalls, 0);
    expect(gateway.savedConfigurations, isEmpty);
    expect(find.text('Choose apps'), findsOneWidget);
  });

  testWidgets('accepted disclosure loads and saves selected apps',
      (tester) async {
    final gateway = _FakeGateway(_status());
    await _pumpSettings(tester, gateway);

    await tester.scrollUntilVisible(
      find.text('Choose apps'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Choose apps'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Agree and show apps'));
    await tester.pumpAndSettle();

    expect(gateway.listCalls, 1);
    expect(find.text('Video'), findsOneWidget);
    expect(
      gateway.savedConfigurations.last.hasConsent(
        focusProtectionAppCatalogConsent,
      ),
      isTrue,
    );

    await tester.tap(find.byKey(const ValueKey('focus-app-video.app')));
    await tester.pumpAndSettle();
    expect(
      gateway.savedConfigurations.last.selectedPackages,
      {'video.app'},
    );
  });

  testWidgets('active lease locks every configuration control', (tester) async {
    final now = DateTime.now();
    final gateway = _FakeGateway(
      _status(
        lease: FocusProtectionLease(
          sessionId: 'session-1',
          startedAt: now.subtract(const Duration(minutes: 1)),
          endsAt: now.add(const Duration(minutes: 10)),
          state: FocusProtectionLeaseState.active,
        ),
      ),
    );
    await _pumpSettings(tester, gateway);

    expect(
      find.textContaining('protected Focus session is active'),
      findsOneWidget,
    );
    final master = tester.widget<SwitchListTile>(
      find.byKey(const ValueKey('focus-protection-master-switch')),
    );
    expect(master.onChanged, isNull);
    await tester.scrollUntilVisible(
      find.text('Choose apps'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Choose apps'),
          )
          .onPressed,
      isNull,
    );
  });

  test('Android manifest and accessibility source keep the narrow boundary',
      () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final service = File(
      'android/app/src/main/res/xml/focus_block_accessibility_service.xml',
    ).readAsStringSync();
    final nativeSources = Directory(
      'android/app/src/main/kotlin/com/mylifegraph/app',
    )
        .listSync()
        .whereType<File>()
        .map((file) => file.readAsStringSync())
        .join('\n');

    expect(service, contains('typeWindowStateChanged'));
    expect(service, contains('android:canRetrieveWindowContent="false"'));
    expect(service, contains('android:canPerformGestures="false"'));
    expect(service, contains('android:isAccessibilityTool="false"'));
    expect(manifest, isNot(contains('QUERY_ALL_PACKAGES')));
    expect(manifest, isNot(contains('NotificationListenerService')));
    expect(manifest, isNot(contains('BIND_VPN_SERVICE')));
    expect(manifest, contains('BIND_ACCESSIBILITY_SERVICE'));
    expect(manifest, contains('BIND_CONDITION_PROVIDER_SERVICE'));
    expect(manifest, contains('android:exported="false"'));
    expect(nativeSources, isNot(contains('rootInActiveWindow')));
    expect(nativeSources, isNot(contains('event.text')));
    expect(nativeSources, contains('event.packageName'));
    expect(nativeSources, contains('notifyCondition'));
    expect(nativeSources, contains('Build.VERSION.SDK_INT >= 35'));
    expect(nativeSources, contains('publishDesiredState'));
    expect(nativeSources, contains('EmergencyReleaseGate'));
    expect(nativeSources, isNot(contains('setOnLongClickListener')));
  });
}

Future<void> _pumpSettings(
  WidgetTester tester,
  FocusProtectionGateway gateway,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [focusProtectionGatewayProvider.overrideWithValue(gateway)],
      child: const MaterialApp(home: FocusProtectionSettingsPage()),
    ),
  );
  await tester.pumpAndSettle();
}

FocusProtectionStatus _status({FocusProtectionLease? lease}) {
  return FocusProtectionStatus(
    platformSupported: true,
    accessibilityEnabled: false,
    notificationPolicyGranted: false,
    configuration: FocusProtectionConfiguration(
      enabled: true,
      blockSelectedApps: true,
      silenceNotifications: true,
    ),
    lease: lease,
    warnings: const [
      FocusProtectionWarning.accessibilityDisabled,
      FocusProtectionWarning.notificationPolicyMissing,
      FocusProtectionWarning.noAppsSelected,
    ],
  );
}

class _FakeGateway implements FocusProtectionGateway {
  _FakeGateway(this.status);

  FocusProtectionStatus status;
  int listCalls = 0;
  final savedConfigurations = <FocusProtectionConfiguration>[];

  @override
  Future<FocusProtectionStatus> readStatus() async => status;

  @override
  Future<List<InstalledLaunchableApp>> listLaunchableApps() async {
    listCalls++;
    return const [
      InstalledLaunchableApp(packageName: 'video.app', label: 'Video'),
    ];
  }

  @override
  Future<FocusProtectionStatus> saveConfiguration(
    FocusProtectionConfiguration configuration,
  ) async {
    savedConfigurations.add(configuration);
    status = FocusProtectionStatus(
      platformSupported: status.platformSupported,
      accessibilityEnabled: status.accessibilityEnabled,
      notificationPolicyGranted: status.notificationPolicyGranted,
      configuration: configuration,
      lease: status.lease,
      activeMechanisms: status.activeMechanisms,
      warnings: status.warnings,
    );
    return status;
  }

  @override
  Future<void> openAccessibilitySettings() async {}

  @override
  Future<void> openNotificationPolicySettings() async {}

  @override
  Future<FocusProtectionStatus> activateLease({
    required String sessionId,
    required DateTime startedAt,
    required DateTime endsAt,
  }) async =>
      status;

  @override
  Future<FocusProtectionStatus> deactivateLease(String sessionId) async =>
      status;

  @override
  Future<FocusProtectionStatus> emergencyRelease(String sessionId) async =>
      status;
}
