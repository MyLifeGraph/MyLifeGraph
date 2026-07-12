import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/network/api_client.dart';
import 'package:my_life_graph/features/briefings/data/feedback_api_data_source.dart';
import 'package:my_life_graph/features/briefings/data/feedback_repository_impl.dart';
import 'package:my_life_graph/features/briefings/domain/decision_feedback.dart';

void main() {
  test('strict feedback parser accepts exact history and rejects additions',
      () {
    final item = DecisionFeedback.fromJson(feedbackJson());
    expect(item.feedbackType, DecisionFeedbackType.tooMuch);
    expect(item.estimatedMinutes, 30);

    final invalid = feedbackJson()..['score'] = -75;
    expect(
      () => DecisionFeedback.fromJson(invalid),
      throwsA(isA<DecisionFeedbackException>()),
    );
  });

  test('repository sends exact create, list, and delete contracts', () async {
    final client = _Client();
    final repository = FeedbackRepositoryImpl(
      api: FeedbackApiDataSource(client),
      accessToken: () async => 'token',
      isLocalDemo: false,
    );

    final created = await repository.create(
      requestId: '22222222-2222-4222-8222-222222222222',
      briefingId: '11111111-1111-4111-8111-111111111111',
      actionId: 'open_task:target',
      feedbackType: DecisionFeedbackType.tooMuch,
    );
    final listed = await repository.listRecent();
    await repository.delete(created.id);

    expect(created.feedbackType, DecisionFeedbackType.tooMuch);
    expect(listed, hasLength(1));
    expect(client.postBody, {
      'request_id': '22222222-2222-4222-8222-222222222222',
      'briefing_id': '11111111-1111-4111-8111-111111111111',
      'action_id': 'open_task:target',
      'feedback_type': 'too_much',
    });
    expect(client.paths, [
      '/v1/feedback',
      '/v1/feedback',
      '/v1/feedback/33333333-3333-4333-8333-333333333333',
    ]);
  });

  test('local demo feedback fails without network use', () async {
    final client = _Client();
    final repository = FeedbackRepositoryImpl(
      api: FeedbackApiDataSource(client),
      accessToken: () async => null,
      isLocalDemo: true,
    );

    expect(repository.listRecent, throwsA(isA<DecisionFeedbackException>()));
    expect(client.paths, isEmpty);
  });
}

Map<String, dynamic> feedbackJson() => {
      'id': '33333333-3333-4333-8333-333333333333',
      'request_id': '22222222-2222-4222-8222-222222222222',
      'briefing_id': '11111111-1111-4111-8111-111111111111',
      'recommendation_id': null,
      'action_id': 'open_task:target',
      'action_kind': 'task',
      'feedback_type': 'too_much',
      'context_mode': 'steady',
      'estimated_minutes': 30,
      'rule_key': 'open_task',
      'created_at': '2026-07-12T08:00:00Z',
    };

class _Client extends ApiClient {
  _Client() : super(Dio());
  final paths = <String>[];
  Map<String, dynamic>? postBody;

  @override
  Future<Map<String, dynamic>> postJson(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  }) async {
    paths.add(path);
    postBody = body;
    return {
      'contract_version': decisionFeedbackContractVersion,
      'feedback': feedbackJson(),
    };
  }

  @override
  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, String>? headers,
  }) async {
    paths.add(path);
    return {
      'contract_version': decisionFeedbackContractVersion,
      'feedback': [feedbackJson()],
    };
  }

  @override
  Future<Map<String, dynamic>> deleteJson(
    String path, {
    Map<String, String>? headers,
  }) async {
    paths.add(path);
    return {
      'contract_version': decisionFeedbackContractVersion,
      'deleted_id': '33333333-3333-4333-8333-333333333333',
    };
  }
}
