import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/capabilities/app_surface_capabilities.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/supabase/supabase_providers.dart';
import '../../data/briefing_api_data_source.dart';
import '../../data/briefing_repository_impl.dart';
import '../../domain/briefing_repository.dart';
import '../../domain/daily_briefing.dart';

final briefingApiDataSourceProvider = Provider<BriefingApiDataSource>(
  (ref) => BriefingApiDataSource(ref.watch(apiClientProvider)),
);

final briefingAccessTokenProvider = Provider<BriefingAccessTokenProvider>(
  (ref) =>
      () => ref.read(supabaseClientProvider)?.auth.currentSession?.accessToken,
);

final briefingRepositoryProvider = Provider<BriefingRepository>((ref) {
  final capabilities = ref.watch(appSurfaceCapabilitiesProvider);
  return BriefingRepositoryImpl(
    config: ref.watch(appConfigProvider),
    apiDataSource: ref.watch(briefingApiDataSourceProvider),
    accessTokenProvider: ref.watch(briefingAccessTokenProvider),
    isLocalDemo: capabilities.isLocalDemo,
  );
});

final todayBriefingProvider = FutureProvider.autoDispose<BriefingFeed>(
  (ref) => ref.watch(briefingRepositoryProvider).getToday(),
);
