import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/network/api_client.dart';
import '../domain/account_settings.dart';

class AccountApiDataSource {
  const AccountApiDataSource(this._client);

  static const exportReceiveTimeout = Duration(minutes: 2);

  final ApiClient _client;

  Future<String> updateTimezone({
    required String accessToken,
    required String timezone,
  }) async {
    if (!isValidAccountTimezone(timezone)) {
      throw const AccountSettingsContractException(
        'Choose a supported IANA timezone.',
      );
    }
    late final Map<String, dynamic> json;
    try {
      json = await _client.patchJson(
        '/v1/account/profile',
        headers: _headers(accessToken),
        body: {'timezone': timezone},
      );
    } on AppException catch (error) {
      final cause = error.cause;
      if (cause is DioException && cause.response?.statusCode == 422) {
        throw const AccountTimezoneRejectedException(
          'The backend did not recognize that IANA timezone.',
        );
      }
      if (cause is DioException &&
          ((cause.response?.statusCode ?? 0) >= 500 ||
              cause.response == null)) {
        throw const AccountProfileUpdateOutcomeUnknownException(
          'Account profile update outcome could not be confirmed.',
        );
      }
      rethrow;
    }
    if (json.length != 1 || json['timezone'] is! String) {
      throw const AccountProfileUpdateOutcomeUnknownException(
        'Account profile update returned an invalid result.',
      );
    }
    final returnedTimezone = (json['timezone'] as String).trim();
    if (returnedTimezone != timezone ||
        !isValidAccountTimezone(returnedTimezone)) {
      throw const AccountProfileUpdateOutcomeUnknownException(
        'Account profile update returned a mismatched result.',
      );
    }
    return returnedTimezone;
  }

  Future<AccountExportEnvelope> exportAccount({
    required String accessToken,
  }) async {
    late final Uint8List bytes;
    try {
      bytes = await _client.getBytesWithTimeout(
        '/v1/account/export',
        receiveTimeout: exportReceiveTimeout,
        maxResponseBytes: accountExportV1MaxJsonBytes,
        headers: _headers(accessToken),
      );
    } on ApiResponseTooLargeException {
      throw const AccountExportTooLargeException(
        'Account export exceeds the V1 bounds.',
      );
    } on AppException catch (error) {
      final cause = error.cause;
      if (cause is DioException && cause.response?.statusCode == 413) {
        throw const AccountExportTooLargeException(
          'Account export exceeds the V1 bounds.',
        );
      }
      rethrow;
    }
    return AccountExportEnvelope.fromJsonBytes(bytes);
  }

  Future<void> deleteAccount({required String accessToken}) async {
    try {
      final response = await _client.deleteWithBodyResponse(
        '/v1/account',
        headers: _headers(accessToken),
        body: const {'confirmation': 'DELETE'},
      );
      if (response.statusCode != 204 || response.hasBody) {
        throw const AccountDeletionOutcomeUnknownException(
          'Account deletion did not return the required empty response.',
        );
      }
    } on AppException catch (error) {
      final cause = error.cause;
      if (cause is DioException && cause.response?.statusCode == 403) {
        throw const AccountRecentAuthenticationRequiredException(
          'Recent authentication is required before account deletion.',
        );
      }
      if (cause is DioException &&
          ((cause.response?.statusCode ?? 0) >= 500 ||
              cause.response == null)) {
        throw const AccountDeletionOutcomeUnknownException(
          'Account deletion outcome could not be confirmed.',
        );
      }
      rethrow;
    }
  }

  Map<String, String> _headers(String accessToken) => {
        'Authorization': 'Bearer $accessToken',
      };
}
