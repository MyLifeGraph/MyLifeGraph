import 'dart:async';

import '../../../core/config/app_config.dart';
import '../domain/exam_plan_health.dart';
import '../domain/exam_plan_health_repository.dart';
import 'exam_plan_health_api_data_source.dart';

typedef ExamPlanHealthAccessTokenProvider = FutureOr<String?> Function();

class ExamPlanHealthRepositoryImpl implements ExamPlanHealthRepository {
  const ExamPlanHealthRepositoryImpl({
    required AppConfig config,
    required ExamPlanHealthApiDataSource apiDataSource,
    required ExamPlanHealthAccessTokenProvider accessTokenProvider,
    required bool canUseSyncedPlanner,
  })  : _config = config,
        _api = apiDataSource,
        _accessTokenProvider = accessTokenProvider,
        _canUseSyncedPlanner = canUseSyncedPlanner;

  final AppConfig _config;
  final ExamPlanHealthApiDataSource _api;
  final ExamPlanHealthAccessTokenProvider _accessTokenProvider;
  final bool _canUseSyncedPlanner;

  @override
  Future<ExamPlanHealth> getHealth() async {
    _requireRemote();
    return _api.getHealth(accessToken: await _requireToken());
  }

  @override
  Future<ExamPlanHealthPreview> preview(
    ExamPlanHealthPreviewDraft draft,
  ) async {
    _requireRemote();
    return _api.preview(
      accessToken: await _requireToken(),
      draft: draft,
    );
  }

  void _requireRemote() {
    if (!_canUseSyncedPlanner || !_config.isSupabaseConfigured) {
      throw const ExamPlanHealthContractException(
        'Exam Plan Health requires an authenticated synced account.',
      );
    }
  }

  Future<String> _requireToken() async {
    final token = await _accessTokenProvider();
    if (token == null || token.trim().isEmpty) {
      throw const ExamPlanHealthContractException(
        'Exam Plan Health requires an authenticated session.',
      );
    }
    return token.trim();
  }
}
