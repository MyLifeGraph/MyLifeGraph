import 'decision_feedback.dart';

abstract interface class FeedbackRepository {
  Future<DecisionFeedback> create({
    required String requestId,
    required String briefingId,
    required String actionId,
    required DecisionFeedbackType feedbackType,
  });

  Future<List<DecisionFeedback>> listRecent();

  Future<void> delete(String feedbackId);
}
