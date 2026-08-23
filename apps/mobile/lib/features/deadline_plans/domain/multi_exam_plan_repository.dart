import 'multi_exam_plan.dart';

abstract interface class MultiExamPlanRepository {
  Future<MultiExamPlanFeed> getBalances();

  Future<MultiExamPlanBatch> getBalance(String balanceId);

  Future<MultiExamPlanProposalResult> propose({
    required String requestId,
    required MultiExamPlanProposalDraft draft,
  });

  Future<MultiExamPlanBatch> confirm({
    required String balanceId,
    required String requestId,
    required int expectedRevision,
  });

  Future<MultiExamPlanBatch> cancel({
    required String balanceId,
    required String requestId,
    required int expectedRevision,
  });
}
