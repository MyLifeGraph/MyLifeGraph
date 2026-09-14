import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/features/quick_action/domain/capture_draft_proposal.dart';
import 'package:my_life_graph/features/quick_action/domain/quick_check_in.dart';
import 'package:my_life_graph/features/quick_action/domain/skillset_signals.dart';

Map<String, dynamic> wire(
  String branch,
  Map<String, Object?> fields, {
  String date = '2026-09-14',
}) => {
  'contract_version': dailyCaptureDraftVersion,
  'request_id': '5c281fae-9a65-4a04-bca9-3e01f5f0ca7c',
  'owner_id': 'owner-one',
  'entry_date': date,
  'timezone': 'Europe/Berlin',
  'branch': branch,
  'fields': fields,
  'evidence': {
    for (final entry in fields.entries)
      if (entry.value != null) entry.key: 'Explicit ${entry.value}',
  },
};

void main() {
  test('draft request identity must be a UUID', () {
    expect(
      () => CaptureDraftProposal.fromJson({
        ...wire('morning', {'current_energy': 7}),
        'request_id': 'request-one',
      }, ownerId: 'owner-one'),
      throwsFormatException,
    );
  });

  for (final absentValue in [false, true]) {
    test(
      'evidence cannot refer to ${absentValue ? 'null' : 'missing'} fields',
      () {
        final data = wire('morning', {
          'current_energy': 7,
          if (absentValue) 'motivation': null,
        });
        (data['evidence'] as Map<String, String>)['motivation'] =
            'Motivation 2';
        expect(
          () => CaptureDraftProposal.fromJson(data, ownerId: 'owner-one'),
          throwsFormatException,
        );
      },
    );
  }

  test('source excerpts obey the same 1000-character response bound', () {
    final data = wire('morning', {'current_energy': 7});
    (data['evidence'] as Map<String, String>)['current_energy'] = 'x' * 1001;
    expect(
      () => CaptureDraftProposal.fromJson(data, ownerId: 'owner-one'),
      throwsFormatException,
    );
  });

  test(
    'spoken stress context cannot create a hidden required field for low saved stress',
    () {
      final draft = EveningShutdownDraft.empty(
        DateTime(2026, 9, 14),
      ).copyWith(stress: 3);
      final proposal = CaptureDraftProposal.fromJson(
        wire('evening', {'stress_source': 'workload'}),
        ownerId: 'owner-one',
      );
      final applied = proposal.applyToEvening(draft, allowSkillset: true);
      expect(applied.stress, 3);
      expect(applied.stressSource, isNull);
      expect(applied.stressControllability, isNull);
      expect(applied.hasConsistentStressContext, isTrue);
    },
  );
  test('Morning proposal preserves identity and unmentioned saved values', () {
    final time = DateTime.utc(2026, 9, 14, 7);
    final original =
        MorningCalibrationDraft.empty(time, entryDate: '2026-09-14').copyWith(
          energy: 3,
          sleepQuality: 5,
          sleepTargetMinutes: 480,
          skillset: const SkillsetSignals({'motivation': 1}),
        );
    final proposal = CaptureDraftProposal.fromJson(
      wire('morning', {
        'sleep_start': '23:00',
        'wake_time': '07:00',
        'current_energy': 8,
        'sleep_quality': null,
      }),
      ownerId: 'owner-one',
    );
    final applied = proposal.applyToMorning(original, allowSkillset: true);
    expect(applied.captureId, original.captureId);
    expect(applied.capturedAt, original.capturedAt);
    expect(applied.energy, 8);
    expect(applied.sleepQuality, 5);
    expect(applied.skillset?.values, {'motivation': 1});
    expect(applied.estimatedSleepMinutes, 480);
    expect(
      applied.estimatedSleepStartedAt!.toUtc(),
      DateTime.utc(2026, 9, 13, 21),
    );
    expect(applied.wokeAt!.toUtc(), DateTime.utc(2026, 9, 14, 5));
    expect(applied.isComplete, isTrue);
  });

  test('partial Morning does not invent clocks, ratings or completeness', () {
    final proposal = CaptureDraftProposal.fromJson(
      wire('morning', {'wake_time': '07:00', 'motivation': 0}),
      ownerId: 'owner-one',
    );
    final applied = proposal.applyToMorning(
      MorningCalibrationDraft.empty(DateTime(2026, 9, 14)),
      allowSkillset: true,
    );
    expect(applied.estimatedSleepStartedAt, isNull);
    expect(applied.estimatedSleepMinutes, isNull);
    expect(applied.sleepQuality, isNull);
    expect(applied.energy, isNull);
    expect(applied.skillset?.values['motivation'], 0);
    expect(applied.isComplete, isFalse);
  });

  for (final date in ['2026-03-29', '2026-10-25']) {
    test(
      'ambiguous or nonexistent profile-local clock remains incomplete $date',
      () {
        final proposal = CaptureDraftProposal.fromJson(
          wire('morning', {
            'sleep_start': '02:30',
            'wake_time': '07:00',
          }, date: date),
          ownerId: 'owner-one',
        );
        final applied = proposal.applyToMorning(
          MorningCalibrationDraft.empty(DateTime.parse(date)),
          allowSkillset: true,
        );
        expect(applied.estimatedSleepStartedAt, isNull);
        expect(applied.wokeAt, isNull);
        expect(applied.estimatedSleepMinutes, isNull);
      },
    );
  }

  test('Evening preserves notes and conditional required stress context', () {
    final draft = EveningShutdownDraft.empty(DateTime(2026, 9, 14)).copyWith(
      reflectionNote: 'Keep note',
      specificBlocker: 'Keep blocker',
      skillset: const SkillsetSignals({'sport': 2, 'social': 1}),
    );
    final proposal = CaptureDraftProposal.fromJson(
      wire('evening', {
        'mood': 7,
        'energy': 8,
        'stress_intensity': 8,
        'planned_sleep_time': '23:00',
        'social': 0,
      }),
      ownerId: 'owner-one',
    );
    final applied = proposal.applyToEvening(draft, allowSkillset: true);
    expect(applied.captureId, draft.captureId);
    expect(applied.reflectionNote, 'Keep note');
    expect(applied.specificBlocker, 'Keep blocker');
    expect(applied.skillset?.values, {'sport': 2, 'social': 0});
    expect(applied.hasConsistentStressContext, isFalse);
    expect(applied.isComplete, isFalse);
  });

  test('explicit lower stress follows the existing manual context clear', () {
    final draft = EveningShutdownDraft.empty(DateTime(2026, 9, 14)).copyWith(
      stress: 8,
      stressSource: StressSource.workload,
      stressControllability: StressControllability.partlyControllable,
    );
    final proposal = CaptureDraftProposal.fromJson(
      wire('evening', {'stress_intensity': 3}),
      ownerId: 'owner-one',
    );
    final applied = proposal.applyToEvening(draft, allowSkillset: true);
    expect(applied.stressSource, isNull);
    expect(applied.stressControllability, isNull);
  });

  for (final field in [
    {'current_energy': 11},
    {'current_energy': 3.5},
    {'current_energy': true},
    {'sleep_start': '24:00'},
    {'sleep_target_minutes': 481},
    {'motivation': -1},
    {'invented_field': 4},
  ]) {
    test('invalid inferred values are rejected $field', () {
      expect(
        () => CaptureDraftProposal.fromJson(
          wire('morning', field),
          ownerId: 'owner-one',
        ),
        throwsFormatException,
      );
    });
  }

  test(
    'foreign owner, unknown version and unsupported evidence fail closed',
    () {
      final data = wire('morning', {'current_energy': 7});
      expect(
        () => CaptureDraftProposal.fromJson(data, ownerId: 'other'),
        throwsFormatException,
      );
      expect(
        () => CaptureDraftProposal.fromJson({
          ...data,
          'contract_version': 'future',
        }, ownerId: 'owner-one'),
        throwsFormatException,
      );
      expect(
        () => CaptureDraftProposal.fromJson({
          ...data,
          'evidence': {},
        }, ownerId: 'owner-one'),
        throwsFormatException,
      );
      final proposal = CaptureDraftProposal.fromJson(
        data,
        ownerId: 'owner-one',
      );
      expect(
        proposal.matches(
          ownerId: 'owner-one',
          entryDate: '2026-09-14',
          timezone: 'Europe/Berlin',
          branch: 'morning',
        ),
        isTrue,
      );
      expect(
        proposal.matches(
          ownerId: 'owner-one',
          entryDate: '2026-09-15',
          timezone: 'Europe/Berlin',
          branch: 'morning',
        ),
        isFalse,
      );
      expect(
        proposal.matches(
          ownerId: 'owner-one',
          entryDate: '2026-09-14',
          timezone: 'UTC',
          branch: 'morning',
        ),
        isFalse,
      );
    },
  );
}
