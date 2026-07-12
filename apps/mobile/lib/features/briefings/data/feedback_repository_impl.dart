import '../domain/decision_feedback.dart';
import '../domain/feedback_repository.dart';
import 'feedback_api_data_source.dart';

class FeedbackRepositoryImpl implements FeedbackRepository {
  const FeedbackRepositoryImpl({
    required FeedbackApiDataSource? api,
    required Future<String?> Function() accessToken,
    required bool isLocalDemo,
  })  : _api = api,
        _accessToken = accessToken,
        _isLocalDemo = isLocalDemo;

  final FeedbackApiDataSource? _api;
  final Future<String?> Function() _accessToken;
  final bool _isLocalDemo;

  @override
  Future<DecisionFeedback> create({
    required String requestId,
    required String briefingId,
    required String actionId,
    required DecisionFeedbackType feedbackType,
  }) async {
    final context = await _context();
    return context.api.create(
      accessToken: context.token,
      requestId: requestId,
      briefingId: briefingId,
      actionId: actionId,
      feedbackType: feedbackType,
    );
  }

  @override
  Future<List<DecisionFeedback>> listRecent() async {
    final context = await _context();
    return context.api.listRecent(accessToken: context.token);
  }

  @override
  Future<void> delete(String feedbackId) async {
    final context = await _context();
    await context.api
        .delete(accessToken: context.token, feedbackId: feedbackId);
  }

  Future<({FeedbackApiDataSource api, String token})> _context() async {
    if (_isLocalDemo) {
      throw const DecisionFeedbackException(
        'Feedback is unavailable in local demo mode.',
      );
    }
    final api = _api;
    final token = await _accessToken();
    if (api == null || token == null || token.isEmpty) {
      throw const DecisionFeedbackException(
        'Feedback requires an authenticated account.',
      );
    }
    return (api: api, token: token);
  }
}
