import 'daily_briefing.dart';

abstract interface class BriefingRepository {
  Future<BriefingFeed> getToday();

  Future<BriefingFeed> generateToday({required bool force});
}
