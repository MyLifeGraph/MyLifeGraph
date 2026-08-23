import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/capabilities/app_surface_capabilities.dart';
import '../core/config/app_config.dart';
import '../core/network/api_client.dart';
import '../core/supabase/supabase_providers.dart';
import '../features/weekly_review/data/weekly_review_api_data_source.dart';
import '../features/weekly_review/data/weekly_review_repository_impl.dart';
import '../features/weekly_review/domain/weekly_review.dart';
import '../features/weekly_review/domain/weekly_review_repository.dart';

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
