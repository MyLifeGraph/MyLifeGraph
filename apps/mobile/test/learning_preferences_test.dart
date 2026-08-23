import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/features/learning/domain/learning_preferences.dart';

void main() {
  Map<String, dynamic> settings() => {
        'contract_version': learningPreferencesContractVersion,
        'revision': 2,
        'focus_reflection_prompt_enabled': true,
        'personal_pattern_analysis_enabled': true,
        'learned_focus_planning_enabled': false,
        'updated_at': '2026-08-02T09:30:00Z',
        'replayed': false,
      };

  test('learning settings retain exact scalar and cross-field contracts', () {
    final parsed = LearningPreferences.fromJson(settings());
    expect(parsed.revision, 2);
    expect(parsed.updatedAt, DateTime.utc(2026, 8, 2, 9, 30));

    final invalidValues = <Map<String, dynamic>>[
      {...settings(), 'unknown': true},
      {...settings()}..remove('revision'),
      {...settings(), 'replayed': null},
      {...settings(), 'revision': true},
      {...settings(), 'updated_at': '2026-08-02T09:30:00'},
      {
        ...settings(),
        'personal_pattern_analysis_enabled': false,
        'learned_focus_planning_enabled': true,
      },
    ];
    for (final value in invalidValues) {
      expect(
        () => LearningPreferences.fromJson(value),
        throwsA(isA<LearningContractException>()),
      );
    }
  });

  test('learning request UUIDs remain lowercase RFC UUIDs', () {
    expect(
      () => LearningPreferencesUpdate(
        requestId: '123e4567-e89b-42d3-a456-426614174000',
        expectedRevision: 0,
        focusReflectionPromptEnabled: true,
        personalPatternAnalysisEnabled: true,
        learnedFocusPlanningEnabled: false,
      ),
      returnsNormally,
    );
    for (final requestId in [
      '123E4567-E89B-42D3-A456-426614174000',
      '123e4567-e89b-92d3-a456-426614174000',
      '123e4567-e89b-42d3-7456-426614174000',
    ]) {
      expect(
        () => FocusReflectionHistoryClearRequest(
          requestId: requestId,
          expectedRevision: 0,
        ),
        throwsA(isA<LearningContractException>()),
      );
    }
  });

  test('history clear result rejects shape, numeric, and timestamp coercion',
      () {
    Map<String, dynamic> result() => {
          'contract_version': focusReflectionContractVersion,
          'revision': 3,
          'deleted_count': 4,
          'cleared_at': '2026-08-02T09:30:00+02:00',
          'replayed': false,
        };
    expect(
      FocusReflectionHistoryClearResult.fromJson(result()).deletedCount,
      4,
    );
    for (final value in <Map<String, dynamic>>[
      {...result(), 'unknown': true},
      {...result(), 'deleted_count': 4.0},
      {...result(), 'replayed': 0},
      {...result(), 'cleared_at': '2026-08-02'},
    ]) {
      expect(
        () => FocusReflectionHistoryClearResult.fromJson(value),
        throwsA(isA<LearningContractException>()),
      );
    }
  });
}
