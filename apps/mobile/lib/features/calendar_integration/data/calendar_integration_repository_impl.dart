import 'dart:async';
import 'dart:convert';

import '../../../core/config/app_config.dart';
import '../../../core/utils/client_uuid.dart';
import '../domain/calendar_integration.dart';
import '../domain/calendar_integration_repository.dart';
import 'calendar_integration_api_data_source.dart';

typedef CalendarAccessTokenProvider = FutureOr<String?> Function();

class CalendarIntegrationRepositoryImpl
    implements CalendarIntegrationRepository {
  const CalendarIntegrationRepositoryImpl({
    required AppConfig config,
    required CalendarIntegrationApiDataSource apiDataSource,
    required CalendarAccessTokenProvider accessTokenProvider,
    required bool isLocalDemo,
    required bool canUseSyncedIntegration,
  })  : _config = config,
        _api = apiDataSource,
        _accessTokenProvider = accessTokenProvider,
        _isLocalDemo = isLocalDemo,
        _canUseSyncedIntegration = canUseSyncedIntegration;

  final AppConfig _config;
  final CalendarIntegrationApiDataSource _api;
  final CalendarAccessTokenProvider _accessTokenProvider;
  final bool _isLocalDemo;
  final bool _canUseSyncedIntegration;

  @override
  Future<CalendarIntegrationFeed> getIntegration() async {
    if (_isLocalDemo) return CalendarIntegrationFeed.localDemo();
    _requireRemote();
    return _api.getIntegration(accessToken: await _requireToken());
  }

  @override
  Future<CalendarIntegrationFeed> createConnection({
    required String requestId,
    required String sourceLabel,
  }) async {
    _requireRemote();
    _requireRequestId(requestId);
    final label = sourceLabel.trim();
    if (label.isEmpty || label.runes.length > 80 || label != sourceLabel) {
      throw const CalendarIntegrationAccessException(
        'Calendar source label must contain 1 to 80 trimmed characters.',
      );
    }
    final feed = await _api.createConnection(
      accessToken: await _requireToken(),
      requestId: requestId,
      sourceLabel: label,
    );
    if (feed.connection?.status != CalendarConnectionStatus.connected) {
      throw const CalendarIntegrationContractException(
        'Calendar connection response is not connected.',
      );
    }
    return feed;
  }

  @override
  Future<CalendarImportResponse> importCalendar({
    required String connectionId,
    required String requestId,
    required String calendarText,
  }) async {
    _requireRemote();
    _requireConnectionId(connectionId);
    _requireRequestId(requestId);
    final byteLength = utf8.encode(calendarText).length;
    if (byteLength == 0 || byteLength > calendarImportMaxFileBytes) {
      throw const CalendarIntegrationAccessException(
        'Calendar text must contain 1 to 512 KiB of UTF-8 data.',
      );
    }
    final response = await _api.importCalendar(
      accessToken: await _requireToken(),
      connectionId: connectionId,
      requestId: requestId,
      calendarText: calendarText,
    );
    if (response.connection.id != connectionId ||
        !response.connection.isConnected) {
      throw const CalendarIntegrationContractException(
        'Calendar import response does not match its connection.',
      );
    }
    return response;
  }

  @override
  Future<CalendarEventPage> getEvents({
    required String connectionId,
    String? cursor,
  }) async {
    _requireRemote();
    _requireConnectionId(connectionId);
    if (cursor != null &&
        (cursor.isEmpty || cursor.trim() != cursor || cursor.length > 512)) {
      throw const CalendarIntegrationAccessException(
        'Calendar event cursor is invalid.',
      );
    }
    final page = await _api.getEvents(
      accessToken: await _requireToken(),
      connectionId: connectionId,
      cursor: cursor,
    );
    if (page.connectionId != connectionId) {
      throw const CalendarIntegrationContractException(
        'Calendar event response belongs to another connection.',
      );
    }
    return page;
  }

  @override
  Future<CalendarIntegrationFeed> disconnect({
    required String connectionId,
    required String requestId,
  }) async {
    _requireRemote();
    _requireConnectionId(connectionId);
    _requireRequestId(requestId);
    final feed = await _api.disconnect(
      accessToken: await _requireToken(),
      connectionId: connectionId,
      requestId: requestId,
    );
    if (feed.connection?.id != connectionId ||
        feed.connection?.status != CalendarConnectionStatus.disconnected) {
      throw const CalendarIntegrationContractException(
        'Calendar disconnect response is invalid.',
      );
    }
    return feed;
  }

  @override
  Future<CalendarIntegrationFeed> deleteImportedData({
    required String connectionId,
    required String requestId,
  }) async {
    _requireRemote();
    _requireConnectionId(connectionId);
    _requireRequestId(requestId);
    final feed = await _api.deleteImportedData(
      accessToken: await _requireToken(),
      connectionId: connectionId,
      requestId: requestId,
    );
    final connection = feed.connection;
    if (connection?.id != connectionId ||
        connection?.status != CalendarConnectionStatus.disconnected ||
        connection?.lastImport != null ||
        connection?.importedDataDeletedAt == null) {
      throw const CalendarIntegrationContractException(
        'Calendar imported-data deletion response is invalid.',
      );
    }
    return feed;
  }

  void _requireRemote() {
    if (_isLocalDemo) {
      throw const CalendarIntegrationAccessException(
        'Calendar integration is unavailable in local demo mode.',
      );
    }
    if (!_canUseSyncedIntegration) {
      throw const CalendarIntegrationAccessException(
        'Calendar integration requires an authenticated synced account.',
      );
    }
  }

  Future<String> _requireToken() async {
    if (!_config.isSupabaseConfigured) {
      throw const CalendarIntegrationAccessException(
        'Calendar import requires Supabase configuration.',
      );
    }
    final token = await _accessTokenProvider();
    if (token == null || token.trim().isEmpty) {
      throw const CalendarIntegrationAccessException(
        'Calendar import requires an authenticated session.',
      );
    }
    return token.trim();
  }

  void _requireRequestId(String value) {
    if (!isClientUuid(value)) {
      throw const CalendarIntegrationAccessException(
        'Calendar operation request id is invalid.',
      );
    }
  }

  void _requireConnectionId(String value) {
    if (!isCalendarUuid(value)) {
      throw const CalendarIntegrationAccessException(
        'Calendar connection id is invalid.',
      );
    }
  }
}

class CalendarIntegrationAccessException implements Exception {
  const CalendarIntegrationAccessException(this.message);
  final String message;

  @override
  String toString() => 'CalendarIntegrationAccessException: $message';
}
