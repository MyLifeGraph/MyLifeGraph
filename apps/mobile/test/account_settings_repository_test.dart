import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:my_life_graph/core/config/app_config.dart';
import 'package:my_life_graph/core/contracts/account_deletion.dart';
import 'package:my_life_graph/core/errors/app_exception.dart';
import 'package:my_life_graph/core/network/api_client.dart';
import 'package:my_life_graph/core/network/api_failure.dart';
import 'package:my_life_graph/features/settings/data/account_api_data_source.dart';
import 'package:my_life_graph/features/settings/data/account_deletion_coordinator.dart';
import 'package:my_life_graph/features/settings/data/account_deletion_pending_store.dart';
import 'package:my_life_graph/features/settings/data/account_settings_repository_impl.dart';
import 'package:my_life_graph/features/settings/domain/account_settings.dart';

void main() {
  const deletionId = 'a1000000-0000-4000-8000-000000000001';
  const config = AppConfig(
    environment: 'test',
    supabaseUrl: 'http://127.0.0.1:54321',
    supabaseAnonKey: 'anon-key',
    aiServiceBaseUrl: 'http://127.0.0.1:8000',
    useMockData: false,
  );

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('export contract includes Focus provenance and Planner content', () {
    expect(accountExportTableNames, hasLength(41));
    expect(accountExportTableNames, isNot(contains('goals')));
    expect(accountExportTableNames, isNot(contains('recommendations')));
    expect(accountExportTableNames, isNot(contains('decision_feedback')));
    expect(
      accountExportTableNames,
      containsAllInOrder(const [
        'focus_sessions',
        'focus_session_schedule_sources',
        'focus_session_reflections',
      ]),
    );
    expect(
      accountExportTableNames,
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
      accountExportTableNames,
      containsAllInOrder(const [
        'assignment_series',
        'assignment_series_revisions',
        'assignment_series_revision_items',
        'deadline_plans',
      ]),
    );
    expect(
      accountExportV1OmittedTables['planner_request_identities'],
      'backend_only_anti_replay_ledger',
    );
    expect(
      accountExportTableNames,
      isNot(contains('planner_request_identities')),
    );
  });

  test('account operations use exact endpoints, bodies, and bearer', () async {
    final client = _TrackingApiClient(
      patchResponse: const {
        'contract_version': 'account-profile-v2',
        'timezone': 'Europe/London',
        'revision': 5,
        'updated_at': '2026-07-29T12:00:00Z',
        'replayed': false,
      },
      getResponse: _validExportJson(
        profileRows: const [
          {'id': 'account-id'},
        ],
      ),
    );
    final dataSource = AccountApiDataSource(client);
    final repository = AccountSettingsRepositoryImpl(
      config: config,
      apiDataSource: dataSource,
      deletionCoordinator: AccountDeletionCoordinator(
        apiDataSource: dataSource,
        pendingStore: const AccountDeletionPendingStore(),
      ),
      accessTokenProvider: () => ' account-token ',
      authSnapshotProvider: () => const AccountAuthSnapshot(
        userId: 'account-id',
        accessToken: 'account-token',
      ),
      canUseSyncedAccount: true,
    );

    final write = await repository.updateTimezone(
      'Europe/London',
      expectedRevision: 4,
    );
    final export = await repository.exportAccount();
    await repository.deleteAccount(expectedUserId: 'account-id');

    expect(write.timezone, 'Europe/London');
    expect(write.revision, 5);
    expect(export.contractVersion, 'account-export-v6');
    expect(export.recordCounts['profiles'], 1);
    expect(client.patchCalls, ['/v1/account/profile']);
    expect(client.getCalls, ['/v1/account/export']);
    expect(
      client.getTimeoutsByPath['/v1/account/export'],
      AccountApiDataSource.exportReceiveTimeout,
    );
    expect(client.deleteCalls, ['/v1/account']);
    final profileBody = client.bodyByPath['/v1/account/profile']!;
    expect(profileBody['contract_version'], 'account-profile-update-v2');
    expect(profileBody['expected_revision'], 4);
    expect(profileBody['timezone'], 'Europe/London');
    expect(
      profileBody['request_id'],
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );
    expect(client.bodyByPath['/v1/account'], {
      'contract_version': accountDeletionContractVersion,
      'deletion_id': isA<String>(),
      'confirmation': 'DELETE',
    });
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
    const tooLarge = ApiFailure(
      kind: ApiFailureKind.response,
      statusCode: 413,
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

  test('delete requires exact V2 result and classifies ambiguous outcomes',
      () async {
    await expectLater(
      AccountApiDataSource(
        _TrackingApiClient(
          deleteResponse: const ApiMutationResponse(
            statusCode: 200,
            body: '',
          ),
        ),
      ).deleteAccount(accessToken: 'token', deletionId: deletionId),
      throwsA(isA<AccountDeletionOutcomeUnknownException>()),
    );
    await expectLater(
      AccountApiDataSource(
        _TrackingApiClient(
          deleteResponse: const ApiMutationResponse(
            statusCode: 202,
            body: 'unexpected',
          ),
        ),
      ).deleteAccount(accessToken: 'token', deletionId: deletionId),
      throwsA(isA<AccountDeletionOutcomeUnknownException>()),
    );

    const unknownResponse = ApiFailure(
      kind: ApiFailureKind.response,
      statusCode: 502,
    );
    await expectLater(
      AccountApiDataSource(
        _TrackingApiClient(deleteError: unknownResponse),
      ).deleteAccount(accessToken: 'token', deletionId: deletionId),
      throwsA(isA<AccountDeletionOutcomeUnknownException>()),
    );

    const transportLoss = ApiFailure(kind: ApiFailureKind.timeout);
    await expectLater(
      AccountApiDataSource(
        _TrackingApiClient(deleteError: transportLoss),
      ).deleteAccount(accessToken: 'token', deletionId: deletionId),
      throwsA(isA<AccountDeletionOutcomeUnknownException>()),
    );

    const gatewayTimeout = ApiFailure(
      kind: ApiFailureKind.response,
      statusCode: 504,
    );
    await expectLater(
      AccountApiDataSource(
        _TrackingApiClient(deleteError: gatewayTimeout),
      ).deleteAccount(accessToken: 'token', deletionId: deletionId),
      throwsA(isA<AccountDeletionOutcomeUnknownException>()),
    );
  });

  test('delete maps a recent-authentication rejection separately', () async {
    const recentAuthenticationRequired = ApiFailure(
      kind: ApiFailureKind.response,
      statusCode: 403,
    );

    await expectLater(
      AccountApiDataSource(
        _TrackingApiClient(deleteError: recentAuthenticationRequired),
      ).deleteAccount(accessToken: 'token', deletionId: deletionId),
      throwsA(isA<AccountRecentAuthenticationRequiredException>()),
    );
  });

  test('deletion parser rejects naive times and status adopts server identity',
      () async {
    final naive = jsonEncode({
      'contract_version': accountDeletionContractVersion,
      'deletion_id': deletionId,
      'state': 'deletion_pending',
      'accepted_at': '2026-08-20T12:00:00',
      'completed_at': null,
      'journal_durable': false,
    });
    await expectLater(
      AccountApiDataSource(
        _TrackingApiClient(
          deleteResponse: ApiMutationResponse(statusCode: 202, body: naive),
        ),
      ).deleteAccount(accessToken: 'token', deletionId: deletionId),
      throwsA(isA<AccountDeletionOutcomeUnknownException>()),
    );

    const serverDeletionId = 'a1000000-0000-4000-8000-000000000099';
    final client = _TrackingApiClient(
      getResponse: const {
        'contract_version': 'account-deletion-status-v2',
        'deletion': {
          'contract_version': accountDeletionContractVersion,
          'deletion_id': serverDeletionId,
          'state': 'deletion_pending',
          'accepted_at': '2026-08-20T12:00:00Z',
          'completed_at': null,
          'journal_durable': true,
        },
      },
      deleteError: const ApiFailure(
        kind: ApiFailureKind.response,
        statusCode: 503,
      ),
    );
    final store = const AccountDeletionPendingStore();
    final recovery = await AccountDeletionCoordinator(
      apiDataSource: AccountApiDataSource(client),
      pendingStore: store,
    ).resume(userId: 'account-id', accessToken: 'token');

    expect(recovery?.deletionId, serverDeletionId);
    expect(recovery?.journalDurable, isTrue);
    expect(await store.read(userId: 'account-id'), serverDeletionId);
    expect(client.bodyByPath['/v1/account']?['deletion_id'], serverDeletionId);
  });

  test('pending deletion store serializes concurrent identity creation',
      () async {
    final store = const AccountDeletionPendingStore();
    final identities = await Future.wait([
      store.getOrCreate(userId: 'account-id'),
      store.getOrCreate(userId: 'account-id'),
      store.getOrCreate(userId: 'account-id'),
    ]);

    final identitySet = identities.toSet();
    expect(identitySet, hasLength(1));
    expect(await store.read(userId: 'account-id'), identitySet.single);
  });

  test('delete aborts before transport when the authenticated owner changes',
      () async {
    final client = _TrackingApiClient();
    final dataSource = AccountApiDataSource(client);
    var reads = 0;
    AccountAuthSnapshot? authSnapshot() {
      reads += 1;
      return AccountAuthSnapshot(
        userId: reads < 3 ? 'account-id' : 'other-account-id',
        accessToken: reads < 3 ? 'token-a' : 'token-b',
      );
    }

    final repository = AccountSettingsRepositoryImpl(
      config: config,
      apiDataSource: dataSource,
      deletionCoordinator: AccountDeletionCoordinator(
        apiDataSource: dataSource,
        pendingStore: const AccountDeletionPendingStore(),
      ),
      accessTokenProvider: () => 'token-a',
      authSnapshotProvider: authSnapshot,
      canUseSyncedAccount: true,
    );

    await expectLater(
      repository.deleteAccount(expectedUserId: 'account-id'),
      throwsA(isA<AccountSettingsAccessException>()),
    );
    expect(client.deleteCalls, isEmpty);
    expect(
      await const AccountDeletionPendingStore().read(userId: 'account-id'),
      isNull,
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
      invalidRequestRepository.updateTimezone('CET', expectedRevision: 1),
      throwsA(isA<AccountSettingsContractException>()),
    );
    expect(invalidRequestClient.totalCalls, 0);

    final mismatchedClient = _TrackingApiClient(
      patchResponse: const {
        'contract_version': 'account-profile-v2',
        'timezone': 'Europe/Paris',
        'revision': 2,
        'updated_at': '2026-07-29T12:00:00Z',
        'replayed': false,
      },
    );
    final mismatchedRepository = AccountSettingsRepositoryImpl(
      config: config,
      apiDataSource: AccountApiDataSource(mismatchedClient),
      accessTokenProvider: () => 'token',
      canUseSyncedAccount: true,
    );
    await expectLater(
      mismatchedRepository.updateTimezone(
        'Europe/London',
        expectedRevision: 1,
      ),
      throwsA(isA<AccountProfileUpdateOutcomeUnknownException>()),
    );

    const unknownResponse = ApiFailure(
      kind: ApiFailureKind.response,
      statusCode: 502,
    );
    await expectLater(
      AccountApiDataSource(
        _TrackingApiClient(patchError: unknownResponse),
      ).updateTimezone(
        accessToken: 'token',
        expectedRevision: 1,
        timezone: 'Europe/London',
      ),
      throwsA(isA<AccountProfileUpdateOutcomeUnknownException>()),
    );

    const conflictResponse = ApiFailure(
      kind: ApiFailureKind.response,
      statusCode: 409,
    );
    await expectLater(
      AccountApiDataSource(
        _TrackingApiClient(patchError: conflictResponse),
      ).updateTimezone(
        accessToken: 'token',
        expectedRevision: 1,
        timezone: 'Europe/London',
      ),
      throwsA(isA<AccountSettingConflictException>()),
    );

    const rejectedResponse = ApiFailure(
      kind: ApiFailureKind.response,
      statusCode: 422,
    );
    await expectLater(
      AccountApiDataSource(
        _TrackingApiClient(patchError: rejectedResponse),
      ).updateTimezone(
        accessToken: 'token',
        expectedRevision: 1,
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
          'contract_version': 'account-preparation-budget-v2',
          'daily_preparation_budget_minutes': minutes,
          'revision': 8,
          'updated_at': '2026-07-29T12:00:00Z',
          'replayed': false,
        },
      );
      final repository = AccountSettingsRepositoryImpl(
        config: config,
        apiDataSource: AccountApiDataSource(client),
        accessTokenProvider: () => ' account-token ',
        canUseSyncedAccount: true,
      );

      final write = await repository.updateDailyPreparationBudget(
        minutes,
        expectedRevision: 7,
      );
      expect(write.minutes, minutes);
      expect(write.revision, 8);
      expect(client.patchCalls, ['/v1/account/preparation-budget']);
      final body = client.bodyByPath['/v1/account/preparation-budget']!;
      expect(
        body['contract_version'],
        'account-preparation-budget-update-v2',
      );
      expect(body['expected_revision'], 7);
      expect(body['daily_preparation_budget_minutes'], minutes);
      expect(
        body['request_id'],
        isA<String>().having((value) => value.length, 'UUID length', 36),
      );
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
        invalidRepository.updateDailyPreparationBudget(
          minutes,
          expectedRevision: 1,
        ),
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
          patchResponse: const {
            'contract_version': 'account-preparation-budget-v2',
            'daily_preparation_budget_minutes': 90,
            'revision': 2,
            'updated_at': '2026-07-29T12:00:00Z',
            'replayed': false,
          },
        ),
      ).updateDailyPreparationBudget(
        accessToken: 'token',
        expectedRevision: 1,
        minutes: 120,
      ),
      throwsA(isA<AccountPreparationBudgetUpdateOutcomeUnknownException>()),
    );

    const unknownResponse = ApiFailure(
      kind: ApiFailureKind.response,
      statusCode: 502,
    );
    await expectLater(
      AccountApiDataSource(
        _TrackingApiClient(patchError: unknownResponse),
      ).updateDailyPreparationBudget(
        accessToken: 'token',
        expectedRevision: 1,
        minutes: 120,
      ),
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
        repository.updateDailyPreparationBudget(120, expectedRevision: 1),
        throwsA(isA<AccountSettingsAccessException>()),
      );
      await expectLater(
        repository.deleteAccount(expectedUserId: 'account-id'),
        throwsA(isA<AccountSettingsAccessException>()),
      );
    }
  });
}

class _TrackingApiClient extends ApiClient {
  _TrackingApiClient({
    this.patchResponse = const <String, dynamic>{},
    this.getResponse = const <String, dynamic>{},
    this.deleteResponse,
    this.patchError,
    this.getError,
    this.deleteError,
    this.getBytesResponse,
    this.getBytesError,
  }) : super(Dio());

  final Map<String, dynamic> patchResponse;
  final Map<String, dynamic> getResponse;
  final ApiMutationResponse? deleteResponse;
  final ApiFailure? patchError;
  final ApiFailure? getError;
  final ApiFailure? deleteError;
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
    return deleteResponse ??
        ApiMutationResponse(
          statusCode: 200,
          body: jsonEncode({
            'contract_version': accountDeletionContractVersion,
            'deletion_id': body['deletion_id'],
            'state': 'completed',
            'accepted_at': '2026-08-20T12:00:00Z',
            'completed_at': '2026-08-20T12:00:01Z',
            'journal_durable': true,
          }),
        );
  }
}

Map<String, dynamic> _validExportJson({
  List<Map<String, dynamic>> profileRows = const [],
}) {
  final data = <String, dynamic>{
    for (final table in accountExportTableNames)
      table: <Map<String, dynamic>>[],
  };
  data['profiles'] = profileRows;
  return {
    'contract_version': 'account-export-v6',
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
