import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/features/optimization/data/datasources/skillset_profile_supabase_data_source.dart';

void main() {
  const mapper = SkillsetProfileSupabaseRowMapper();

  test('maps a bounded canonical skillset profile row', () {
    final profile = mapper.fromRow(
      {
        'overall_score': 82,
        'archetype': 'Focused Builder',
        'scores': [
          {'name': 'Recovery', 'score': 74, 'signal': 'Stable sleep'},
        ],
        'generated_at': '2026-07-13T10:00:00Z',
      },
      displayName: 'Alex',
    );

    expect(profile.userName, 'Alex');
    expect(profile.overallScore, 82);
    expect(profile.primaryArchetype, 'Focused Builder');
    expect(profile.scores.single.name, 'Recovery');
    expect(profile.scores.single.score, 74);
    expect(profile.updatedAt, DateTime.utc(2026, 7, 13, 10));
  });

  test('uses an honest owner fallback when display name is absent', () {
    final profile = mapper.fromRow({
      'overall_score': 0,
      'archetype': 'Starting point',
      'scores': const [],
      'generated_at': '2026-07-13T10:00:00Z',
    });

    expect(profile.userName, 'You');
  });

  test('rejects malformed or out-of-range persisted scores', () {
    expect(
      () => mapper.fromRow({
        'overall_score': 101,
        'archetype': 'Invalid',
        'scores': const [],
        'generated_at': '2026-07-13T10:00:00Z',
      }),
      throwsFormatException,
    );
    expect(
      () => mapper.fromRow({
        'overall_score': 50,
        'archetype': 'Coerced timestamp',
        'scores': const [],
        'generated_at': const _TimestampLike(),
      }),
      throwsFormatException,
    );
    expect(
      () => mapper.fromRow({
        'overall_score': 50,
        'archetype': 'Invalid',
        'scores': const [
          {'name': 'Focus', 'score': 1.5, 'signal': 'Fractional'},
        ],
        'generated_at': '2026-07-13T10:00:00Z',
      }),
      throwsFormatException,
    );
    expect(
      () => mapper.fromRow({
        'overall_score': 50.0,
        'archetype': 'Coerced',
        'scores': const [],
        'generated_at': '2026-07-13T10:00:00Z',
      }),
      throwsFormatException,
    );
  });

  test('rejects unknown keys, duplicate names, and unbounded content', () {
    expect(
      () => mapper.fromRow({
        'overall_score': 50,
        'archetype': 'Unknown key',
        'scores': const [],
        'generated_at': '2026-07-13T10:00:00Z',
        'unexpected': true,
      }),
      throwsFormatException,
    );
    expect(
      () => mapper.fromRow({
        'overall_score': 50,
        'archetype': 'Duplicates',
        'scores': const [
          {'name': 'Focus', 'score': 40, 'signal': 'One'},
          {'name': 'Focus', 'score': 50, 'signal': 'Two'},
        ],
        'generated_at': '2026-07-13T10:00:00Z',
      }),
      throwsFormatException,
    );
    expect(
      () => mapper.fromRow({
        'overall_score': 50,
        'archetype': List.filled(101, 'A').join(),
        'scores': const [],
        'generated_at': '2026-07-13T10:00:00Z',
      }),
      throwsFormatException,
    );
  });
}

class _TimestampLike {
  const _TimestampLike();

  @override
  String toString() => '2026-07-13T10:00:00Z';
}
