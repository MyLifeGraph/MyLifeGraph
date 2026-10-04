import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:my_life_graph/composition/auth_providers.dart';
import 'package:my_life_graph/composition/widgets/coach_phone_data_sheet.dart';
import 'package:my_life_graph/core/network/api_client.dart';
import 'package:my_life_graph/core/supabase/supabase_providers.dart';
import 'package:my_life_graph/features/auth/domain/app_session.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:my_life_graph/core/theme/app_theme.dart';
import 'support/ui_catalog_capture.dart';

const _owner = '11111111-1111-4111-8111-111111111111';
const _device = '22222222-2222-4222-8222-222222222222';
const _channel = MethodChannel('com.mylifegraph.app/blocking_v2');

class _Auth extends AuthController {
  _Auth() : super(null);
  void owner(String id) => state = AsyncData(
    AppSession.authenticated(
      AppProfile(
        id: id,
        email: 'synthetic@example.test',
        name: 'Student',
        timezone: 'UTC',
        role: AppRole.user,
        onboardingDone: true,
        authProvider: 'email',
      ),
    ),
  );
}

class _Api extends ApiClient {
  _Api({this.enabled = true}) : super(Dio());
  bool enabled;
  bool conflict = false;
  int reads = 0;
  final writes = <Map<String, dynamic>>[];
  Completer<void>? waitRead;
  Map<String, dynamic> value() => {
    'contract_version': coachPhoneDataVersion,
    'enabled': enabled,
    'revision': 7,
    'device_id': enabled ? _device : null,
    'timezone': 'Europe/Berlin',
    'data': null,
  };
  @override
  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, String>? headers,
  }) async {
    reads++;
    expect(headers!['Authorization'], 'Bearer synthetic');
    await waitRead?.future;
    return value();
  }

  @override
  Future<Map<String, dynamic>> postJson(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  }) async {
    writes.add(body!);
    if (conflict) throw StateError('409 stale revision');
    enabled = body['command'] == 'enable' || body['command'] == 'sync';
    return value();
  }
}

Future<_Auth> _open(WidgetTester tester, _Api api, {double scale = 1}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.resetPhysicalSize();
  tester.view.physicalSize = const Size(320, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final client = SupabaseClient(
    'http://localhost:54321',
    'synthetic',
    authOptions: const AuthClientOptions(autoRefreshToken: false),
    httpClient: MockClient((_) async => throw StateError('No network')),
  );
  addTearDown(() {
    unawaited(client.dispose());
  });
  await tester.runAsync(
    () => client.auth.recoverSession(
      jsonEncode({
        'access_token': 'synthetic',
        'refresh_token': 'synthetic',
        'token_type': 'bearer',
        'expires_in': 3600,
        'expires_at': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
        'user': {
          'id': _owner,
          'aud': 'authenticated',
          'app_metadata': {},
          'user_metadata': {},
          'created_at': '2026-10-04T00:00:00Z',
        },
      }),
    ),
  );
  final auth = _Auth();
  await tester.runAsync(auth.refresh);
  auth.owner(_owner);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith((_) => auth),
        supabaseClientProvider.overrideWithValue(client),
        apiClientProvider.overrideWithValue(api),
      ],
      child: MaterialApp(
        theme: AppTheme.liquidGlass,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showCoachPhoneData(context),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
  return auth;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          if (call.method == 'phoneStatus') {
            return {'granted': true, 'device_id': _device};
          }
          if (call.method == 'phoneData') return {'timezone': 'Europe/Berlin'};
          throw StateError(
            'Unexpected local permission/blocking mutation: ${call.method}',
          );
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null),
  );

  testWidgets(
    'open never syncs; explicit sync sends profile zone and CAS revision',
    (tester) async {
      final api = _Api();
      await _open(tester, api);
      expect(api.writes, isEmpty);
      await tester.ensureVisible(find.text('Sync now'));
      await tester.tap(find.text('Sync now'));
      await tester.pumpAndSettle();
      expect(api.writes.single['command'], 'sync');
      expect(api.writes.single['expected_revision'], 7);
      expect(api.writes.single['data']['timezone'], 'Europe/Berlin');
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
  testWidgets(
    'account switch during native read drops sample without upload',
    (tester) async {
      final sample = Completer<Map<String, dynamic>>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            _channel,
            (call) async => call.method == 'phoneStatus'
                ? {'granted': true, 'device_id': _device}
                : sample.future,
          );
      final api = _Api();
      final auth = await _open(tester, api);
      await tester.ensureVisible(find.text('Sync now'));
      await tester.tap(find.text('Sync now'));
      await tester.pump();
      auth.owner('other-owner');
      sample.complete({'timezone': 'Europe/Berlin'});
      await tester.pumpAndSettle();
      expect(api.writes, isEmpty);
      expect(find.text('Account changed. Reopen Coach data.'), findsOneWidget);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
  testWidgets(
    'rapid reload is singleflight and large text remains scrollable',
    (tester) async {
      final api = _Api();
      await _open(tester, api, scale: 2);
      expect(find.text('Daily app time'), findsOneWidget);
      expect(find.text('Top apps'), findsOneWidget);
      expect(find.text('Blocking attempts'), findsOneWidget);
      expect(find.text('Data shared'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Reload'));
      final reloadRect = tester.getRect(find.text('Reload'));
      final deleteRect = tester.getRect(find.text('Delete'));
      expect(reloadRect.center.dy, closeTo(deleteRect.center.dy, 1));
      expect(reloadRect.right, lessThan(deleteRect.left));
      final reload = tester.widget<TextButton>(
        find.ancestor(
          of: find.text('Reload'),
          matching: find.byType(TextButton),
        ),
      );
      api.waitRead = Completer<void>();
      reload.onPressed!();
      reload.onPressed!();
      expect(api.reads, 2);
      api.waitRead!.complete();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Done'));
      expect(find.text('Done'), findsOneWidget);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
  testWidgets(
    'consent dialog at large text is dismissible without enabling',
    (tester) async {
      final api = _Api(enabled: false);
      await _open(tester, api, scale: 2);
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('cloud account'), findsOneWidget);
      expect(find.textContaining('earlier Coach replies'), findsOneWidget);
      await tester.ensureVisible(find.text('Privacy details'));
      await tester.tap(find.text('Privacy details'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('No messages, notification content'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('Not now'));
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(api.writes, isEmpty);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
  testWidgets(
    'disable and delete have no native permission or blocking mutation',
    (tester) async {
      final api = _Api();
      await _open(tester, api);
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(api.writes.single['command'], 'disable');
      expect(api.writes.single['data'], isNull);
      expect(api.writes.single['device_id'], isNull);
      await tester.ensureVisible(find.text('Delete'));
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(api.writes.last['command'], 'delete');
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
  testWidgets(
    'stale sync fails closed until explicit reload, without auto retry',
    (tester) async {
      final api = _Api()..conflict = true;
      await _open(tester, api);
      await tester.ensureVisible(find.text('Sync now'));
      await tester.tap(find.text('Sync now'));
      await tester.pumpAndSettle();
      expect(api.writes.length, 1);
      expect(
        find.text('Could not confirm. Reload before retrying.'),
        findsOneWidget,
      );
      final sync = tester.widget<TextButton>(
        find.ancestor(
          of: find.text('Sync now'),
          matching: find.byType(TextButton),
        ),
      );
      expect(sync.onPressed, isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
  if (captureUiCatalog) {
    testWidgets(
      'phone data synthetic visual catalog',
      (tester) async {
        await loadCatalogFonts();
        await _open(tester, _Api(enabled: false));
        await captureCatalog(tester, 'coach-phone-data-320');
        await tester.tap(find.byType(SwitchListTile));
        await tester.pumpAndSettle();
        await captureCatalog(tester, 'coach-phone-consent-320');
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );
  }
}
