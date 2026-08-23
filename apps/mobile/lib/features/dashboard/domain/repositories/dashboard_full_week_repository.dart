import '../entities/dashboard_full_week.dart';

abstract interface class DashboardFullWeekRepository {
  Future<DashboardFullWeekProjection> getCurrentWeek();
}

class DashboardFullWeekUnavailableException implements Exception {
  const DashboardFullWeekUnavailableException(this.message);

  final String message;

  @override
  String toString() => message;
}
