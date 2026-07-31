import '../errors/app_exception.dart';

enum ApiFailureKind {
  timeout,
  connection,
  cancelled,
  response,
  unknown,
}

/// Framework-neutral transport evidence retained at the API boundary.
///
/// Feature code may interpret HTTP status and response data according to its
/// own contract without depending on Dio's exception and response types.
class ApiFailure {
  const ApiFailure({
    required this.kind,
    this.statusCode,
    this.responseData,
  });

  final ApiFailureKind kind;
  final int? statusCode;
  final Object? responseData;

  bool get isTimeout => kind == ApiFailureKind.timeout;
  bool get isConnectionFailure => kind == ApiFailureKind.connection;
  bool get isCancelled => kind == ApiFailureKind.cancelled;
  bool get isUnauthorized => statusCode == 401 || statusCode == 403;
  bool get isConflict => statusCode == 409;

  bool get hasClientError =>
      statusCode != null && statusCode! >= 400 && statusCode! < 500;

  bool get hasServerError => statusCode != null && statusCode! >= 500;

  bool get hasAmbiguousMutationOutcome =>
      statusCode == null || statusCode! >= 500;

  @override
  String toString() => 'ApiFailure(kind: $kind, statusCode: $statusCode, '
      'hasResponseData: ${responseData != null})';
}

ApiFailure? apiFailureFrom(Object? error) {
  if (error is ApiFailure) return error;
  if (error is AppException && error.cause is ApiFailure) {
    return error.cause as ApiFailure;
  }
  return null;
}
