import 'dart:async';

import 'package:dio/dio.dart';

import '../../../core/config/app_config.dart';
import '../../../core/utils/client_uuid.dart';
import '../domain/coach.dart';
import '../domain/coach_repository.dart';
import 'coach_api_data_source.dart';

typedef CoachAccessTokenProvider = FutureOr<String?> Function();
typedef CoachCredentialsProvider = CoachProviderCredentials? Function();

class CoachRepositoryImpl implements CoachRepository {
  CoachRepositoryImpl({
    required AppConfig config,
    required CoachApiDataSource apiDataSource,
    required CoachAccessTokenProvider accessTokenProvider,
    required bool isLocalDemo,
    required bool canAccessCoachBackend,
    CoachCredentialsProvider? credentialsProvider,
  })  : _config = config,
        _api = apiDataSource,
        _accessTokenProvider = accessTokenProvider,
        _isLocalDemo = isLocalDemo,
        _canAccessCoachBackend = canAccessCoachBackend,
        _credentialsProvider = credentialsProvider ?? (() => null);

  final AppConfig _config;
  final CoachApiDataSource _api;
  final CoachAccessTokenProvider _accessTokenProvider;
  final bool _isLocalDemo;
  final bool _canAccessCoachBackend;
  final CoachCredentialsProvider _credentialsProvider;
  CancelToken? _activeResponseCancellation;

  @override
  Future<CoachCapabilities> getCapabilities() async {
    if (_isLocalDemo) return CoachCapabilities.localDemo();
    _requireRemote();
    final credentials = _credentials();
    return _api.getCapabilities(
      accessToken: await _requireToken(),
      provider: credentials?.provider,
      apiKey: credentials?.apiKey,
    );
  }

  @override
  Future<CoachHistory> getHistory() async {
    if (_isLocalDemo) return CoachHistory.empty();
    _requireRemote();
    return _api.getHistory(accessToken: await _requireToken());
  }

  @override
  Stream<CoachStreamEvent> respond({
    required String requestId,
    required String message,
  }) async* {
    _requireRemote();
    if (!isClientUuid(requestId)) {
      throw const CoachInputException('Coach request id is invalid.');
    }
    final request = CoachRequest(requestId: requestId, message: message);
    final credentials = _credentials();
    final environment = _config.environment.trim().toLowerCase();
    if (credentials == null &&
        const {'staging', 'production'}.contains(environment)) {
      throw const CoachAccessException(
        'Choose a Coach provider and test its API key in Settings first.',
      );
    }
    if (_activeResponseCancellation != null) {
      throw const CoachAccessException(
        'Another Coach response is already in progress.',
      );
    }
    final cancellation = CancelToken();
    _activeResponseCancellation = cancellation;
    try {
      await for (final event in _api.respond(
        accessToken: await _requireToken(),
        request: request,
        cancelToken: cancellation,
        provider: credentials?.provider,
        apiKey: credentials?.apiKey,
      )) {
        if (event is CoachStartedEvent && event.requestId != requestId) {
          throw const CoachContractException(
            'Coach stream request identity is inconsistent.',
          );
        }
        if (event is CoachCompletedEvent &&
            event.response.requestId != requestId) {
          throw const CoachContractException(
            'Coach response request identity is inconsistent.',
          );
        }
        if (event is CoachFailedEvent) {
          throw CoachRemoteException(
            code: event.error.code,
            message: event.error.message,
            retryable: event.error.retryable,
            statusCode: _statusForError(event.error.code),
          );
        }
        yield event;
      }
    } finally {
      if (identical(_activeResponseCancellation, cancellation)) {
        _activeResponseCancellation = null;
      }
    }
  }

  @override
  Future<CoachHistoryDeleteResult> deleteHistory() async {
    _requireRemote();
    final result = await _api.deleteHistory(accessToken: await _requireToken());
    if (!result.deleted) {
      throw const CoachContractException(
        'Coach history was not confirmed as deleted.',
      );
    }
    return result;
  }

  @override
  void cancelActiveResponse() {
    _activeResponseCancellation?.cancel('Coach analysis cancelled.');
  }

  void _requireRemote() {
    if (_isLocalDemo) {
      throw const CoachAccessException(
        'Coach responses are unavailable in local demo mode.',
      );
    }
    if (!_canAccessCoachBackend) {
      throw const CoachAccessException(
        'Coach requires an authenticated synced account.',
      );
    }
  }

  CoachProviderCredentials? _credentials() {
    final credentials = _credentialsProvider();
    if (credentials == null) return null;
    final environment = _config.environment.trim().toLowerCase();
    if (const {'staging', 'production'}.contains(environment)) {
      final uri = Uri.tryParse(_config.aiServiceBaseUrl);
      if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
        throw const CoachAccessException(
          'Coach keys require a configured HTTPS service address.',
        );
      }
    }
    return credentials;
  }

  Future<String> _requireToken() async {
    if (!_config.isSupabaseConfigured) {
      throw const CoachAccessException(
        'Coach requires Supabase configuration.',
      );
    }
    final token = await _accessTokenProvider();
    if (token == null || token.trim().isEmpty) {
      throw const CoachAccessException(
        'Coach requires an authenticated session.',
      );
    }
    return token.trim();
  }
}

int _statusForError(String code) {
  if (code == 'account_limit') return 429;
  if (code == 'in_progress' || code == 'request_conflict') return 409;
  if (code == 'history_deleted') return 410;
  return 503;
}
