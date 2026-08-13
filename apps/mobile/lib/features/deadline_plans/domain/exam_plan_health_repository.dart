import 'exam_plan_health.dart';

abstract interface class ExamPlanHealthRepository {
  Future<ExamPlanHealth> getHealth();

  Future<ExamPlanHealthPreview> preview(ExamPlanHealthPreviewDraft draft);
}
