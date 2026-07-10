import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/features/dashboard/data/datasources/dashboard_mock_data_source.dart';
import 'package:my_life_graph/features/dashboard/data/datasources/dashboard_supabase_data_source.dart';
import 'package:my_life_graph/features/dashboard/data/repositories/dashboard_repository_impl.dart';
import 'package:my_life_graph/features/dashboard/domain/entities/dashboard_snapshot.dart';
import 'package:my_life_graph/features/quick_action/domain/quick_check_in.dart';

void main() {
  group('DashboardSnapshotMapper', () {
    const mapper = DashboardSnapshotMapper();
    final loadedAt = DateTime(2026, 7, 10, 12);

    test('preserves daily signals without score conversion', () {
      final snapshot = mapper.map(
        dailyLogs: [
          {
            'entry_date': '2026-07-10',
            'mood_score': 2,
            'energy_level': 9,
            'sleep_hours': 5.5,
            'stress_level': 8,
            'focus_minutes': 47,
            'steps': 1111,
            'activity_level': 3,
            'screen_time_hours': 6.25,
          },
        ],
        taskRows: [
          {
            'id': 'task-1',
            'title': 'Exact task',
            'deadline': '2026-07-11T09:00:00Z',
            'priority': 'high',
            'status': 'done',
          },
          {
            'id': 'task-cancelled',
            'title': 'Cancelled task',
            'priority': 'low',
            'status': 'cancelled',
          },
          {
            'id': 'task-archived',
            'title': 'Archived task',
            'priority': 'low',
            'status': 'archived',
          },
        ],
        scheduleRows: [
          {
            'title': 'Exact commitment',
            'weekday': 5,
            'starts_at': '10:00',
            'ends_at': '11:30',
            'location': 'Office',
          },
        ],
        loadedAt: loadedAt,
      );

      expect(snapshot.origin, DashboardOrigin.account);
      expect(snapshot.loadedAt, loadedAt);
      expect(snapshot.checkInStreakDays, 1);
      expect(snapshot.latestCheckIn?.mood, 2);
      expect(snapshot.latestCheckIn?.energy, 9);
      expect(snapshot.latestCheckIn?.sleepHours, 5.5);
      expect(snapshot.latestCheckIn?.stress, 8);
      expect(snapshot.latestCheckIn?.focusMinutes, 47);
      expect(snapshot.latestCheckIn?.steps, 1111);
      expect(snapshot.latestCheckIn?.activityLevel, 3);
      expect(snapshot.latestCheckIn?.screenTimeHours, 6.25);
      expect(snapshot.todayPlan.single.priority, 'high');
      expect(snapshot.todayPlan.single.isCompleted, isTrue);
      expect(snapshot.scheduleDays[4].events.single.title, 'Exact commitment');
      expect(snapshot.scheduleDays[4].events.single.time, '10:00-11:30');
    });

    test('keeps missing daily data empty instead of inventing zero values', () {
      final snapshot = mapper.map(
        dailyLogs: const [],
        taskRows: const [],
        scheduleRows: const [],
        loadedAt: loadedAt,
      );

      expect(snapshot.latestCheckIn, isNull);
      expect(snapshot.checkInStreakDays, 0);
      expect(snapshot.todayPlan, isEmpty);
      expect(snapshot.scheduleDays.expand((day) => day.events), isEmpty);
    });
  });

  test('local dashboard reads exact guest check-in values', () async {
    final capturedAt = DateTime.now();
    final source = DashboardMockDataSource(
      quickCheckInStore: _MemoryCheckInStore(
        QuickCheckInDraft(
          captureId: 'local-dashboard',
          capturedAt: capturedAt,
          mood: 2,
          energy: 9,
          sleepHours: 5.5,
          stress: 8,
          contextNote: '',
        ),
      ),
    );

    final snapshot = await source.getSnapshot();

    expect(snapshot.origin, DashboardOrigin.localDemo);
    expect(snapshot.latestCheckIn?.mood, 2);
    expect(snapshot.latestCheckIn?.energy, 9);
    expect(snapshot.latestCheckIn?.sleepHours, 5.5);
    expect(snapshot.latestCheckIn?.stress, 8);
    expect(snapshot.todayPlan, isEmpty);
  });

  test('real dashboard without Supabase throws instead of returning demo', () {
    final repository = DashboardRepositoryImpl(
      mockDataSource: const DashboardMockDataSource(),
      allowMockData: false,
    );

    expect(
      repository.getSnapshot,
      throwsA(isA<DashboardUnavailableException>()),
    );
  });
}

class _MemoryCheckInStore implements QuickCheckInStore {
  const _MemoryCheckInStore(this.value);

  final QuickCheckInDraft value;

  @override
  QuickCheckInSaveTarget get target => QuickCheckInSaveTarget.guest;

  @override
  Future<QuickCheckInDraft?> loadToday(DateTime today) async => value;

  @override
  Future<void> save(QuickCheckInDraft draft) async {}
}
