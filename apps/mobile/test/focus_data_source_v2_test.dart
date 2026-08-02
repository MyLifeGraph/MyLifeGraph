import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/errors/app_exception.dart';
import 'package:my_life_graph/core/network/api_client.dart';
import 'package:my_life_graph/core/network/api_failure.dart';
import 'package:my_life_graph/features/focus/data/focus_session_supabase_data_source.dart';
import 'package:my_life_graph/features/focus/domain/focus_session.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('strict capability enables the manual V2 start transport', () async {
    final api = _RecordingApiClient(
      capabilityResponse: _capabilityResponse(),
      postResponse: _sessionResponse(),
    );
    final source = _source(api);

    final session = await source.startSession(
      sessionId: _sessionId,
      draft: FocusStartDraft(
        plannedMinutes: 25,
        recoveryMinutes: 0,
        label: 'Independent focus block',
      ),
    );

    expect(session.id, _sessionId);
    expect(session.requiresBackendLifecycle, isTrue);
    expect(api.getPaths, ['/v1/focus/capabilities']);
    expect(api.postPaths, ['/v1/focus/sessions/start']);
    expect(api.lastBody, {
      'contract_version': 'focus-start-v2',
      'request_id': _sessionId,
      'source_kind': 'manual',
      'planned_minutes': 25,
      'recovery_minutes': 0,
      'target_kind': null,
      'target_id': null,
      'label': 'Independent focus block',
    });
  });

  test('only a definitive missing capability route reports V2 absent',
      () async {
    final missing = _source(
      _RecordingApiClient(
        capabilityError: const AppException(
          'not found',
          cause: ApiFailure(
            kind: ApiFailureKind.response,
            statusCode: 404,
          ),
        ),
      ),
    );
    expect(await missing.fetchFocusV2Availability(), isFalse);

    final unavailable = _source(
      _RecordingApiClient(
        capabilityError: const AppException(
          'offline',
          cause: ApiFailure(kind: ApiFailureKind.connection),
        ),
      ),
    );
    await expectLater(
      unavailable.fetchFocusV2Availability(),
      throwsA(isA<AppException>()),
    );
  });

  test('malformed capability never enables or downgrades Focus writes',
      () async {
    final source = _source(
      _RecordingApiClient(
        capabilityResponse: {
          ..._capabilityResponse(),
          'unexpected': true,
        },
      ),
    );

    await expectLater(
      source.fetchFocusV2Availability(),
      throwsA(isA<FocusCommandException>()),
    );
  });

  test('scheduled start never probes or falls back from V2', () async {
    final api = _RecordingApiClient(
      capabilityError: const AppException('capability must not be read'),
      postError: const AppException(
        'route missing',
        cause: ApiFailure(
          kind: ApiFailureKind.response,
          statusCode: 404,
        ),
      ),
    );
    final source = _source(api);

    await expectLater(
      source.startScheduledSession(
        sessionId: _sessionId,
        sourceKind: FocusScheduleSourceKind.plannerTaskBlock,
        blockId: _blockId,
        plannedMinutes: 20,
      ),
      throwsA(isA<AppException>()),
    );
    expect(api.getPaths, isEmpty);
    expect(api.postPaths, ['/v1/focus/sessions/start']);
  });
}

const _sessionId = 'f6000000-0000-4000-8000-000000000001';
const _blockId = 'f6000000-0000-4000-8000-000000000002';

FocusSessionSupabaseDataSource _source(ApiClient apiClient) {
  return FocusSessionSupabaseDataSource(
    SupabaseClient(
      'http://localhost:54321',
      'test-anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    ),
    apiClient: apiClient,
    accessTokenProvider: () async => 'focus-token',
  );
}

Map<String, dynamic> _capabilityResponse() => {
      'contract_version': 'focus-capabilities-v1',
      'origin': 'authenticated_backend',
      'focus_session_v2': true,
    };

Map<String, dynamic> _sessionResponse() => {
      'contract_version': 'focus-session-v2',
      'origin': 'authenticated_backend',
      'replayed': false,
      'id': _sessionId,
      'status': 'active',
      'started_at': '2026-08-02T10:00:00Z',
      'ended_at': null,
      'planned_minutes': 25,
      'actual_minutes': null,
      'label': 'Independent focus block',
      'task_id': null,
      'habit_id': null,
      'entry_date': '2026-08-02',
      'recovery_minutes': 0,
      'updated_at': '2026-08-02T10:00:00Z',
      'schedule_source': null,
    };

class _RecordingApiClient extends ApiClient {
  _RecordingApiClient({
    this.capabilityResponse,
    this.capabilityError,
    this.postResponse,
    this.postError,
  }) : super(Dio());

  final Map<String, dynamic>? capabilityResponse;
  final Object? capabilityError;
  final Map<String, dynamic>? postResponse;
  final Object? postError;
  final List<String> getPaths = [];
  final List<String> postPaths = [];
  Map<String, dynamic>? lastBody;

  @override
  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, String>? headers,
  }) async {
    getPaths.add(path);
    final error = capabilityError;
    if (error != null) throw error;
    return capabilityResponse ?? <String, dynamic>{};
  }

  @override
  Future<Map<String, dynamic>> postJson(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  }) async {
    postPaths.add(path);
    lastBody = body;
    final error = postError;
    if (error != null) throw error;
    return postResponse ?? <String, dynamic>{};
  }
}
