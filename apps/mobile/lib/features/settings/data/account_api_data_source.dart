import 'dart:typed_data';

import '../../../core/contracts/strict_contract.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_failure.dart';
import '../../../core/utils/client_uuid.dart';
import '../domain/account_settings.dart';

class AccountApiDataSource {
  AccountApiDataSource(this._client);

  static const exportReceiveTimeout = Duration(minutes: 2);

  final ApiClient _client;
  final Map<String, String> _pendingRequestIds = {};

  Future<AccountTimezoneWrite> updateTimezone({
    required String accessToken,
    required int expectedRevision,
    required String timezone,
  }) async {
    if (!isValidAccountTimezone(timezone)) {
      throw const AccountSettingsContractException(
        'Choose a supported IANA timezone.',
      );
    }
    final requestKey = 'timezone:$expectedRevision:$timezone';
    final requestId = _pendingRequestIds.putIfAbsent(requestKey, newClientUuid);
    late final Map<String, dynamic> json;
    try {
      json = await _client.patchJson(
        '/v1/account/profile',
        headers: _headers(accessToken),
        body: {
          'contract_version': 'account-profile-update-v2',
          'request_id': requestId,
          'expected_revision': expectedRevision,
          'timezone': timezone,
        },
      );
    } on AppException catch (error) {
      final failure = apiFailureFrom(error);
      if (failure?.statusCode == 422) {
        throw const AccountTimezoneRejectedException(
          'The backend did not recognize that IANA timezone.',
        );
      }
      if (failure?.statusCode == 409) {
        throw const AccountSettingConflictException(
          'Timezone changed. Reload your account before saving.',
        );
      }
      if (failure != null && failure.hasAmbiguousMutationOutcome) {
        throw const AccountProfileUpdateOutcomeUnknownException(
          'Account profile update outcome could not be confirmed.',
        );
      }
      rethrow;
    }
    Never invalidProfile() =>
        throw const AccountProfileUpdateOutcomeUnknownException(
          'Account profile update returned an invalid result.',
        );
    requireStrictKeys(
      json,
      requiredKeys: const {
        'contract_version',
        'timezone',
        'revision',
        'updated_at',
        'replayed',
      },
      onFailure: invalidProfile,
    );
    if (json['contract_version'] != 'account-profile-v2' ||
        json['timezone'] is! String ||
        json['revision'] is! int ||
        json['updated_at'] is! String ||
        json['replayed'] is! bool) {
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
    final updatedAt = DateTime.tryParse(json['updated_at'] as String);
    if (updatedAt == null || json['revision'] != expectedRevision + 1) {
      throw const AccountProfileUpdateOutcomeUnknownException(
        'Account profile update returned an invalid revision.',
      );
    }
    _pendingRequestIds.remove(requestKey);
    return AccountTimezoneWrite(
      timezone: returnedTimezone,
      revision: json['revision'] as int,
      updatedAt: updatedAt,
      replayed: json['replayed'] as bool,
    );
  }

  Future<AccountPreparationBudgetWrite> updateDailyPreparationBudget({
    required String accessToken,
    required int expectedRevision,
    required int? minutes,
  }) async {
    if (!isValidDailyPreparationBudget(minutes)) {
      throw const AccountSettingsContractException(
        'Choose 25 to 480 minutes in five-minute steps.',
      );
    }
    final requestKey = 'preparation:$expectedRevision:$minutes';
    final requestId = _pendingRequestIds.putIfAbsent(requestKey, newClientUuid);
    late final Map<String, dynamic> json;
    try {
      json = await _client.patchJson(
        '/v1/account/preparation-budget',
        headers: _headers(accessToken),
        body: {
          'contract_version': 'account-preparation-budget-update-v2',
          'request_id': requestId,
          'expected_revision': expectedRevision,
          'daily_preparation_budget_minutes': minutes,
        },
      );
    } on AppException catch (error) {
      final failure = apiFailureFrom(error);
      if (failure?.statusCode == 422) {
        throw const AccountPreparationBudgetRejectedException(
          'The backend rejected that daily preparation budget.',
        );
      }
      if (failure?.statusCode == 409) {
        throw const AccountSettingConflictException(
          'Preparation budget changed. Reload your account before saving.',
        );
      }
      if (failure != null && failure.hasAmbiguousMutationOutcome) {
        throw const AccountPreparationBudgetUpdateOutcomeUnknownException(
          'Preparation budget update outcome could not be confirmed.',
        );
      }
      rethrow;
    }
    Never invalidBudget() =>
        throw const AccountPreparationBudgetUpdateOutcomeUnknownException(
          'Preparation budget update returned an invalid result.',
        );
    requireStrictKeys(
      json,
      requiredKeys: const {
        'contract_version',
        'daily_preparation_budget_minutes',
        'revision',
        'updated_at',
        'replayed',
      },
      onFailure: invalidBudget,
    );
    if (json['contract_version'] != 'account-preparation-budget-v2') {
      throw const AccountPreparationBudgetUpdateOutcomeUnknownException(
        'Preparation budget update returned an invalid result.',
      );
    }
    final returned = json['daily_preparation_budget_minutes'];
    if ((returned != null && returned is! int) || returned != minutes) {
      throw const AccountPreparationBudgetUpdateOutcomeUnknownException(
        'Preparation budget update returned a mismatched result.',
      );
    }
    final updatedAt = DateTime.tryParse('${json['updated_at'] ?? ''}');
    if (json['revision'] is! int ||
        json['revision'] != expectedRevision + 1 ||
        updatedAt == null ||
        json['replayed'] is! bool) {
      throw const AccountPreparationBudgetUpdateOutcomeUnknownException(
        'Preparation budget update returned an invalid revision.',
      );
    }
    _pendingRequestIds.remove(requestKey);
    return AccountPreparationBudgetWrite(
      minutes: returned as int?,
      revision: json['revision'] as int,
      updatedAt: updatedAt,
      replayed: json['replayed'] as bool,
    );
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
        'Account export exceeds the V3 bounds.',
      );
    } on AppException catch (error) {
      if (apiFailureFrom(error)?.statusCode == 413) {
        throw const AccountExportTooLargeException(
          'Account export exceeds the V3 bounds.',
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
      final failure = apiFailureFrom(error);
      if (failure?.statusCode == 403) {
        throw const AccountRecentAuthenticationRequiredException(
          'Recent authentication is required before account deletion.',
        );
      }
      if (failure != null && failure.hasAmbiguousMutationOutcome) {
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
