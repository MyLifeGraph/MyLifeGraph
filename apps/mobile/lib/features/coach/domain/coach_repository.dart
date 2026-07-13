import 'coach.dart';

abstract interface class CoachRepository {
  Future<CoachCapabilities> getCapabilities();

  Future<CoachHistory> getHistory();

  Future<CoachMemorySelection> getMemories();

  Future<CoachResponse> respond({
    required String requestId,
    required String message,
    required Duration receiveTimeout,
  });

  Future<CoachHistoryDeleteResult> deleteHistory();

  Future<CoachMemorySelection> selectMemory(String memoryId);

  Future<CoachMemorySelection> deselectMemory(String memoryId);

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
  });

  final String code;
  final String message;
  final bool retryable;
  final int statusCode;

  bool get preservesRequestIdentity =>
      statusCode == 409 && (code == 'in_progress' || retryable);

  bool get isRateLimited =>
      statusCode == 429 ||
      const {
        'rate_limited',
        'account_limit',
        'daily_limit',
        'usage_limit',
      }.contains(code);

  @override
  String toString() => 'CoachRemoteException($code, $statusCode)';
}
