import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/errors/app_exception.dart';
import 'package:my_life_graph/core/network/api_client.dart';
import 'package:my_life_graph/core/network/api_failure.dart';
import 'package:my_life_graph/features/learning/data/learning_api_data_source.dart';
import 'package:my_life_graph/features/learning/domain/learning_preferences.dart';

const _requestId = '11111111-1111-4111-8111-111111111111';

void main() {
  test('preference conflict remains a feature-owned typed outcome', () async {
    final dataSource = LearningApiDataSource(
      _FailingApiClient(
        const ApiFailure(
          kind: ApiFailureKind.response,
          statusCode: 409,
        ),
      ),
    );

    await expectLater(
      dataSource.updatePreferences(
        accessToken: 'token',
        request: LearningPreferencesUpdate(
          requestId: _requestId,
          expectedRevision: 2,
          focusReflectionPromptEnabled: true,
          personalPatternAnalysisEnabled: true,
          learnedFocusPlanningEnabled: false,
        ),
      ),
      throwsA(isA<LearningConflictException>()),
    );
  });

  test('reflection timeout remains an explicit unknown mutation outcome',
      () async {
    final dataSource = LearningApiDataSource(
      _FailingApiClient(
        const ApiFailure(kind: ApiFailureKind.timeout),
      ),
    );

    await expectLater(
      dataSource.clearFocusReflections(
        accessToken: 'token',
        request: FocusReflectionHistoryClearRequest(
          requestId: _requestId,
          expectedRevision: 2,
        ),
      ),
      throwsA(isA<LearningOutcomeUnknownException>()),
    );
  });
}

class _FailingApiClient extends ApiClient {
  _FailingApiClient(this.failure) : super(Dio());

  final ApiFailure failure;

  @override
  Future<Map<String, dynamic>> patchJson(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  }) {
    throw AppException('Network request failed', cause: failure);
  }

  @override
  Future<Map<String, dynamic>> postJson(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  }) {
    throw AppException('Network request failed', cause: failure);
  }
}
