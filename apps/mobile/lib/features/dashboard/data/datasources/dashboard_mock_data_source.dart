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
              entryDate: draft.capturedAt,
              mood: draft.mood,
              energy: draft.energy,
              sleepHours: draft.sleepHours,
              stress: draft.stress,
            ),
      checkInStreakDays: draft == null ? 0 : 1,
      todayPlan: const [],
      scheduleDays: const [],
    );
  }
}
