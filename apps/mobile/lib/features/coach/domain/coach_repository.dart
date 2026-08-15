import 'coach.dart';

class CoachProviderCredentials {
  const CoachProviderCredentials({
    required this.provider,
    required this.apiKey,
  });

  final CoachProviderName provider;
  final String apiKey;
}

abstract interface class CoachRepository {
  Future<CoachCapabilities> getCapabilities();

  Future<CoachHistory> getHistory();

  Stream<CoachStreamEvent> respond({
    required String requestId,
    required String message,
  });

  Future<CoachHistoryDeleteResult> deleteHistory();

  void cancelActiveResponse();
}

class CoachAccessException implements Exception {
  const CoachAccessException(this.message);
  final String message;

  @override
  String toString() => 'CoachAccessException: $message';
}

class CoachRemoteException implements Exception {
  const CoachRemoteException({
    required this.code,
    required this.message,
    required this.retryable,
    required this.statusCode,
    this.timedOut = false,
  });

  final String code;
  final String message;
  final bool retryable;
  final int statusCode;
  final bool timedOut;

  bool get preservesRequestIdentity =>
      statusCode == 409 && (code == 'in_progress' || retryable) ||
      code == 'network_error' && retryable;

  bool get isRateLimited =>
      statusCode == 429 ||
      const {
        'rate_limited',
        'account_limit',
        'daily_limit',
        'usage_limit',
      }.contains(code);
}
