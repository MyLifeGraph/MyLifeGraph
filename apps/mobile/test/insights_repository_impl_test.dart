import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/features/insights/data/datasources/insights_mock_data_source.dart';
import 'package:my_life_graph/features/insights/data/datasources/insights_supabase_data_source.dart';
import 'package:my_life_graph/features/insights/data/repositories/insights_repository_impl.dart';
import 'package:my_life_graph/features/insights/domain/entities/correlation.dart';
import 'package:my_life_graph/features/insights/domain/entities/insight.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('uses mock correlation points only when mock mode is allowed', () async {
    final repository = InsightsRepositoryImpl(
      mockDataSource: const _SentinelMockDataSource(),
      supabaseDataSource: _EmptySupabaseDataSource(),
      allowMockData: true,
    );

    final points = await repository.getCorrelationDataPoints(windowDays: 14);

    expect(points, hasLength(1));
    expect(points.single.values['sleep_hours'], 7.5);
  });

  test('does not substitute mock points for an empty real source', () async {
    final repository = InsightsRepositoryImpl(
      mockDataSource: const _SentinelMockDataSource(),
      supabaseDataSource: _EmptySupabaseDataSource(),
      allowMockData: false,
    );

    final points = await repository.getCorrelationDataPoints(windowDays: 14);

    expect(points, isEmpty);
  });

  test('bounds legacy all-time and oversized windows to 90 days', () async {
    final source = _CapturingSupabaseDataSource();
    final repository = InsightsRepositoryImpl(
      mockDataSource: const _SentinelMockDataSource(),
      supabaseDataSource: source,
      allowMockData: false,
    );

    await repository.getCorrelationDataPoints(windowDays: -1);
    await repository.getCorrelationDataPoints(windowDays: 365);

    expect(source.windowDayRequests, [90, 90]);
  });

  test('propagates a real correlation source failure', () async {
    final repository = InsightsRepositoryImpl(
      mockDataSource: const _SentinelMockDataSource(),
      supabaseDataSource: _ThrowingSupabaseDataSource(),
      allowMockData: false,
    );

    expect(
      repository.getCorrelationDataPoints(windowDays: 14),
      throwsA(isA<StateError>()),
    );
  });

  test('reports missing real correlation configuration as an error', () async {
    final repository = InsightsRepositoryImpl(
      mockDataSource: const _SentinelMockDataSource(),
      allowMockData: false,
    );

    expect(
      repository.getCorrelationDataPoints(windowDays: 14),
      throwsA(isA<StateError>()),
    );
  });

  test('propagates real discovered-insight failures', () async {
    final repository = InsightsRepositoryImpl(
      mockDataSource: const _SentinelMockDataSource(),
      supabaseDataSource: _ThrowingSupabaseDataSource(),
      allowMockData: false,
    );

    expect(repository.getInsights(), throwsA(isA<StateError>()));
  });

  test('reports missing real discovered-insight configuration as an error',
      () async {
    final repository = InsightsRepositoryImpl(
      mockDataSource: const _SentinelMockDataSource(),
      allowMockData: false,
    );

    expect(repository.getInsights(), throwsA(isA<StateError>()));
  });

  test('keeps nullable persisted insight confidence honest', () {
    const mapper = InsightSupabaseRowMapper();
    final withoutConfidence = mapper.fromRow(
      _insightRow(confidence: null),
    );
    final withConfidence = mapper.fromRow(
      _insightRow(confidence: 0.82),
    );

    expect(withoutConfidence.confidence, isNull);
    expect(withoutConfidence.confidenceLabel, 'Confidence not stored');
    expect(withConfidence.confidence, 0.82);
    expect(withConfidence.confidenceLabel, '82% confidence');
  });

  test('rejects malformed persisted insight confidence', () {
    const mapper = InsightSupabaseRowMapper();

    expect(
      () => mapper.fromRow(_insightRow(confidence: '0.82')),
      throwsFormatException,
    );
    expect(
      () => mapper.fromRow(_insightRow(confidence: 1.2)),
      throwsFormatException,
    );
  });

  test('uses local task days for UTC query bounds and deadline buckets', () {
    const offset = Duration(hours: 2);
    final localDates = InsightsLocalDatePolicy(
      localizer: (timestamp) => DateTime.fromMicrosecondsSinceEpoch(
        timestamp.toUtc().microsecondsSinceEpoch + offset.inMicroseconds,
        isUtc: true,
      ),
      localMidnightToUtc: (localDate) => DateTime.utc(
        localDate.year,
        localDate.month,
        localDate.day,
      ).subtract(offset),
    );

    final range = localDates.taskDeadlineUtcRange(
      startDate: '2026-07-01',
      endDate: '2026-07-02',
    );

    expect(range.startInclusive, DateTime.utc(2026, 6, 30, 22));
    expect(range.endExclusive, DateTime.utc(2026, 7, 2, 22));
    expect(
      localDates.taskDeadlineDateKey(DateTime.utc(2026, 7, 1, 21, 59)),
      '2026-07-01',
    );
    expect(
      localDates.taskDeadlineDateKey(DateTime.utc(2026, 7, 1, 22, 1)),
      '2026-07-02',
    );
  });

  test('legacy focus rows fall back to the UTC start day', () {
    const mapper = InsightsCorrelationRowMapper();

    final totals = mapper.focusMinutesByDate(
      [
        {
          'status': 'completed',
          'actual_minutes': 20,
          'started_at': '2026-07-01T08:00:00Z',
          'metadata': {'entry_date': '2026-07-02'},
        },
        {
          'status': 'completed',
          'actual_minutes': 30,
          'started_at': '2026-07-02T00:30:00+02:00',
          'metadata': const <String, dynamic>{},
        },
        {
          'status': 'completed',
          'actual_minutes': 40,
          'started_at': '2026-07-03T23:30:00-02:00',
          'metadata': {'entry_date': 'not-a-date'},
        },
        {
          'status': 'active',
          'actual_minutes': 99,
          'started_at': '2026-07-01T12:00:00Z',
          'metadata': const <String, dynamic>{},
        },
      ],
      startDate: '2026-07-01',
      endDate: '2026-07-04',
    );

    expect(totals, {
      '2026-07-01': 30,
      '2026-07-02': 20,
      '2026-07-04': 40,
    });
  });

  test('planned load includes only confirmed preparation reservations', () {
    const mapper = InsightsCorrelationRowMapper();

    final totals = mapper.plannedMinutesByDate(
      taskRows: const [
        {
          'deadline': '2026-07-21T12:00:00Z',
          'status': 'open',
          'estimated_minutes': 90,
        },
      ],
      scheduleRows: const [
        {
          'weekday': DateTime.monday,
          'starts_at': '09:00:00',
          'ends_at': '10:00:00',
        },
      ],
      preparationBlockRows: const [
        {
          'reservation_state': 'active',
          'local_date': '2026-07-20',
          'planned_minutes': 50,
        },
        {
          'reservation_state': 'proposed',
          'local_date': '2026-07-20',
          'planned_minutes': 90,
        },
        {
          'reservation_state': 'active',
          'local_date': '2026-07-22',
          'planned_minutes': 25,
        },
      ],
      startDate: DateTime(2026, 7, 20),
      windowDays: 2,
      localDates: const InsightsLocalDatePolicy(),
    );

    expect(totals, {
      '2026-07-20': 110,
      '2026-07-21': 90,
    });
  });

  test('paginates through every row beyond one response page', () async {
    const paginator = InsightsQueryPaginator(pageSize: 2);
    final sourceRows = List.generate(5, (index) => {'id': 'row-$index'});
    final requestedRanges = <(int, int)>[];

    final rows = await paginator.load((from, to) async {
      requestedRanges.add((from, to));
      if (from >= sourceRows.length) {
        return const <Map<String, dynamic>>[];
      }
      final end = to + 1 > sourceRows.length ? sourceRows.length : to + 1;
      return sourceRows.sublist(
        from,
        end,
      );
    });

    expect(rows.map((row) => row['id']), [
      'row-0',
      'row-1',
      'row-2',
      'row-3',
      'row-4',
    ]);
    expect(requestedRanges, [(0, 1), (2, 3), (4, 5)]);
  });

  test('accepts the exact pagination bound after an empty sentinel page',
      () async {
    const paginator = InsightsQueryPaginator(pageSize: 2, maxRows: 4);
    final sourceRows = List.generate(4, (index) => {'id': 'row-$index'});
    final requestedRanges = <(int, int)>[];

    final rows = await paginator.load((from, to) async {
      requestedRanges.add((from, to));
      if (from >= sourceRows.length) {
        return const <Map<String, dynamic>>[];
      }
      final end = to + 1 > sourceRows.length ? sourceRows.length : to + 1;
      return sourceRows.sublist(from, end);
    });

    expect(rows, hasLength(4));
    expect(requestedRanges, [(0, 1), (2, 3), (4, 4)]);
  });

  test('fails explicitly when a source exceeds the pagination bound', () async {
    const paginator = InsightsQueryPaginator(pageSize: 2, maxRows: 4);
    final sourceRows = List.generate(5, (index) => {'id': 'row-$index'});

    await expectLater(
      paginator.load((from, to) async {
        if (from >= sourceRows.length) {
          return const <Map<String, dynamic>>[];
        }
        final end = to + 1 > sourceRows.length ? sourceRows.length : to + 1;
        return sourceRows.sublist(from, end);
      }),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('exceeds the 4-row verification limit'),
        ),
      ),
    );
  });
}

Map<String, dynamic> _insightRow({required Object? confidence}) => {
      'id': 'insight-1',
      'title': 'Stored pattern',
      'description': 'A persisted non-causal observation.',
      'confidence': confidence,
      'category': 'Recovery',
      'priority': 'medium',
    };

class _SentinelMockDataSource extends InsightsMockDataSource {
  const _SentinelMockDataSource();

  @override
  Future<List<CorrelationDataPoint>> getCorrelationDataPoints({
    required int windowDays,
  }) async {
    return [
      CorrelationDataPoint(
        date: DateTime(2026, 7, 7),
        values: const {'sleep_hours': 7.5},
      ),
    ];
  }
}

class _EmptySupabaseDataSource extends InsightsSupabaseDataSource {
  _EmptySupabaseDataSource() : super(_testSupabaseClient());

  @override
  Future<List<CorrelationDataPoint>> getCorrelationDataPoints({
    required int windowDays,
  }) async {
    return const [];
  }
}

class _CapturingSupabaseDataSource extends InsightsSupabaseDataSource {
  _CapturingSupabaseDataSource() : super(_testSupabaseClient());

  final windowDayRequests = <int>[];

  @override
  Future<List<CorrelationDataPoint>> getCorrelationDataPoints({
    required int windowDays,
  }) async {
    windowDayRequests.add(windowDays);
    return const [];
  }
}

class _ThrowingSupabaseDataSource extends InsightsSupabaseDataSource {
  _ThrowingSupabaseDataSource() : super(_testSupabaseClient());

  @override
  Future<List<Insight>> getInsights() async {
    throw StateError('real source failed');
  }

  @override
  Future<List<CorrelationDataPoint>> getCorrelationDataPoints({
    required int windowDays,
  }) async {
    throw StateError('real source failed');
  }
}

SupabaseClient _testSupabaseClient() {
  return SupabaseClient('http://localhost:54321', 'test-anon-key');
}
