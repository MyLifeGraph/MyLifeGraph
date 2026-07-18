import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/capabilities/app_surface_capabilities.dart';
import 'package:my_life_graph/features/dashboard/data/datasources/deadline_preparation_schedule_data_source.dart';
import 'package:my_life_graph/features/dashboard/domain/entities/dashboard_snapshot.dart';
import 'package:my_life_graph/features/dashboard/domain/entities/deadline_preparation_schedule_block.dart';
import 'package:my_life_graph/features/dashboard/domain/repositories/dashboard_repository.dart';
import 'package:my_life_graph/features/dashboard/presentation/providers/dashboard_providers.dart';

void main() {
  test('dashboard reads only the lightweight displayed-week projection',
      () async {
    final source = _FakePreparationSource(
      blocks: [
        DeadlinePreparationScheduleBlock(
          id: '22222222-2222-4222-8222-222222222222',
          planId: '11111111-1111-4111-8111-111111111111',
          planTitle: 'Algorithms exam',
          revision: 1,
          sequence: 1,
          startsAt: DateTime.parse('2026-07-20T08:00:00Z'),
          endsAt: DateTime.parse('2026-07-20T08:50:00Z'),
          plannedMinutes: 50,
        ),
      ],
    );
    final container = _container(source);
    addTearDown(container.dispose);

    final snapshot = await container.read(dashboardSnapshotProvider.future);

    expect(source.calls, 1);
    expect(source.startDate, DateTime(2026, 7, 20));
    expect(source.endDate, DateTime(2026, 7, 26));
    expect(
      snapshot.scheduleDays
          .expand((day) => day.events)
          .where((event) => event.isDeadlinePreparation),
      hasLength(1),
    );
  });

  test('projection failure preserves the base snapshot and marks only overlay',
      () async {
    final source = _FakePreparationSource(error: StateError('bad projection'));
    final container = _container(source);
    addTearDown(container.dispose);

    final snapshot = await container.read(dashboardSnapshotProvider.future);

    expect(snapshot.scheduleDays.first.events.single.title, 'Existing class');
    expect(snapshot.preparationScheduleError, contains('could not be loaded'));
  });
}

ProviderContainer _container(DeadlinePreparationScheduleDataSource source) =>
    ProviderContainer(
      overrides: [
        appSurfaceCapabilitiesProvider.overrideWithValue(
          const AppSurfaceCapabilities(
            isLocalDemo: false,
            canUseSyncedHabits: true,
            canUseDeadlinePlanner: true,
          ),
        ),
        dashboardRepositoryProvider.overrideWithValue(
          _FakeDashboardRepository(_snapshot()),
        ),
        deadlinePreparationScheduleDataSourceProvider.overrideWithValue(source),
      ],
    );

DashboardSnapshot _snapshot() => DashboardSnapshot(
      origin: DashboardOrigin.account,
      loadedAt: DateTime(2026, 7, 20, 9),
      latestCheckIn: null,
      checkInStreakDays: 0,
      todayPlan: const [],
      scheduleDays: List.generate(7, (index) {
        final date = DateTime(2026, 7, 20 + index);
        return ScheduleDay(
          label: 'Day ${index + 1}',
          dateLabel: 'Jul ${20 + index}',
          date: date,
          events: index == 0
              ? const [ScheduleEvent(title: 'Existing class', time: '09:00')]
              : const [],
        );
      }),
    );

class _FakeDashboardRepository implements DashboardRepository {
  const _FakeDashboardRepository(this.snapshot);

  final DashboardSnapshot snapshot;

  @override
  Future<DashboardSnapshot> getSnapshot() async => snapshot;
}

class _FakePreparationSource implements DeadlinePreparationScheduleDataSource {
  _FakePreparationSource({this.blocks = const [], this.error});

  final List<DeadlinePreparationScheduleBlock> blocks;
  final Object? error;
  int calls = 0;
  DateTime? startDate;
  DateTime? endDate;

  @override
  Future<List<DeadlinePreparationScheduleBlock>> getActiveBlocksForWeek({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    calls++;
    this.startDate = startDate;
    this.endDate = endDate;
    if (error case final error?) throw error;
    return blocks;
  }
}
