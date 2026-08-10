import 'dart:convert';
import 'dart:typed_data';

import '../../../core/contracts/strict_contract.dart';

const accountExportContractVersion = 'account-export-v4';
const accountExportTableNames = <String>[
  'profiles',
  'notification_preferences',
  'learning_preferences',
  'daily_logs',
  'behavioral_events',
  'lifestyle_entries',
  'tasks',
  'schedule_items',
  'notifications',
  'coach_messages',
  'memory_entries',
  'ai_insights',
  'recommendations',
  'skillset_profiles',
  'habits',
  'habit_logs',
  'focus_sessions',
  'focus_session_schedule_sources',
  'focus_session_reflections',
  'intake_responses',
  'study_setup_profiles',
  'user_state_snapshots',
  'daily_briefings',
  'decision_feedback',
  'weekly_reviews',
  'calendar_connections',
  'calendar_imports',
  'calendar_events',
  'coach_requests',
  'coach_usage_events',
  'coach_memory_selections',
  'assignment_series',
  'assignment_series_revisions',
  'assignment_series_revision_items',
  'deadline_plans',
  'deadline_plan_revisions',
  'deadline_plan_blocks',
  'planner_preferences',
  'planner_action_plans',
  'planner_action_plan_revisions',
  'planner_task_blocks',
  'planner_habit_slots',
  'planner_commitments',
];
const accountExportV1SanitizedTables = <String>[
  'calendar_connections',
  'calendar_imports',
  'calendar_events',
  'coach_requests',
  'coach_usage_events',
];
const accountExportV1OmittedTables = <String, String>{
  'daily_capture_request_identities': 'backend_only_anti_replay_ledger',
  'account_setting_request_identities': 'backend_only_anti_replay_ledger',
  'calendar_request_identities': 'backend_only_anti_replay_ledger',
  'notification_action_requests': 'backend_only_anti_replay_ledger',
  'deadline_plan_request_identities': 'backend_only_anti_replay_ledger',
  'assignment_series_request_identities': 'backend_only_anti_replay_ledger',
  'planner_request_identities': 'backend_only_anti_replay_ledger',
  'learning_request_identities': 'backend_only_anti_replay_ledger',
};
const accountExportV1MaxRowsPerTable = 10000;
const accountExportV1MaxTotalRows = 50000;
const accountExportV1MaxJsonBytes = 8 * 1024 * 1024;
const dailyPreparationBudgetMinimumMinutes = 25;
const dailyPreparationBudgetMaximumMinutes = 480;

bool isValidDailyPreparationBudget(int? minutes) =>
    minutes == null ||
    minutes >= dailyPreparationBudgetMinimumMinutes &&
        minutes <= dailyPreparationBudgetMaximumMinutes &&
        minutes % 5 == 0;

const supportedAccountTimezones = <String>[
  'UTC',
  'Europe/Berlin',
  'Europe/London',
  'Europe/Paris',
  'Europe/Madrid',
  'Europe/Rome',
  'Europe/Amsterdam',
  'Europe/Brussels',
  'Europe/Zurich',
  'Europe/Vienna',
  'Europe/Prague',
  'Europe/Warsaw',
  'Europe/Athens',
  'Europe/Helsinki',
  'America/New_York',
  'America/Chicago',
  'America/Denver',
  'America/Los_Angeles',
  'America/Toronto',
  'America/Vancouver',
  'America/Mexico_City',
  'America/Sao_Paulo',
  'Asia/Dubai',
  'Asia/Kolkata',
  'Asia/Bangkok',
  'Asia/Singapore',
  'Asia/Hong_Kong',
  'Asia/Tokyo',
  'Asia/Seoul',
  'Australia/Perth',
  'Australia/Sydney',
  'Pacific/Auckland',
];

bool isSupportedAccountTimezone(String value) =>
    supportedAccountTimezones.contains(value.trim());

bool isValidAccountTimezone(String value) {
  final clean = value.trim();
  if (clean == 'UTC') return true;
  if (clean.isEmpty || clean.length > 100 || !clean.contains('/')) return false;
  return RegExp(
    r'^[A-Za-z][A-Za-z0-9._+-]*(/[A-Za-z0-9][A-Za-z0-9._+-]*)+$',
  ).hasMatch(clean);
}

class AccountTimezoneWrite {
  const AccountTimezoneWrite({
    required this.timezone,
    required this.revision,
    required this.updatedAt,
    required this.replayed,
  });

  final String timezone;
  final int revision;
  final DateTime updatedAt;
  final bool replayed;
}

class AccountPreparationBudgetWrite {
  const AccountPreparationBudgetWrite({
    required this.minutes,
    required this.revision,
    required this.updatedAt,
    required this.replayed,
  });

  final int? minutes;
  final int revision;
  final DateTime updatedAt;
  final bool replayed;
}

class AccountSettingsException implements Exception {
  const AccountSettingsException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AccountSettingsContractException extends AccountSettingsException {
  const AccountSettingsContractException(super.message);
}

class AccountSettingsAccessException extends AccountSettingsException {
  const AccountSettingsAccessException(super.message);
}

class AccountDeletionOutcomeUnknownException extends AccountSettingsException {
  const AccountDeletionOutcomeUnknownException(super.message);
}

class AccountRecentAuthenticationRequiredException
    extends AccountSettingsException {
  const AccountRecentAuthenticationRequiredException(super.message);
}

class AccountProfileUpdateOutcomeUnknownException
    extends AccountSettingsException {
  const AccountProfileUpdateOutcomeUnknownException(super.message);
}

class AccountTimezoneRejectedException extends AccountSettingsException {
  const AccountTimezoneRejectedException(super.message);
}

class AccountSettingConflictException extends AccountSettingsException {
  const AccountSettingConflictException(super.message);
}

class AccountPreparationBudgetRejectedException
    extends AccountSettingsException {
  const AccountPreparationBudgetRejectedException(super.message);
}

class AccountPreparationBudgetUpdateOutcomeUnknownException
    extends AccountSettingsException {
  const AccountPreparationBudgetUpdateOutcomeUnknownException(super.message);
}

class AccountExportTooLargeException extends AccountSettingsException {
  const AccountExportTooLargeException(super.message);
}

class AccountExportEnvelope {
  const AccountExportEnvelope._({
    required this.exportedAt,
    required this.data,
    required this.recordCounts,
    required this.sanitizedTables,
    required this.omittedTables,
    required this.maxRowsPerTable,
    required this.maxTotalRows,
    required this.maxJsonBytes,
    required Uint8List sourceBytes,
  }) : _sourceBytes = sourceBytes;

  factory AccountExportEnvelope.fromJson(Map<String, dynamic> json) {
    try {
      final sourceBytes = Uint8List.fromList(utf8.encode(jsonEncode(json)));
      return AccountExportEnvelope._parse(json, sourceBytes: sourceBytes);
    } on AccountSettingsContractException {
      rethrow;
    } catch (_) {
      throw const AccountSettingsContractException(
        'The account export contains a non-JSON value.',
      );
    }
  }

  factory AccountExportEnvelope.fromJsonBytes(Uint8List sourceBytes) {
    if (sourceBytes.isEmpty ||
        sourceBytes.length > accountExportV1MaxJsonBytes) {
      throw const AccountSettingsContractException(
        'The account export exceeds its JSON size bound.',
      );
    }
    try {
      final decoded =
          jsonDecode(utf8.decode(sourceBytes, allowMalformed: false));
      if (decoded is! Map || decoded.keys.any((key) => key is! String)) {
        throw const AccountSettingsContractException(
          'The account export response is not a JSON object.',
        );
      }
      return AccountExportEnvelope._parse(
        Map<String, dynamic>.from(decoded),
        sourceBytes: sourceBytes,
      );
    } on AccountSettingsContractException {
      rethrow;
    } catch (_) {
      throw const AccountSettingsContractException(
        'The account export response is not valid UTF-8 JSON.',
      );
    }
  }

  static AccountExportEnvelope _parse(
    Map<String, dynamic> json, {
    required Uint8List sourceBytes,
  }) {
    const topLevelKeys = {
      'contract_version',
      'exported_at',
      'data',
      'record_counts',
      'ledger_policy',
      'limits',
    };
    Never invalidTopLevel() => throw const AccountSettingsContractException(
          'The account export response has an invalid top-level contract.',
        );
    requireStrictKeys(
      json,
      requiredKeys: topLevelKeys,
      onFailure: invalidTopLevel,
    );
    if (json['contract_version'] != accountExportContractVersion) {
      invalidTopLevel();
    }
    final exportedAt = json['exported_at'];
    if (exportedAt is! String ||
        !isStrictAwareDateTime(exportedAt, exactSecondsFormat: false)) {
      throw const AccountSettingsContractException(
        'The account export timestamp is invalid.',
      );
    }
    final rawData = json['data'];
    final rawCounts = json['record_counts'];
    if (rawData is! Map || rawCounts is! Map) {
      throw const AccountSettingsContractException(
        'The account export data or record counts are invalid.',
      );
    }
    final data = <String, List<Map<String, dynamic>>>{};
    for (final entry in rawData.entries) {
      if (entry.key is! String || entry.value is! List) {
        throw const AccountSettingsContractException(
          'The account export data tables are invalid.',
        );
      }
      final rows = <Map<String, dynamic>>[];
      for (final row in entry.value as List) {
        rows.add(
          requireStrictMap(
            row,
            onFailure: () => throw const AccountSettingsContractException(
              'An account export row is invalid.',
            ),
          ),
        );
      }
      data[entry.key as String] = rows;
    }
    final recordCounts = <String, int>{};
    for (final entry in rawCounts.entries) {
      if (entry.key is! String) {
        throw const AccountSettingsContractException(
          'The account export record counts are invalid.',
        );
      }
      recordCounts[entry.key as String] = requireStrictInt(
        entry.value,
        min: 0,
        onFailure: () => throw const AccountSettingsContractException(
          'The account export record counts are invalid.',
        ),
      );
    }
    if (data.keys.toSet().difference(recordCounts.keys.toSet()).isNotEmpty ||
        recordCounts.keys.toSet().difference(data.keys.toSet()).isNotEmpty ||
        data.keys
            .toSet()
            .difference(accountExportTableNames.toSet())
            .isNotEmpty ||
        accountExportTableNames
            .toSet()
            .difference(data.keys.toSet())
            .isNotEmpty ||
        data.entries.any(
          (entry) => recordCounts[entry.key] != entry.value.length,
        )) {
      throw const AccountSettingsContractException(
        'The account export record counts do not match its data.',
      );
    }

    final ledgerPolicy = json['ledger_policy'];
    if (ledgerPolicy is! Map) {
      throw const AccountSettingsContractException(
        'The account export ledger policy is invalid.',
      );
    }
    final ledgerPolicyMap = requireStrictMap(
      ledgerPolicy,
      onFailure: () => throw const AccountSettingsContractException(
        'The account export ledger policy is invalid.',
      ),
    );
    requireStrictKeys(
      ledgerPolicyMap,
      requiredKeys: const {'sanitized_tables', 'omitted_tables'},
      onFailure: () => throw const AccountSettingsContractException(
        'The account export ledger policy is invalid.',
      ),
    );
    final rawSanitized = ledgerPolicyMap['sanitized_tables'];
    final rawOmitted = ledgerPolicyMap['omitted_tables'];
    if (rawSanitized is! List ||
        rawSanitized.any((value) => value is! String) ||
        rawOmitted is! Map ||
        rawOmitted.entries.any(
          (entry) => entry.key is! String || entry.value is! String,
        )) {
      throw const AccountSettingsContractException(
        'The account export ledger policy values are invalid.',
      );
    }
    if (!_orderedValuesEqual(rawSanitized, accountExportV1SanitizedTables) ||
        !_stringMapsEqual(
          Map<String, String>.from(rawOmitted),
          accountExportV1OmittedTables,
        )) {
      throw const AccountSettingsContractException(
        'The account export ledger policy does not match V2.',
      );
    }

    final limits = json['limits'];
    const limitKeys = {
      'max_rows_per_table',
      'max_total_rows',
      'max_json_bytes',
    };
    if (limits is! Map) {
      throw const AccountSettingsContractException(
        'The account export limits are invalid.',
      );
    }
    final limitsMap = requireStrictMap(
      limits,
      onFailure: () => throw const AccountSettingsContractException(
        'The account export limits are invalid.',
      ),
    );
    Never invalidLimits() => throw const AccountSettingsContractException(
          'The account export limits are invalid.',
        );
    requireStrictKeys(
      limitsMap,
      requiredKeys: limitKeys,
      onFailure: invalidLimits,
    );
    final maxRowsPerTable = requireStrictInt(
      limitsMap['max_rows_per_table'],
      min: 1,
      onFailure: invalidLimits,
    );
    final maxTotalRows = requireStrictInt(
      limitsMap['max_total_rows'],
      min: 1,
      onFailure: invalidLimits,
    );
    final maxJsonBytes = requireStrictInt(
      limitsMap['max_json_bytes'],
      min: 1,
      onFailure: invalidLimits,
    );
    if (maxRowsPerTable != accountExportV1MaxRowsPerTable ||
        maxTotalRows != accountExportV1MaxTotalRows ||
        maxJsonBytes != accountExportV1MaxJsonBytes) {
      throw const AccountSettingsContractException(
        'The account export limits do not match V2.',
      );
    }
    if (recordCounts.values.any((count) => count > maxRowsPerTable) ||
        recordCounts.values.fold<int>(0, (sum, count) => sum + count) >
            maxTotalRows) {
      throw const AccountSettingsContractException(
        'The account export exceeds its declared limits.',
      );
    }
    if (sourceBytes.length > maxJsonBytes) {
      throw const AccountSettingsContractException(
        'The account export exceeds its JSON size bound.',
      );
    }

    return AccountExportEnvelope._(
      exportedAt: exportedAt,
      data: data,
      recordCounts: recordCounts,
      sanitizedTables: List<String>.from(rawSanitized),
      omittedTables: Map<String, String>.from(rawOmitted),
      maxRowsPerTable: maxRowsPerTable,
      maxTotalRows: maxTotalRows,
      maxJsonBytes: maxJsonBytes,
      sourceBytes: Uint8List.fromList(sourceBytes),
    );
  }

  final String exportedAt;
  final Map<String, List<Map<String, dynamic>>> data;
  final Map<String, int> recordCounts;
  final List<String> sanitizedTables;
  final Map<String, String> omittedTables;
  final int maxRowsPerTable;
  final int maxTotalRows;
  final int maxJsonBytes;
  final Uint8List _sourceBytes;

  String get contractVersion => accountExportContractVersion;

  Uint8List get fileBytes => Uint8List.fromList(_sourceBytes);
}

enum AccountExportSaveResult { saved, shared, cancelled, shareDismissed }

bool _orderedValuesEqual(List<dynamic> actual, List<String> expected) {
  if (actual.length != expected.length) return false;
  for (var index = 0; index < actual.length; index += 1) {
    if (actual[index] != expected[index]) return false;
  }
  return true;
}

bool _stringMapsEqual(
  Map<String, String> actual,
  Map<String, String> expected,
) {
  if (actual.length != expected.length) return false;
  return expected.entries.every((entry) => actual[entry.key] == entry.value);
}
