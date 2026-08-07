import '../features/dashboard/domain/entities/dashboard_snapshot.dart';
import '../features/quick_action/data/guest_quick_check_in_data_source.dart';
import '../features/quick_action/domain/quick_check_in.dart';

class DashboardGuestSnapshotAdapter {
  const DashboardGuestSnapshotAdapter({QuickCheckInStore? quickCheckInStore})
      : _quickCheckInStore = quickCheckInStore;

  final QuickCheckInStore? _quickCheckInStore;

  Future<DashboardSnapshot> getSnapshot({DateTime? throughLocalDate}) async {
    final now = throughLocalDate ?? DateTime.now();
    final draft = await _quickCheckInStore?.loadToday(now);
    final entries = _quickCheckInStore is GuestQuickCheckInDataSource
        ? await _quickCheckInStore.readAll()
        : <DailyCaptureEntry>[if (draft != null) draft];
    final today = DateTime(now.year, now.month, now.day);
    final latestEntries = entries.where((entry) {
      final date = DateTime.tryParse(entry.entryDate);
      return date != null && !date.isAfter(today);
    }).toList(growable: false)
      ..sort((left, right) => left.entryDate.compareTo(right.entryDate));
    final latest = latestEntries.lastOrNull;
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
      latestCheckIn: latest == null
          ? null
          : DashboardCheckIn(
              entryDate: DateTime.parse(latest.entryDate),
              mood: latest.mood,
              energy: latest.energy,
              sleepHours: latest.sleepHours,
              sleepQuality: latest.sleepQuality,
              stress: latest.stress,
              hasEveningCapture: latest.evening != null,
              hasMorningCapture: latest.morning != null,
              focusBand: latest.evening?.focusBand?.code,
              stressSource: latest.evening?.stressSource?.code,
              stressControllability:
                  latest.evening?.stressControllability?.code,
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
