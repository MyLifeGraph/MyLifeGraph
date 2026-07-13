import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/capabilities/app_surface_capabilities.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/supabase/supabase_providers.dart';
import '../../../../core/utils/local_date.dart';
import '../../../quick_action/data/habit_completion_supabase_data_source.dart';
import '../../../snapshots/presentation/providers/snapshot_providers.dart';
import '../../application/weekly_review_proposal_applier.dart';
import '../../data/weekly_review_api_data_source.dart';
import '../../data/weekly_review_repository_impl.dart';
import '../../domain/weekly_review.dart';
import '../../domain/weekly_review_repository.dart';

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
    return WeeklyReviewHabitGatewayImpl(
      HabitCompletionSupabaseDataSource(client),
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
        ref.read(snapshotRefreshServiceProvider).refreshDailyAfterHabitChange(
              targetDate: localDateKey(DateTime.now()),
            ),
  );
});
