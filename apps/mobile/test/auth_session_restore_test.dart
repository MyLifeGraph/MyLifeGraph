import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:my_life_graph/features/auth/data/auth_repository.dart';
import 'package:my_life_graph/features/auth/domain/auth_failure.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('expired restored session refreshes before hosted recovery reads', () async {
    final harness = _RestorationHarness();
    addTearDown(harness.client.dispose);
    await harness.restoreExpiredSession();

    final session = await harness.repository.currentSession();

    expect(session?.profile.id, 'restore-user');
    expect(harness.refreshCalls, 1);
    expect(harness.recoveryTokens, [harness.freshToken]);
    expect(harness.profileCalls, 1);
  });

  test('startup shares an already running SDK refresh', () async {
    final gate = Completer<void>();
    final harness = _RestorationHarness(refreshGate: gate);
    addTearDown(harness.client.dispose);
    await harness.restoreExpiredSession();
    final sdkRecovery = harness.client.auth.refreshSession();
    await harness.refreshStarted.future;
    final restoration = harness.repository.currentSession();
    final outcome = expectLater(
      restoration,
      completion(predicate((dynamic value) => value?.profile.id == 'restore-user')),
    );
    await Future<void>.delayed(Duration.zero);
    final earlyRecoveryTokens = List<String>.of(harness.recoveryTokens);
    gate.complete();
    await sdkRecovery;
    await outcome;
    expect(earlyRecoveryTokens, isEmpty);
    expect(harness.refreshCalls, 1);
    expect(harness.recoveryTokens, [harness.freshToken]);
  });

  test('invalid refresh never proceeds to recovery or profile reads', () async {
    final harness = _RestorationHarness(rejectRefresh: true);
    addTearDown(harness.client.dispose);
    await harness.restoreExpiredSession();

    await expectLater(harness.repository.currentSession(), throwsA(isA<AuthException>()));

    expect(harness.refreshCalls, 1);
    expect(harness.recoveryTokens, isEmpty);
    expect(harness.profileCalls, 0);
  });

  test('successful token refresh does not conceal a missing profile', () async {
    final harness = _RestorationHarness(missingProfile: true);
    addTearDown(harness.client.dispose);
    await harness.restoreExpiredSession();

    await expectLater(
      harness.repository.currentSession(),
      throwsA(isA<MissingProfileInvariantException>()),
    );
    expect(harness.recoveryTokens, [harness.freshToken]);
  });

  test('expired mock session remains local without refreshing credentials', () async {
    final harness = _RestorationHarness(useMockData: true);
    addTearDown(harness.client.dispose);
    await harness.restoreExpiredSession();

    final session = await harness.repository.currentSession();

    expect(session?.profile.id, 'restore-user');
    expect(harness.refreshCalls, 0);
    expect(harness.recoveryTokens, isEmpty);
    expect(harness.profileCalls, 0);
  });
}

class _RestorationHarness {
  _RestorationHarness({
    this.refreshGate,
    this.rejectRefresh = false,
    this.missingProfile = false,
    bool useMockData = false,
  }) {
    client = SupabaseClient(
      'http://localhost:54321',
      'synthetic-publishable-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        if (request.url.path == '/auth/v1/token') {
          refreshCalls++;
          if (!refreshStarted.isCompleted) refreshStarted.complete();
          await refreshGate?.future;
          return http.Response(
            jsonEncode(rejectRefresh
                ? {'code': 'refresh_token_not_found', 'msg': 'Synthetic expired refresh token'}
                : _session(freshToken)),
            rejectRefresh ? 400 : 200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.url.path == '/rest/v1/profiles') {
          profileCalls++;
          return http.Response(jsonEncode(missingProfile ? [] : [{
            'id': 'restore-user', 'email': 'restore@example.test',
            'display_name': 'Restore', 'timezone': 'Europe/Berlin',
            'role': 'user', 'auth_provider': 'google',
            'onboarding_completed_at': '2026-10-01T00:00:00Z',
          }]), 200, request: request, headers: {'content-type': 'application/json'});
        }
        throw StateError('Unexpected synthetic request: ${request.url.path}');
      }),
    );
    repository = AuthRepository(
      client,
      useMockData: useMockData,
      isHostedEnvironment: true,
      pendingAccountDeletionResolver: ({required userId, required accessToken}) async {
        recoveryTokens.add(accessToken);
        if (accessToken != freshToken) {
          throw const AuthException('Synthetic API rejects expired JWT', statusCode: '401');
        }
        return null;
      },
    );
  }

  final Completer<void>? refreshGate;
  final bool rejectRefresh;
  final bool missingProfile;
  final refreshStarted = Completer<void>();
  late final SupabaseClient client;
  late final AuthRepository repository;
  final recoveryTokens = <String>[];
  int refreshCalls = 0;
  int profileCalls = 0;
  final freshToken = _jwt(DateTime.now().add(const Duration(hours: 1)));

  Future<void> restoreExpiredSession() => client.auth.setInitialSession(
    jsonEncode(_session(_jwt(DateTime.now().subtract(const Duration(hours: 1))))),
  );

  Map<String, Object> _session(String token) => {
    'access_token': token,
    'refresh_token': 'synthetic-refresh-token',
    'token_type': 'bearer',
    'expires_in': 3600,
    'user': {
      'id': 'restore-user', 'email': 'restore@example.test',
      'aud': 'authenticated', 'app_metadata': {'provider': 'google'},
      'user_metadata': <String, Object>{}, 'created_at': '2026-10-01T00:00:00Z',
    },
  };
}

String _jwt(DateTime expiry) {
  String part(Object value) => base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${part({'alg': 'HS256', 'typ': 'JWT'})}.${part({'sub': 'restore-user', 'exp': expiry.millisecondsSinceEpoch ~/ 1000})}.synthetic';
}
