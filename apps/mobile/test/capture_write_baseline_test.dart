import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:my_life_graph/core/network/api_client.dart';
import 'package:my_life_graph/core/network/api_failure.dart';
import 'package:my_life_graph/core/errors/app_exception.dart';
import 'package:my_life_graph/features/quick_action/data/quick_check_in_supabase_data_source.dart';
import 'package:my_life_graph/features/quick_action/domain/quick_check_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  for (final status in [409, 422, 503]) {
    test('only HTTP 409 becomes a typed Capture conflict ($status)', () async {
      final h = _CaptureHarness();
      addTearDown(h.client.dispose);
      await h.signIn();
      final draft = (await h.store.loadToday(DateTime.parse(_date)))!.morning!;
      final failure = AppException(
        'Network request failed',
        cause: ApiFailure(
          kind: ApiFailureKind.response,
          statusCode: status,
          responseData: {
            'detail': 'Daily Capture was changed by another write.',
          },
        ),
      );
      h.api.failure = failure;
      await expectLater(
        h.store.saveMorning(draft),
        status == 409
            ? throwsA(isA<QuickCheckInConflictException>())
            : throwsA(same(failure)),
      );
      h.api.failure = null;
      await h.store.saveMorning(draft);
      expect(h.api.requests[1], h.api.requests[0]);
    });
  }
  for (final morning in [true, false]) {
    test(
      '${morning ? 'Morning' : 'Evening'} retains its reviewed baseline after another read',
      () async {
        final harness = _CaptureHarness();
        addTearDown(harness.client.dispose);
        await harness.signIn();
        final reviewed = (await harness.store.loadToday(
          DateTime.parse(_date),
        ))!;
        harness.entry = _entry('concurrent', 8);
        // Calendar status and another form can read newer data using this store.
        await harness.store.loadToday(DateTime.parse(_date));

        if (morning) {
          await harness.store.saveMorning(
            reviewed.morning!.forEditing().copyWith(energy: 3),
          );
        } else {
          await harness.store.saveEvening(
            reviewed.evening!.forEditing().copyWith(energy: 3),
          );
        }

        expect(harness.api.requests.single['expected_capture'], {
          'capture_id': '${morning ? 'morning' : 'evening'}-initial',
          'captured_at': _capturedAt.toIso8601String(),
        });
        expect(
          harness.reads,
          2,
          reason: 'Save must not silently rebase a reviewed draft.',
        );
      },
    );
  }

  test(
    'missing ordinary day stays null; editor read binds known absence',
    () async {
      final h = _CaptureHarness()..entry = null;
      addTearDown(h.client.dispose);
      await h.signIn();
      expect(await h.store.loadToday(DateTime.parse(_date)), isNull);
      final read = (await loadCaptureForEditing(
        h.store,
        DateTime.parse(_date),
      ))!;
      expect(read.hasAnyCapture, isFalse);
      expect(read.morning, isNull);
      expect(read.evening, isNull);
      final draft = _entry(
        'new',
        5,
      ).morning!.copyWith(writeBaseline: read.morningBaseline);
      h.entry = _entry('created-elsewhere', 8);
      await h.store.saveMorning(draft);
      expect(h.api.requests.single['expected_capture'], isNull);
    },
  );

  test('unknown baseline and owner/date/branch mismatch never write', () async {
    final h = _CaptureHarness();
    addTearDown(h.client.dispose);
    await h.signIn();
    await expectLater(
      h.store.saveMorning(_entry('unknown', 5).morning!),
      throwsA(isA<QuickCheckInUnavailableException>()),
    );
    final read = (await h.store.loadToday(DateTime.parse(_date)))!;
    await expectLater(
      h.store.saveMorning(read.morning!.copyWith(entryDate: '2026-10-15')),
      throwsA(isA<QuickCheckInUnavailableException>()),
    );
    await expectLater(
      h.store.saveMorning(
        read.morning!.copyWith(writeBaseline: read.eveningBaseline),
      ),
      throwsA(isA<QuickCheckInUnavailableException>()),
    );
    await h.signIn('owner-b');
    await expectLater(
      h.store.saveMorning(read.morning!),
      throwsA(isA<QuickCheckInUnavailableException>()),
    );
    expect(h.api.requests, isEmpty);
  });

  test(
    'failed write retry keeps request and baseline despite newer reads',
    () async {
      final h = _CaptureHarness();
      addTearDown(h.client.dispose);
      await h.signIn();
      final read = (await h.store.loadToday(DateTime.parse(_date)))!;
      final draft = read.morning!.copyWith(energy: 2);
      h.api.fail = true;
      await expectLater(h.store.saveMorning(draft), throwsStateError);
      h.entry = _entry('concurrent', 9);
      await h.store.loadToday(DateTime.parse(_date));
      h.api.fail = false;
      await h.store.saveMorning(draft);
      expect(h.api.requests[1], h.api.requests[0]);
      expect(h.reads, 2);
    },
  );

  test(
    'same payload reviewed against a new baseline has a new request',
    () async {
      final h = _CaptureHarness();
      addTearDown(h.client.dispose);
      await h.signIn();
      final old = (await h.store.loadToday(DateTime.parse(_date)))!.morning!;
      h.api.fail = true;
      await expectLater(h.store.saveMorning(old), throwsStateError);
      h.entry = _entry('concurrent', 9);
      final fresh = (await h.store.loadToday(DateTime.parse(_date)))!;
      h.api.fail = false;
      await h.store.saveMorning(
        old.copyWith(writeBaseline: fresh.morningBaseline),
      );
      expect(
        h.api.requests[1]['request_id'],
        isNot(h.api.requests[0]['request_id']),
      );
      expect(
        (h.api.requests[1]['expected_capture'] as Map)['capture_id'],
        'morning-concurrent',
      );
    },
  );

  test(
    'guest merge binds each branch and retains exact failed replay',
    () async {
      final h = _CaptureHarness();
      addTearDown(h.client.dispose);
      await h.signIn();
      final guest = _entry('guest', 6);
      h.api.fail = true;
      await expectLater(
        h.store.mergeEntryForUser(userId: 'owner-a', entry: guest),
        throwsStateError,
      );
      h.entry = _entry('concurrent', 9);
      h.api.fail = false;
      await h.store.mergeEntryForUser(userId: 'owner-a', entry: guest);
      expect(h.api.requests[1], h.api.requests[0]);
      expect(
        (h.api.requests[2]['expected_capture'] as Map)['capture_id'],
        'morning-concurrent',
      );
      expect(
        (h.api.requests[2]['capture'] as Map)['capture_id'],
        'morning-guest',
      );
      await expectLater(
        h.store.mergeEntryForUser(userId: 'owner-b', entry: guest),
        throwsA(isA<QuickCheckInUnavailableException>()),
      );
      expect(h.api.requests, hasLength(3));
    },
  );

  test('read baseline never enters persisted capture or guest JSON', () async {
    final h = _CaptureHarness();
    addTearDown(h.client.dispose);
    await h.signIn();
    final read = (await h.store.loadToday(DateTime.parse(_date)))!;
    expect(read.toGuestJson(), h.entry!.toGuestJson());
    expect(
      read.morning!.normalized().writeBaseline,
      same(read.morningBaseline),
    );
    expect(
      read.evening!.forEditing().writeBaseline,
      same(read.eveningBaseline),
    );
  });
}

const _date = '2026-10-16';
final _capturedAt = DateTime.utc(2026, 10, 16, 9);

DailyCaptureEntry _entry(String identity, int energy) => DailyCaptureEntry(
  entryDate: _date,
  morning: MorningCalibrationDraft(
    captureId: 'morning-$identity',
    entryDate: _date,
    capturedAt: _capturedAt,
    sleepQuality: 7,
    energy: energy,
    estimatedSleepStartedAt: DateTime.utc(2026, 10, 15, 23),
    wokeAt: DateTime.utc(2026, 10, 16, 7),
    estimatedSleepMinutes: 480,
    sleepTargetMinutes: 480,
  ),
  evening: EveningShutdownDraft(
    captureId: 'evening-$identity',
    entryDate: _date,
    capturedAt: _capturedAt,
    mood: 7,
    energy: energy,
    stress: 2,
    stressSource: null,
    stressControllability: null,
    focusBand: null,
    tomorrowPriority: '',
    plannedSleepTime: '23:00',
    sleepTargetMinutes: 480,
  ),
);

class _CaptureHarness {
  _CaptureHarness() {
    client = SupabaseClient(
      'http://localhost:54321',
      'synthetic-anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/rest/v1/daily_logs');
        reads++;
        final row = entry == null
            ? null
            : {
                'entry_date': _date,
                'source': 'quick_check_in',
                'updated_at': _capturedAt.toIso8601String(),
                'metadata': entry!.toCaptureMetadata(),
              };
        return http.Response(
          jsonEncode(row),
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    store = QuickCheckInSupabaseDataSource(client, apiClient: api);
  }
  late final SupabaseClient client;
  late final QuickCheckInSupabaseDataSource store;
  final api = _CaptureApi();
  DailyCaptureEntry? entry = _entry('initial', 5);
  int reads = 0;

  Future<void> signIn([String owner = 'owner-a']) => client.auth
      .recoverSession(
        jsonEncode({
          'access_token': 'synthetic-token-$owner',
          'refresh_token': 'synthetic-refresh',
          'token_type': 'bearer',
          'expires_in': 3600,
          'expires_at':
              DateTime.now()
                  .add(const Duration(hours: 1))
                  .millisecondsSinceEpoch ~/
              1000,
          'user': {
            'id': owner,
            'aud': 'authenticated',
            'app_metadata': {},
            'user_metadata': {},
            'created_at': '2026-01-01T00:00:00Z',
          },
        }),
      )
      .then((_) {});
}

class _CaptureApi extends ApiClient {
  _CaptureApi() : super(Dio());
  final requests = <Map<String, dynamic>>[];
  bool fail = false;
  Object? failure;

  @override
  Future<Map<String, dynamic>> putJson(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  }) async {
    final request = Map<String, dynamic>.from(body!);
    requests.add(request);
    if (failure case final error?) throw error;
    if (fail) throw StateError('Simulated response loss');
    final capture = request['capture'] as Map;
    return {
      'contract_version': 'daily-capture-write-v1',
      'entry_date': _date,
      'branch': path.split('/').last,
      'capture_id': capture['capture_id'],
      'captured_at': capture['captured_at'],
      'updated_at': '2026-10-17T09:00:00Z',
      'replayed': false,
    };
  }
}
