import 'dart:convert';
import 'dart:typed_data';

const accountExportV1TableNames = <String>[
  'profiles',
  'notification_preferences',
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
  'goals',
  'habits',
  'habit_logs',
  'focus_sessions',
  'intake_responses',
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
  'deadline_plans',
  'deadline_plan_revisions',
  'deadline_plan_blocks',
];
const accountExportV1SanitizedTables = <String>[
  'calendar_connections',
  'calendar_imports',
  'calendar_events',
  'coach_requests',
  'coach_usage_events',
];
const accountExportV1OmittedTables = <String, String>{
  'calendar_request_identities': 'backend_only_anti_replay_ledger',
  'notification_action_requests': 'backend_only_anti_replay_ledger',
  'deadline_plan_request_identities': 'backend_only_anti_replay_ledger',
};
const accountExportV1MaxRowsPerTable = 10000;
const accountExportV1MaxTotalRows = 50000;
const accountExportV1MaxJsonBytes = 8 * 1024 * 1024;

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
    if (json.keys.toSet().difference(topLevelKeys).isNotEmpty ||
        topLevelKeys.difference(json.keys.toSet()).isNotEmpty ||
        json['contract_version'] != 'account-export-v1') {
      throw const AccountSettingsContractException(
        'The account export response has an invalid top-level contract.',
      );
    }
    final exportedAt = json['exported_at'];
    if (exportedAt is! String ||
        !RegExp(r'(Z|[+-][0-9]{2}:[0-9]{2})$').hasMatch(exportedAt) ||
        DateTime.tryParse(exportedAt) == null) {
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
        if (row is! Map || row.keys.any((key) => key is! String)) {
          throw const AccountSettingsContractException(
            'An account export row is invalid.',
          );
        }
        rows.add(Map<String, dynamic>.from(row));
      }
      data[entry.key as String] = rows;
    }
    final recordCounts = <String, int>{};
    for (final entry in rawCounts.entries) {
      if (entry.key is! String || entry.value is! int || entry.value < 0) {
        throw const AccountSettingsContractException(
          'The account export record counts are invalid.',
        );
      }
      recordCounts[entry.key as String] = entry.value as int;
    }
    if (data.keys.toSet().difference(recordCounts.keys.toSet()).isNotEmpty ||
        recordCounts.keys.toSet().difference(data.keys.toSet()).isNotEmpty ||
        data.keys
            .toSet()
            .difference(accountExportV1TableNames.toSet())
            .isNotEmpty ||
        accountExportV1TableNames
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
    if (ledgerPolicy is! Map ||
        ledgerPolicy.keys.toSet().difference(
          const {'sanitized_tables', 'omitted_tables'},
        ).isNotEmpty ||
        !ledgerPolicy.containsKey('sanitized_tables') ||
        !ledgerPolicy.containsKey('omitted_tables')) {
      throw const AccountSettingsContractException(
        'The account export ledger policy is invalid.',
      );
    }
    final rawSanitized = ledgerPolicy['sanitized_tables'];
    final rawOmitted = ledgerPolicy['omitted_tables'];
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
        'The account export ledger policy does not match V1.',
      );
    }

    final limits = json['limits'];
    const limitKeys = {
      'max_rows_per_table',
      'max_total_rows',
      'max_json_bytes',
    };
    if (limits is! Map ||
        limits.keys.toSet().difference(limitKeys).isNotEmpty ||
        limitKeys.difference(limits.keys.toSet()).isNotEmpty ||
        limits.values.any((value) => value is! int || value <= 0)) {
      throw const AccountSettingsContractException(
        'The account export limits are invalid.',
      );
    }
    final maxRowsPerTable = limits['max_rows_per_table'] as int;
    final maxTotalRows = limits['max_total_rows'] as int;
    final maxJsonBytes = limits['max_json_bytes'] as int;
    if (maxRowsPerTable != accountExportV1MaxRowsPerTable ||
        maxTotalRows != accountExportV1MaxTotalRows ||
        maxJsonBytes != accountExportV1MaxJsonBytes) {
      throw const AccountSettingsContractException(
        'The account export limits do not match V1.',
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

  String get contractVersion => 'account-export-v1';

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
