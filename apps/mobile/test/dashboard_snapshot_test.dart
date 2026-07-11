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
            'metadata': {
              'capture_version': 'daily-capture-v2',
              'captures': {
                'evening': {
                  'focus_band': '30_to_60_minutes',
                  'stress_source': 'private_emotional',
                  'stress_controllability': 'hardly_controllable',
                },
                'morning': {'day_shape': 'constrained'},
              },
            },
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
      expect(snapshot.latestCheckIn?.hasEveningCapture, isTrue);
      expect(snapshot.latestCheckIn?.hasMorningCapture, isTrue);
      expect(snapshot.latestCheckIn?.focusBand, '30_to_60_minutes');
      expect(snapshot.latestCheckIn?.stressSource, 'private_emotional');
      expect(
        snapshot.latestCheckIn?.stressControllability,
        'hardly_controllable',
      );
      expect(snapshot.latestCheckIn?.dayShape, 'constrained');
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
    final entryDate = dailyCaptureEntryDate(capturedAt);
    final source = DashboardMockDataSource(
      quickCheckInStore: _MemoryCaptureStore(
        DailyCaptureEntry(
          entryDate: entryDate,
          evening: EveningShutdownDraft(
            captureId: 'local-evening',
            entryDate: entryDate,
            capturedAt: capturedAt,
            mood: 2,
            energy: 9,
            stress: 8,
            stressSource: StressSource.privateEmotional,
            stressControllability: StressControllability.hardlyControllable,
            focusBand: FocusBand.thirtyToSixtyMinutes,
            mainFriction: MainFriction.emotionalLoad,
            tomorrowPriority: 'Protect tomorrow',
          ),
          morning: MorningCalibrationDraft(
            captureId: 'local-morning',
            entryDate: entryDate,
            capturedAt: capturedAt,
            sleepHours: 5.5,
            energy: 4,
            dayShape: DayShape.constrained,
          ),
        ),
      ),
    );

    final snapshot = await source.getSnapshot();

    expect(snapshot.origin, DashboardOrigin.localDemo);
    expect(snapshot.latestCheckIn?.mood, 2);
    expect(snapshot.latestCheckIn?.energy, 4);
    expect(snapshot.latestCheckIn?.sleepHours, 5.5);
    expect(snapshot.latestCheckIn?.stress, 8);
    expect(snapshot.latestCheckIn?.focusBand, '30_to_60_minutes');
    expect(snapshot.latestCheckIn?.dayShape, 'constrained');
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

class _MemoryCaptureStore implements QuickCheckInStore {
  const _MemoryCaptureStore(this.value);

  final DailyCaptureEntry value;

  @override
  QuickCheckInSaveTarget get target => QuickCheckInSaveTarget.guest;

  @override
  Future<DailyCaptureEntry?> loadToday(DateTime today) async => value;

  @override
  Future<void> saveEvening(EveningShutdownDraft draft) async {}

  @override
  Future<void> saveMorning(MorningCalibrationDraft draft) async {}
}
