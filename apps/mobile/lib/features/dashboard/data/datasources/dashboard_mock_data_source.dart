import '../../../quick_action/domain/quick_check_in.dart';
import '../../../quick_action/data/guest_quick_check_in_data_source.dart';
import '../../domain/entities/dashboard_snapshot.dart';

class DashboardMockDataSource {
  const DashboardMockDataSource({QuickCheckInStore? quickCheckInStore})
      : _quickCheckInStore = quickCheckInStore;

  final QuickCheckInStore? _quickCheckInStore;

  Future<DashboardSnapshot> getSnapshot() async {
    final now = DateTime.now();
    final draft = await _quickCheckInStore?.loadToday(now);
    final entries = _quickCheckInStore is GuestQuickCheckInDataSource
        ? await _quickCheckInStore.readAll()
        : <DailyCaptureEntry>[if (draft != null) draft];
    final today = DateTime(now.year, now.month, now.day);
    final byDate = {
      for (final entry in entries) entry.entryDate: entry,
    };
    var expected = draft?.morning != null && draft?.evening != null
        ? today
        : today.subtract(const Duration(days: 1));
    var streak = 0;
    while (true) {
      final entry = byDate[dailyCaptureEntryDate(expected)];
      if (entry?.morning == null || entry?.evening == null) break;
      streak += 1;
      expected = expected.subtract(const Duration(days: 1));
    }
    final checkIns = TodayCheckIns(
      morningSaved: draft?.morning != null,
      eveningSaved: draft?.evening != null,
      completedDaysStreak: streak,
    );
    const currentSource = TodaySourceState(
      status: TodaySourceStatus.current,
    );
    return DashboardSnapshot(
      origin: DashboardOrigin.localDemo,
      loadedAt: now,
      latestCheckIn: draft == null
          ? null
          : DashboardCheckIn(
              entryDate: DateTime.parse(draft.entryDate),
              mood: draft.mood,
              energy: draft.energy,
              sleepHours: draft.sleepHours,
              stress: draft.stress,
              hasEveningCapture: draft.evening != null,
              hasMorningCapture: draft.morning != null,
              focusBand: draft.evening?.focusBand?.code,
              stressSource: draft.evening?.stressSource?.code,
              stressControllability: draft.evening?.stressControllability?.code,
              dayShape: draft.morning?.dayShape?.code,
            ),
      checkInStreakDays: streak,
      todayPlan: const [],
      scheduleDays: const [],
      localDate: today,
      timezone: 'Device time',
      checkIns: checkIns,
      progress: TodayProgress(
        completed:
            (checkIns.morningSaved ? 1 : 0) + (checkIns.eveningSaved ? 1 : 0),
        total: 2,
      ),
      sourceStates: const TodaySourceStates(
        checkIns: currentSource,
        tasks: currentSource,
        habits: currentSource,
        setupCommitments: currentSource,
        preparation: currentSource,
        calendarEvents: currentSource,
        focusSessions: currentSource,
      ),
      isTodayOverview: true,
    );
  }
}
