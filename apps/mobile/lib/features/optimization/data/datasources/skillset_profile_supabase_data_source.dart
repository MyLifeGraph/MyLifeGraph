import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/supabase/app_user_resolver.dart';
import '../../../../core/supabase/supabase_tables.dart';
import '../../domain/entities/skillset_profile.dart';

class SkillsetProfileSupabaseDataSource {
  const SkillsetProfileSupabaseDataSource(
    this._client, {
    this.mapper = const SkillsetProfileSupabaseRowMapper(),
  });

  final SupabaseClient _client;
  final SkillsetProfileSupabaseRowMapper mapper;

  Future<SkillsetProfile> getLatestProfile() async {
    final userId = await AppUserResolver(_client).resolveUserId();
    final results = await Future.wait([
      _client
          .from(SupabaseTables.skillsetProfiles)
          .select('overall_score,archetype,scores,generated_at')
          .eq('user_id', userId)
          .order('generated_at', ascending: false)
          .order('id', ascending: false)
          .limit(1),
      _client
          .from(SupabaseTables.profiles)
          .select('display_name')
          .eq('id', userId)
          .limit(1),
    ]);
    final profileRows = List<Map<String, dynamic>>.from(results[0] as List);
    if (profileRows.isEmpty) {
      throw const SkillsetProfileUnavailableException(
        'No generated skillset profile is available yet.',
      );
    }
    final ownerRows = List<Map<String, dynamic>>.from(results[1] as List);
    final displayName = ownerRows.isEmpty
        ? null
        : _optionalNonBlankString(ownerRows.single['display_name']);
    return mapper.fromRow(profileRows.single, displayName: displayName);
  }
}

class SkillsetProfileSupabaseRowMapper {
  const SkillsetProfileSupabaseRowMapper();

  static const _rowKeys = {
    'overall_score',
    'archetype',
    'scores',
    'generated_at',
  };
  static const _scoreKeys = {'name', 'score', 'signal'};
  static const _maxScores = 32;

  SkillsetProfile fromRow(
    Map<String, dynamic> row, {
    String? displayName,
  }) {
    if (row.keys.toSet().difference(_rowKeys).isNotEmpty ||
        _rowKeys.difference(row.keys.toSet()).isNotEmpty) {
      throw const FormatException(
        'Skillset profile row must match the canonical contract.',
      );
    }
    final overallScore = _requiredBoundedInt(
      row['overall_score'],
      field: 'overall_score',
    );
    final archetype = _requiredNonBlankString(
      row['archetype'],
      field: 'archetype',
      maxLength: 100,
    );
    final rawScores = row['scores'];
    if (rawScores is! List || rawScores.length > _maxScores) {
      throw const FormatException(
        'scores must be a JSON array with at most 32 entries.',
      );
    }
    final scoreNames = <String>{};
    final scores = rawScores.map((raw) {
      if (raw is! Map) {
        throw const FormatException('Each skill score must be an object.');
      }
      final value = Map<String, dynamic>.from(raw);
      if (value.keys.toSet().difference(_scoreKeys).isNotEmpty ||
          _scoreKeys.difference(value.keys.toSet()).isNotEmpty) {
        throw const FormatException(
          'Each skill score must match the canonical contract.',
        );
      }
      final name = _requiredNonBlankString(
        value['name'],
        field: 'scores.name',
        maxLength: 100,
      );
      if (!scoreNames.add(name)) {
        throw const FormatException('Skill score names must be unique.');
      }
      return SkillScore(
        name: name,
        score: _requiredBoundedInt(value['score'], field: 'scores.score'),
        signal: _requiredNonBlankString(
          value['signal'],
          field: 'scores.signal',
          maxLength: 500,
        ),
      );
    }).toList(growable: false);
    final rawGeneratedAt = row['generated_at'];
    final generatedAt = rawGeneratedAt is String &&
            RegExp(r'(Z|[+-][0-9]{2}:[0-9]{2})$').hasMatch(rawGeneratedAt)
        ? DateTime.tryParse(rawGeneratedAt)
        : null;
    if (generatedAt == null || !generatedAt.isUtc) {
      throw const FormatException(
        'generated_at must be an ISO-8601 UTC timestamp.',
      );
    }
    final cleanDisplayName = displayName == null
        ? null
        : _requiredNonBlankString(
            displayName,
            field: 'display_name',
            maxLength: 200,
          );
    return SkillsetProfile(
      userName: cleanDisplayName ?? 'You',
      overallScore: overallScore,
      primaryArchetype: archetype,
      scores: scores,
      updatedAt: generatedAt,
    );
  }
}

String _requiredNonBlankString(
  Object? value, {
  required String field,
  required int maxLength,
}) {
  if (value is! String ||
      value.trim().isEmpty ||
      value.trim().length > maxLength) {
    throw FormatException(
      '$field must be a non-blank string with at most $maxLength characters.',
    );
  }
  return value.trim();
}

String? _optionalNonBlankString(Object? value) {
  if (value == null) return null;
  return _requiredNonBlankString(
    value,
    field: 'display_name',
    maxLength: 200,
  );
}

int _requiredBoundedInt(Object? value, {required String field}) {
  if (value is! int || value < 0 || value > 100) {
    throw FormatException('$field must be an integer from 0 to 100.');
  }
  return value;
}
