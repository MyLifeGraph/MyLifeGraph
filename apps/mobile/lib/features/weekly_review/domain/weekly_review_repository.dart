import 'weekly_review.dart';

abstract interface class WeeklyReviewRepository {
  Future<WeeklyReviewFeed> getLatest();

  Future<WeeklyReviewFeed> generate({
    required String periodKey,
    required bool force,
  });
}
