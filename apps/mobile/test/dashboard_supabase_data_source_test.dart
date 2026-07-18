import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:my_life_graph/features/dashboard/data/datasources/dashboard_supabase_data_source.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
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
