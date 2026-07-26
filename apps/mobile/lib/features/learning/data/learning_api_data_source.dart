import 'package:dio/dio.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/network/api_client.dart';
import '../domain/learning_preferences.dart';

class LearningApiDataSource {
  const LearningApiDataSource(this._client);

  final ApiClient _client;

  Future<LearningPreferences> getPreferences({
    required String accessToken,
  }) async {
    final json = await _client.getJson(
      '/v1/learning/preferences',
      headers: _headers(accessToken),
    );
    return LearningPreferences.fromJson(json);
  }

  Future<LearningPreferences> updatePreferences({
    required String accessToken,
    required LearningPreferencesUpdate request,
  }) async {
    try {
      final json = await _client.patchJson(
        '/v1/learning/preferences',
        headers: _headers(accessToken),
        body: request.toJson(),
      );
      final result = LearningPreferences.fromJson(json);
      if (result.revision != request.expectedRevision + 1 ||
          result.focusReflectionPromptEnabled !=
              request.focusReflectionPromptEnabled ||
          result.personalPatternAnalysisEnabled !=
              request.personalPatternAnalysisEnabled ||
          result.learnedFocusPlanningEnabled !=
              request.learnedFocusPlanningEnabled) {
        throw const LearningOutcomeUnknownException(
          'Personal learning update returned a mismatched result.',
        );
      }
      return result;
    } on AppException catch (error) {
      _mapMutationError(error);
    }
  }

  Future<FocusReflectionHistoryClearResult> clearFocusReflections({
    required String accessToken,
    required FocusReflectionHistoryClearRequest request,
  }) async {
    try {
      final json = await _client.postJson(
        '/v1/learning/focus-reflections/clear',
        headers: _headers(accessToken),
        body: request.toJson(),
      );
      final result = FocusReflectionHistoryClearResult.fromJson(json);
      if (result.revision != request.expectedRevision) {
        throw const LearningOutcomeUnknownException(
          'Focus reflection clear returned a mismatched result.',
        );
      }
      return result;
    } on AppException catch (error) {
      _mapMutationError(error);
    }
  }

  Never _mapMutationError(AppException error) {
    final cause = error.cause;
    if (cause is DioException && cause.response?.statusCode == 409) {
      throw const LearningConflictException(
        'Personal learning settings changed since they were loaded.',
      );
    }
    if (cause is DioException &&
        (cause.response == null || (cause.response?.statusCode ?? 0) >= 500)) {
      throw const LearningOutcomeUnknownException(
        'Personal learning mutation outcome could not be confirmed.',
      );
    }
    throw error;
  }

  Map<String, String> _headers(String token) => {
        'Authorization': 'Bearer $token',
      };
}
