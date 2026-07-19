import 'deadline_plan.dart';

abstract interface class DeadlinePlanRepository {
  Future<DeadlinePlanFeed> getPlans();

  Future<PreparationWorkload> getWorkload();

  Future<DeadlinePlan> getPlan(String planId);

  Future<DeadlinePlan> propose({
    required String requestId,
    required DeadlinePlanProposalDraft draft,
  });

  Future<DeadlinePlan> confirm({
    required String planId,
    required String requestId,
    required int expectedRevision,
  });

  Future<DeadlinePlan> complete({
    required String planId,
    required String requestId,
    required int expectedRevision,
  });

  Future<DeadlinePlan> cancel({
    required String planId,
    required String requestId,
    required int expectedRevision,
  });
}
