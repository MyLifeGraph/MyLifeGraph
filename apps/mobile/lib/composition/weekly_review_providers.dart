import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/capabilities/app_surface_capabilities.dart';
import '../core/config/app_config.dart';
import '../core/network/api_client.dart';
import '../core/supabase/supabase_providers.dart';
import '../features/quick_action/data/habit_completion_supabase_data_source.dart';
import '../features/quick_action/domain/habit_v1.dart';
import '../features/weekly_review/application/weekly_review_proposal_applier.dart';
import '../features/weekly_review/data/weekly_review_api_data_source.dart';
import '../features/weekly_review/data/weekly_review_repository_impl.dart';
import '../features/weekly_review/domain/weekly_review.dart';
import '../features/weekly_review/domain/weekly_review_repository.dart';
import 'profile_local_date_providers.dart';
import 'projection_refresh_providers.dart';

class _SupabaseWeeklyReviewHabitGateway implements WeeklyReviewHabitGateway {
  const _SupabaseWeeklyReviewHabitGateway(this._dataSource);

  final HabitCompletionSupabaseDataSource _dataSource;

  @override
  Future<HabitV1> fetchOwnedHabit(String habitId) =>
      _dataSource.fetchOwnedHabit(habitId);

  @override
  Future<HabitV1> updateHabit({
    required HabitV1 habit,
    required String title,
    String? description,
    required HabitCadence cadence,
  }) =>
      _dataSource.updateHabit(
        habit: habit,
        title: title,
        description: description,
        cadence: cadence,
      );

  @override
  Future<HabitV1> setHabitLifecycle({
    required HabitV1 habit,
    required HabitLifecycle lifecycle,
  }) =>
      _dataSource.setHabitLifecycle(habit: habit, lifecycle: lifecycle);
}

final weeklyReviewApiDataSourceProvider = Provider<WeeklyReviewApiDataSource>(
  (ref) => WeeklyReviewApiDataSource(ref.watch(apiClientProvider)),
);

final weeklyReviewAccessTokenProvider =
    Provider<WeeklyReviewAccessTokenProvider>(
  (ref) =>
      () => ref.read(supabaseClientProvider)?.auth.currentSession?.accessToken,
);

final weeklyReviewRepositoryProvider = Provider<WeeklyReviewRepository>((ref) {
  final capabilities = ref.watch(appSurfaceCapabilitiesProvider);
  return WeeklyReviewRepositoryImpl(
    config: ref.watch(appConfigProvider),
    apiDataSource: ref.watch(weeklyReviewApiDataSourceProvider),
    accessTokenProvider: ref.watch(weeklyReviewAccessTokenProvider),
    isLocalDemo: capabilities.isLocalDemo,
  );
});

final latestWeeklyReviewProvider = FutureProvider.autoDispose<WeeklyReviewFeed>(
  (ref) => ref.watch(weeklyReviewRepositoryProvider).getLatest(),
);

final weeklyReviewHabitGatewayProvider = Provider<WeeklyReviewHabitGateway>(
  (ref) {
    final client = ref.watch(supabaseClientProvider);
    if (client == null) {
      throw StateError('Synced habits are unavailable.');
    }
    final profileDate = ref.watch(profileLocalDateSourceProvider);
    return _SupabaseWeeklyReviewHabitGateway(
      HabitCompletionSupabaseDataSource(
        client,
        todayProvider: profileDate.today,
      ),
    );
  },
);

final weeklyReviewProposalApplierProvider =
    Provider<WeeklyReviewProposalApplier>((ref) {
  return WeeklyReviewProposalApplier(
    habitGateway: ref.watch(weeklyReviewHabitGatewayProvider),
    loadLatestReview: () =>
        ref.read(weeklyReviewRepositoryProvider).getLatest(),
    refreshDailySnapshot: () =>
        ref.read(projectionRefreshCoordinatorProvider).habitDefinitionChanged(
              targetDate: ref.read(profileLocalDateSourceProvider).todayKey(),
            ),
  );
});
