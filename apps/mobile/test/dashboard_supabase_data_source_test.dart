import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:my_life_graph/features/dashboard/data/datasources/dashboard_supabase_data_source.dart';
import 'package:my_life_graph/features/dashboard/domain/entities/dashboard_snapshot.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('latest check-in read is owner-filtered and date-bounded', () async {
    Uri? query;
    final client = _client((request) async {
      query = request.url;
      return _json(
        const [
          {
            'entry_date': '2026-08-04',
            'mood_score': 6,
            'energy_level': 7,
            'sleep_hours': 7.5,
            'stress_level': 3,
            'metadata': {
              'captures': {
                'morning': {'sleep_quality': 8},
              },
            },
          },
        ],
        request,
      );
    });
    addTearDown(client.dispose);
    final source = DashboardSupabaseDataSource(
      client,
      resolveUserId: () async => 'owner-id',
    );

    final result = await source.getLatestCheckIn(
      throughLocalDate: DateTime(2026, 8, 5),
    );

    expect(result?.entryDate, DateTime(2026, 8, 4));
    expect(result?.sleepQuality, 8);
    expect(query?.queryParameters['user_id'], 'eq.owner-id');
    expect(query?.queryParameters['entry_date'], 'lte.2026-08-05');
    expect(query?.queryParameters['limit'], '1');
    expect(query?.queryParameters['order'], contains('entry_date.desc'));
  });

  test('malformed latest row is an isolated unavailable error', () async {
    final client = _client(
      (request) async => _json(
        const [
          {
            'entry_date': '2026-02-30',
            'mood_score': 6,
            'metadata': {},
          },
        ],
        request,
      ),
    );
    addTearDown(client.dispose);
    final source = DashboardSupabaseDataSource(
      client,
      resolveUserId: () async => 'owner-id',
    );

    await expectLater(
      source.getLatestCheckIn(
        throughLocalDate: DateTime(2026, 8, 5),
      ),
      throwsA(isA<DashboardUnavailableException>()),
    );
  });

  test('open tasks cannot be displaced by the terminal task history cap',
      () async {
    final taskQueries = <Uri>[];
    final client = _client((request) async {
      if (request.url.path.endsWith('/daily_logs') ||
          request.url.path.endsWith('/schedule_items')) {
        return _json(const [], request);
      }
      if (request.url.path.endsWith('/tasks')) {
        taskQueries.add(request.url);
        final status = request.url.queryParameters['status'];
        if (status == 'in.("todo","in_progress")') {
          return _json(
            [
              {
                'id': 'open-task',
                'title': 'Submit algorithms assignment',
                'deadline': '2026-07-30T12:00:00Z',
                'priority': 'high',
                'status': 'todo',
                'estimated_minutes': 90,
                'source': 'manual',
              },
            ],
            request,
          );
        }
        if (status == 'in.("done","cancelled")') {
          return _json(
            List.generate(
              100,
              (index) => {
                'id': 'terminal-$index',
                'title': 'Finished task $index',
                'deadline': null,
                'priority': 'normal',
                'status': 'done',
                'estimated_minutes': null,
                'source': 'manual',
              },
            ),
            request,
          );
        }
      }
      throw StateError('Unexpected request ${request.url}');
    });
    addTearDown(client.dispose);
    final source = DashboardSupabaseDataSource(
      client,
      resolveUserId: () async => 'owner-id',
    );

    final snapshot = await source.getSnapshot();

    expect(taskQueries, hasLength(2));
    expect(
      snapshot.todayPlan.any((item) => item.id == 'open-task'),
      isTrue,
    );
    expect(snapshot.todayPlan, hasLength(101));
  });
}

SupabaseClient _client(
  Future<http.Response> Function(http.Request request) handler,
) =>
    SupabaseClient(
      'http://localhost:54321',
      'test-anon-key',
      httpClient: MockClient(handler),
      accessToken: () async => 'test-access-token',
    );

http.Response _json(Object value, http.Request request) => http.Response(
      jsonEncode(value),
      200,
      request: request,
      headers: {'content-type': 'application/json'},
    );
