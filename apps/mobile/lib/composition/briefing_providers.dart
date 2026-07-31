import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/capabilities/app_surface_capabilities.dart';
import '../core/network/api_client.dart';
import '../core/supabase/supabase_providers.dart';
import '../features/briefings/data/feedback_api_data_source.dart';
import '../features/briefings/data/feedback_repository_impl.dart';
import '../features/briefings/domain/decision_feedback.dart';
import '../features/briefings/domain/feedback_repository.dart';

final feedbackRepositoryProvider = Provider<FeedbackRepository>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  final capabilities = ref.watch(appSurfaceCapabilitiesProvider);
  return FeedbackRepositoryImpl(
    api: FeedbackApiDataSource(apiClient),
    accessToken: () async =>
        ref.read(supabaseClientProvider)?.auth.currentSession?.accessToken,
    isLocalDemo: capabilities.isLocalDemo,
  );
});

final decisionFeedbackProvider =
    FutureProvider.autoDispose<List<DecisionFeedback>>(
  (ref) => ref.watch(feedbackRepositoryProvider).listRecent(),
);
