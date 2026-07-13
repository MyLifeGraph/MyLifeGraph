import 'dart:async';

import 'package:dio/dio.dart';

import '../../../core/config/app_config.dart';
import '../../../core/utils/client_uuid.dart';
import '../domain/coach.dart';
import '../domain/coach_repository.dart';
import 'coach_api_data_source.dart';

typedef CoachAccessTokenProvider = FutureOr<String?> Function();

class CoachRepositoryImpl implements CoachRepository {
  CoachRepositoryImpl({
    required AppConfig config,
    required CoachApiDataSource apiDataSource,
    required CoachAccessTokenProvider accessTokenProvider,
    required bool isLocalDemo,
    required bool canAccessCoachBackend,
  })  : _config = config,
        _api = apiDataSource,
        _accessTokenProvider = accessTokenProvider,
        _isLocalDemo = isLocalDemo,
        _canAccessCoachBackend = canAccessCoachBackend;

  final AppConfig _config;
  final CoachApiDataSource _api;
  final CoachAccessTokenProvider _accessTokenProvider;
  final bool _isLocalDemo;
  final bool _canAccessCoachBackend;
  CancelToken? _activeResponseCancellation;

  @override
  Future<CoachCapabilities> getCapabilities() async {
    if (_isLocalDemo) return CoachCapabilities.localDemo();
    _requireRemote();
    return _api.getCapabilities(accessToken: await _requireToken());
  }

  @override
  Future<CoachHistory> getHistory() async {
    if (_isLocalDemo) return CoachHistory.empty();
    _requireRemote();
    return _api.getHistory(accessToken: await _requireToken());
  }

  @override
  Future<CoachMemorySelection> getMemories() async {
    if (_isLocalDemo) return CoachMemorySelection.empty();
    _requireRemote();
    return _api.getMemories(accessToken: await _requireToken());
  }

  @override
  Future<CoachResponse> respond({
    required String requestId,
    required String message,
    required Duration receiveTimeout,
  }) async {
    _requireRemote();
    if (!isClientUuid(requestId)) {
      throw const CoachInputException('Coach request id is invalid.');
    }
    if (receiveTimeout < const Duration(seconds: 5) ||
        receiveTimeout > const Duration(seconds: 130)) {
      throw const CoachInputException('Coach response timeout is invalid.');
    }
    final request = CoachRequest(requestId: requestId, message: message);
    if (_activeResponseCancellation != null) {
      throw const CoachAccessException(
        'Another Coach response is already in progress.',
      );
    }
    final cancellation = CancelToken();
    _activeResponseCancellation = cancellation;
    try {
      final response = await _api.respond(
        accessToken: await _requireToken(),
        request: request,
        receiveTimeout: receiveTimeout,
        cancelToken: cancellation,
      );
      if (response.requestId != requestId) {
        throw const CoachContractException(
          'Coach response request identity is inconsistent.',
        );
      }
      return response;
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
  Future<CoachMemorySelection> selectMemory(String memoryId) async {
    _requireMemoryId(memoryId);
    _requireRemote();
    final selection = await _api.selectMemory(
      accessToken: await _requireToken(),
      memoryId: memoryId,
    );
    _requireMemorySelection(selection, memoryId, selected: true);
    return selection;
  }

  @override
  Future<CoachMemorySelection> deselectMemory(String memoryId) async {
    _requireMemoryId(memoryId);
    _requireRemote();
    final selection = await _api.deselectMemory(
      accessToken: await _requireToken(),
      memoryId: memoryId,
    );
    _requireMemorySelection(selection, memoryId, selected: false);
    return selection;
  }

  @override
  void cancelActiveResponse() {
    _activeResponseCancellation?.cancel('Coach page disposed.');
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

  void _requireMemoryId(String memoryId) {
    if (!RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    ).hasMatch(memoryId)) {
      throw const CoachInputException('Coach memory id is invalid.');
    }
  }

  void _requireMemorySelection(
    CoachMemorySelection selection,
    String memoryId, {
    required bool selected,
  }) {
    final matches = selection.memories.where(
      (memory) => memory.id == memoryId.toLowerCase(),
    );
    if (matches.length != 1 || matches.single.selected != selected) {
      throw const CoachContractException(
        'Coach memory selection response is inconsistent.',
      );
    }
  }
}
