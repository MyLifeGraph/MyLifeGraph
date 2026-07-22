import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/config/app_config.dart';
import 'package:my_life_graph/core/errors/app_exception.dart';
import 'package:my_life_graph/core/network/api_client.dart';
import 'package:my_life_graph/features/settings/data/account_api_data_source.dart';
import 'package:my_life_graph/features/settings/data/account_settings_repository_impl.dart';
import 'package:my_life_graph/features/settings/domain/account_settings.dart';

void main() {
  const config = AppConfig(
    environment: 'test',
    supabaseUrl: 'http://127.0.0.1:54321',
    supabaseAnonKey: 'anon-key',
    aiServiceBaseUrl: 'http://127.0.0.1:8000',
    useMockData: false,
  );

  test('export contract includes Planner content and omits its retry ledger',
      () {
    expect(
      accountExportV1TableNames,
      containsAllInOrder(const [
        'planner_preferences',
        'planner_action_plans',
        'planner_action_plan_revisions',
        'planner_task_blocks',
        'planner_habit_slots',
        'planner_commitments',
      ]),
    );
    expect(
      accountExportV1OmittedTables['planner_request_identities'],
      'backend_only_anti_replay_ledger',
    );
    expect(
      accountExportV1TableNames,
      isNot(contains('planner_request_identities')),
    );
  });

  test('account operations use exact endpoints, bodies, and bearer', () async {
    final client = _TrackingApiClient(
      patchResponse: const {'timezone': 'Europe/London'},
      getResponse: _validExportJson(
        profileRows: const [
          {'id': 'account-id'},
        ],
      ),
    );
    final repository = AccountSettingsRepositoryImpl(
      config: config,
      apiDataSource: AccountApiDataSource(client),
      accessTokenProvider: () => ' account-token ',
      canUseSyncedAccount: true,
    );

    expect(
      await repository.updateTimezone('Europe/London'),
      'Europe/London',
    );
    final export = await repository.exportAccount();
    await repository.deleteAccount();

    expect(export.contractVersion, 'account-export-v1');
    expect(export.recordCounts['profiles'], 1);
    expect(client.patchCalls, ['/v1/account/profile']);
    expect(client.getCalls, ['/v1/account/export']);
    expect(
      client.getTimeoutsByPath['/v1/account/export'],
      AccountApiDataSource.exportReceiveTimeout,
    );
    expect(client.deleteCalls, ['/v1/account']);
    expect(client.bodyByPath['/v1/account/profile'], {
      'timezone': 'Europe/London',
    });
    expect(client.bodyByPath['/v1/account'], {'confirmation': 'DELETE'});
    for (final headers in client.headersByPath.values) {
      expect(headers, {'Authorization': 'Bearer account-token'});
    }
  });

  test('export rejects unknown fields and mismatched record counts', () async {
    Map<String, dynamic> exportJson() => _validExportJson(
          profileRows: const [
            {'id': 'account-id'},
          ],
        );

    final unknown = exportJson()..['unexpected'] = true;
    final mismatch = exportJson()..['record_counts'] = {'profiles': 0};
    for (final response in [unknown, mismatch]) {
      final repository = AccountSettingsRepositoryImpl(
        config: config,
        apiDataSource: AccountApiDataSource(
          _TrackingApiClient(getResponse: response),
        ),
        accessTokenProvider: () => 'token',
        canUseSyncedAccount: true,
      );
      await expectLater(
        repository.exportAccount(),
        throwsA(isA<AccountSettingsContractException>()),
      );
    }
  });

  test('export rejects altered table, policy, and limit contracts', () async {
    final missingTable = _validExportJson();
    (missingTable['data'] as Map<String, dynamic>).remove('lifestyle_entries');
    (missingTable['record_counts'] as Map<String, int>)
        .remove('lifestyle_entries');

    final alteredPolicy = _validExportJson();
    (alteredPolicy['ledger_policy']
        as Map<String, dynamic>)['sanitized_tables'] = <String>[];

    final alteredLimits = _validExportJson();
    (alteredLimits['limits'] as Map<String, int>)['max_json_bytes'] = 1000000;

    for (final response in [missingTable, alteredPolicy, alteredLimits]) {
      final dataSource = AccountApiDataSource(
        _TrackingApiClient(getResponse: response),
      );
      await expectLater(
        dataSource.exportAccount(accessToken: 'token'),
        throwsA(isA<AccountSettingsContractException>()),
      );
    }
  });

  test('export maps the hard server bound separately from retryable errors',
      () async {
    final tooLarge = DioException(
      requestOptions: RequestOptions(path: '/v1/account/export'),
      response: Response<void>(
        requestOptions: RequestOptions(path: '/v1/account/export'),
        statusCode: 413,
      ),
      type: DioExceptionType.badResponse,
    );
    await expectLater(
      AccountApiDataSource(
        _TrackingApiClient(getError: tooLarge),
      ).exportAccount(accessToken: 'token'),
      throwsA(isA<AccountExportTooLargeException>()),
    );
    await expectLater(
      AccountApiDataSource(
        _TrackingApiClient(
          getBytesError: const ApiResponseTooLargeException(),
        ),
      ).exportAccount(accessToken: 'token'),
      throwsA(isA<AccountExportTooLargeException>()),
    );
  });

  test('export retains validated source bytes without numeric rounding',
      () async {
    final canonical = jsonEncode(
      _validExportJson(
        profileRows: const [
          {
            'id': 'account-id',
            'metadata': {'exact': 0, 'large': 0},
          },
        ],
      ),
    );
    final raw = canonical
        .replaceFirst('"exact":0', '"exact":0.12345678901234567890')
        .replaceFirst('"large":0', '"large":9007199254740993');
    final export = await AccountApiDataSource(
      _TrackingApiClient(getBytesResponse: utf8.encode(raw)),
    ).exportAccount(accessToken: 'token');

    expect(utf8.decode(export.fileBytes), raw);
    expect(
      utf8.decode(export.fileBytes),
      contains('"exact":0.12345678901234567890'),
    );
    expect(utf8.decode(export.fileBytes), contains('"large":9007199254740993'));
  });

  test('export byte parser rejects invalid input and owns defensive copies',
      () {
    for (final invalid in [
      Uint8List(0),
      Uint8List.fromList(const [0xC3, 0x28]),
      Uint8List(accountExportV1MaxJsonBytes + 1),
    ]) {
      expect(
        () => AccountExportEnvelope.fromJsonBytes(invalid),
        throwsA(isA<AccountSettingsContractException>()),
      );
    }

    final source = Uint8List.fromList(
      utf8.encode(jsonEncode(_validExportJson())),
    );
    final expected = Uint8List.fromList(source);
    final export = AccountExportEnvelope.fromJsonBytes(source);
    source[0] = 0;
    final firstRead = export.fileBytes;
    firstRead[0] = 0;

    expect(export.fileBytes, expected);
  });

  test('delete requires exact empty 204 and classifies ambiguous outcomes',
      () async {
    await expectLater(
      AccountApiDataSource(
        _TrackingApiClient(
          deleteResponse: const ApiMutationResponse(
            statusCode: 200,
            body: '',
          ),
        ),
      ).deleteAccount(accessToken: 'token'),
      throwsA(isA<AccountDeletionOutcomeUnknownException>()),
    );
    await expectLater(
      AccountApiDataSource(
        _TrackingApiClient(
          deleteResponse: const ApiMutationResponse(
            statusCode: 204,
            body: 'unexpected',
          ),
        ),
      ).deleteAccount(accessToken: 'token'),
      throwsA(isA<AccountDeletionOutcomeUnknownException>()),
    );

    final unknownResponse = DioException(
      requestOptions: RequestOptions(path: '/v1/account'),
      response: Response<void>(
        requestOptions: RequestOptions(path: '/v1/account'),
        statusCode: 502,
      ),
      type: DioExceptionType.badResponse,
    );
    await expectLater(
      AccountApiDataSource(
        _TrackingApiClient(deleteError: unknownResponse),
      ).deleteAccount(accessToken: 'token'),
      throwsA(isA<AccountDeletionOutcomeUnknownException>()),
    );

    final transportLoss = DioException(
      requestOptions: RequestOptions(path: '/v1/account'),
      type: DioExceptionType.receiveTimeout,
    );
    await expectLater(
      AccountApiDataSource(
        _TrackingApiClient(deleteError: transportLoss),
      ).deleteAccount(accessToken: 'token'),
      throwsA(isA<AccountDeletionOutcomeUnknownException>()),
    );

    final gatewayTimeout = DioException(
      requestOptions: RequestOptions(path: '/v1/account'),
      response: Response<void>(
        requestOptions: RequestOptions(path: '/v1/account'),
        statusCode: 504,
      ),
      type: DioExceptionType.badResponse,
    );
    await expectLater(
      AccountApiDataSource(
        _TrackingApiClient(deleteError: gatewayTimeout),
      ).deleteAccount(accessToken: 'token'),
      throwsA(isA<AccountDeletionOutcomeUnknownException>()),
    );
  });

  test('delete maps a recent-authentication rejection separately', () async {
    final recentAuthenticationRequired = DioException(
      requestOptions: RequestOptions(path: '/v1/account'),
      response: Response<void>(
        requestOptions: RequestOptions(path: '/v1/account'),
        statusCode: 403,
      ),
      type: DioExceptionType.badResponse,
    );

    await expectLater(
      AccountApiDataSource(
        _TrackingApiClient(deleteError: recentAuthenticationRequired),
      ).deleteAccount(accessToken: 'token'),
      throwsA(isA<AccountRecentAuthenticationRequiredException>()),
    );
  });

  test('timezone is curated and ambiguous responses remain explicit', () async {
    final invalidRequestClient = _TrackingApiClient();
    final invalidRequestRepository = AccountSettingsRepositoryImpl(
      config: config,
      apiDataSource: AccountApiDataSource(invalidRequestClient),
      accessTokenProvider: () => 'token',
      canUseSyncedAccount: true,
    );
    await expectLater(
      invalidRequestRepository.updateTimezone('CET'),
      throwsA(isA<AccountSettingsContractException>()),
    );
    expect(invalidRequestClient.totalCalls, 0);

    final mismatchedClient = _TrackingApiClient(
      patchResponse: const {'timezone': 'Europe/Paris'},
    );
    final mismatchedRepository = AccountSettingsRepositoryImpl(
      config: config,
      apiDataSource: AccountApiDataSource(mismatchedClient),
      accessTokenProvider: () => 'token',
      canUseSyncedAccount: true,
    );
    await expectLater(
      mismatchedRepository.updateTimezone('Europe/London'),
      throwsA(isA<AccountProfileUpdateOutcomeUnknownException>()),
    );

    final unknownResponse = DioException(
      requestOptions: RequestOptions(path: '/v1/account/profile'),
      response: Response<void>(
        requestOptions: RequestOptions(path: '/v1/account/profile'),
        statusCode: 502,
      ),
      type: DioExceptionType.badResponse,
    );
    await expectLater(
      AccountApiDataSource(
        _TrackingApiClient(patchError: unknownResponse),
      ).updateTimezone(
        accessToken: 'token',
        timezone: 'Europe/London',
      ),
      throwsA(isA<AccountProfileUpdateOutcomeUnknownException>()),
    );

    final rejectedResponse = DioException(
      requestOptions: RequestOptions(path: '/v1/account/profile'),
      response: Response<void>(
        requestOptions: RequestOptions(path: '/v1/account/profile'),
        statusCode: 422,
      ),
      type: DioExceptionType.badResponse,
    );
    await expectLater(
      AccountApiDataSource(
        _TrackingApiClient(patchError: rejectedResponse),
      ).updateTimezone(
        accessToken: 'token',
        timezone: 'Europe/NotARealZone',
      ),
      throwsA(isA<AccountTimezoneRejectedException>()),
    );
  });

  test('daily preparation budget uses strict nullable owner endpoint',
      () async {
    for (final minutes in <int?>[120, null]) {
      final client = _TrackingApiClient(
        patchResponse: {
          'daily_preparation_budget_minutes': minutes,
        },
      );
      final repository = AccountSettingsRepositoryImpl(
        config: config,
        apiDataSource: AccountApiDataSource(client),
        accessTokenProvider: () => ' account-token ',
        canUseSyncedAccount: true,
      );

      expect(await repository.updateDailyPreparationBudget(minutes), minutes);
      expect(client.patchCalls, ['/v1/account/preparation-budget']);
      expect(client.bodyByPath['/v1/account/preparation-budget'], {
        'daily_preparation_budget_minutes': minutes,
      });
      expect(client.headersByPath['/v1/account/preparation-budget'], {
        'Authorization': 'Bearer account-token',
      });
    }

    final invalidClient = _TrackingApiClient();
    final invalidRepository = AccountSettingsRepositoryImpl(
      config: config,
      apiDataSource: AccountApiDataSource(invalidClient),
      accessTokenProvider: () => 'token',
      canUseSyncedAccount: true,
    );
    for (final minutes in [24, 26, 481]) {
      await expectLater(
        invalidRepository.updateDailyPreparationBudget(minutes),
        throwsA(isA<AccountSettingsContractException>()),
      );
    }
    expect(invalidClient.totalCalls, 0);
  });

  test('daily preparation budget rejects mismatches and ambiguous outcomes',
      () async {
    await expectLater(
      AccountApiDataSource(
        _TrackingApiClient(
          patchResponse: const {'daily_preparation_budget_minutes': 90},
        ),
      ).updateDailyPreparationBudget(accessToken: 'token', minutes: 120),
      throwsA(isA<AccountPreparationBudgetUpdateOutcomeUnknownException>()),
    );

    final unknownResponse = DioException(
      requestOptions: RequestOptions(path: '/v1/account/preparation-budget'),
      response: Response<void>(
        requestOptions: RequestOptions(path: '/v1/account/preparation-budget'),
        statusCode: 502,
      ),
      type: DioExceptionType.badResponse,
    );
    await expectLater(
      AccountApiDataSource(
        _TrackingApiClient(patchError: unknownResponse),
      ).updateDailyPreparationBudget(accessToken: 'token', minutes: 120),
      throwsA(isA<AccountPreparationBudgetUpdateOutcomeUnknownException>()),
    );
  });

  test('guest, missing config, and missing token remain zero-call', () async {
    for (final repository in [
      AccountSettingsRepositoryImpl(
        config: config,
        apiDataSource: AccountApiDataSource(_TrackingApiClient()),
        accessTokenProvider: () => 'token',
        canUseSyncedAccount: false,
      ),
      AccountSettingsRepositoryImpl(
        config: const AppConfig(
          environment: 'test',
          supabaseUrl: '',
          supabaseAnonKey: '',
          aiServiceBaseUrl: 'http://127.0.0.1:8000',
          useMockData: false,
        ),
        apiDataSource: AccountApiDataSource(_TrackingApiClient()),
        accessTokenProvider: () => 'token',
        canUseSyncedAccount: true,
      ),
      AccountSettingsRepositoryImpl(
        config: config,
        apiDataSource: AccountApiDataSource(_TrackingApiClient()),
        accessTokenProvider: () => ' ',
        canUseSyncedAccount: true,
      ),
    ]) {
      await expectLater(
        repository.exportAccount(),
        throwsA(isA<AccountSettingsAccessException>()),
      );
      await expectLater(
        repository.updateDailyPreparationBudget(120),
        throwsA(isA<AccountSettingsAccessException>()),
      );
      await expectLater(
        repository.deleteAccount(),
        throwsA(isA<AccountSettingsAccessException>()),
      );
    }
  });
}

class _TrackingApiClient extends ApiClient {
  _TrackingApiClient({
    this.patchResponse = const <String, dynamic>{},
    this.getResponse = const <String, dynamic>{},
    this.deleteResponse = const ApiMutationResponse(
      statusCode: 204,
      body: null,
    ),
    this.patchError,
    this.getError,
    this.deleteError,
    this.getBytesResponse,
    this.getBytesError,
  }) : super(Dio());

  final Map<String, dynamic> patchResponse;
  final Map<String, dynamic> getResponse;
  final ApiMutationResponse deleteResponse;
  final DioException? patchError;
  final DioException? getError;
  final DioException? deleteError;
  final List<int>? getBytesResponse;
  final Object? getBytesError;
  final List<String> patchCalls = [];
  final List<String> getCalls = [];
  final List<String> deleteCalls = [];
  final Map<String, Duration> getTimeoutsByPath = {};
  final Map<String, Map<String, dynamic>> bodyByPath = {};
  final Map<String, Map<String, String>?> headersByPath = {};

  int get totalCalls =>
      patchCalls.length + getCalls.length + deleteCalls.length;

  @override
  Future<Map<String, dynamic>> patchJson(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  }) async {
    patchCalls.add(path);
    bodyByPath[path] = body ?? const {};
    headersByPath[path] = headers;
    final error = patchError;
    if (error != null) {
      throw AppException('Network request failed', cause: error);
    }
    return patchResponse;
  }

  @override
  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, String>? headers,
  }) async {
    getCalls.add(path);
    headersByPath[path] = headers;
    final error = getError;
    if (error != null) {
      throw AppException('Network request failed', cause: error);
    }
    return getResponse;
  }

  @override
  Future<Uint8List> getBytesWithTimeout(
    String path, {
    required Duration receiveTimeout,
    required int maxResponseBytes,
    Map<String, String>? headers,
  }) async {
    getCalls.add(path);
    getTimeoutsByPath[path] = receiveTimeout;
    expect(maxResponseBytes, accountExportV1MaxJsonBytes);
    headersByPath[path] = headers;
    final bytesError = getBytesError;
    if (bytesError != null) throw bytesError;
    final error = getError;
    if (error != null) {
      throw AppException('Network request failed', cause: error);
    }
    return Uint8List.fromList(
      getBytesResponse ?? utf8.encode(jsonEncode(getResponse)),
    );
  }

  @override
  Future<ApiMutationResponse> deleteWithBodyResponse(
    String path, {
    required Map<String, dynamic> body,
    Map<String, String>? headers,
  }) async {
    deleteCalls.add(path);
    bodyByPath[path] = body;
    headersByPath[path] = headers;
    final error = deleteError;
    if (error != null) {
      throw AppException('Network request failed', cause: error);
    }
    return deleteResponse;
  }
}

Map<String, dynamic> _validExportJson({
  List<Map<String, dynamic>> profileRows = const [],
}) {
  final data = <String, dynamic>{
    for (final table in accountExportV1TableNames)
      table: <Map<String, dynamic>>[],
  };
  data['profiles'] = profileRows;
  return {
    'contract_version': 'account-export-v1',
    'exported_at': '2026-07-13T12:00:00Z',
    'data': data,
    'record_counts': <String, int>{
      for (final entry in data.entries) entry.key: (entry.value as List).length,
    },
    'ledger_policy': {
      'sanitized_tables': accountExportV1SanitizedTables,
      'omitted_tables': accountExportV1OmittedTables,
    },
    'limits': {
      'max_rows_per_table': accountExportV1MaxRowsPerTable,
      'max_total_rows': accountExportV1MaxTotalRows,
      'max_json_bytes': accountExportV1MaxJsonBytes,
    },
  };
}
