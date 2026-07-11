import '../../../quick_action/domain/quick_check_in.dart';
import '../../domain/entities/dashboard_snapshot.dart';

class DashboardMockDataSource {
  const DashboardMockDataSource({QuickCheckInStore? quickCheckInStore})
      : _quickCheckInStore = quickCheckInStore;

  final QuickCheckInStore? _quickCheckInStore;

  Future<DashboardSnapshot> getSnapshot() async {
    final now = DateTime.now();
    final draft = await _quickCheckInStore?.loadToday(now);
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
      checkInStreakDays: draft == null ? 0 : 1,
      todayPlan: const [],
      scheduleDays: const [],
    );
  }
}
