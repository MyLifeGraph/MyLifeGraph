import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/features/quick_action/data/guest_quick_check_in_data_source.dart';
import 'package:my_life_graph/features/quick_action/data/quick_check_in_supabase_data_source.dart';
import 'package:my_life_graph/features/quick_action/domain/quick_check_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('Phase 1 capture domain', () {
    test('accepts every bounded stress, friction, focus, and day-shape code',
        () {
      for (final value in StressSource.values) {
        expect(StressSource.fromCode(value.code), value);
      }
      for (final value in StressControllability.values) {
        expect(StressControllability.fromCode(value.code), value);
      }
      for (final value in FocusBand.values) {
        expect(FocusBand.fromCode(value.code), value);
      }
      for (final value in MainFriction.values) {
        expect(MainFriction.fromCode(value.code), value);
      }
      for (final value in DayShape.values) {
        expect(DayShape.fromCode(value.code), value);
      }
      expect(() => StressSource.fromCode('other'), throwsFormatException);
      expect(() => MainFriction.fromCode('other'), throwsFormatException);
      expect(() => DayShape.fromCode('other'), throwsFormatException);
    });

    test('evening metadata omits blank optionals and an unselected gentle flag',
        () {
      final metadata = _evening()
          .copyWith(
            reflectionNote: '   ',
            specificBlocker: '',
            makeTomorrowGentler: false,
          )
          .toMetadataJson();

      expect(metadata, containsPair('capture_kind', 'evening'));
      expect(metadata, containsPair('entry_date', '2026-07-10'));
      expect(metadata, containsPair('stress_intensity_label', 'high'));
      expect(metadata, containsPair('stress_source', 'private_emotional'));
      expect(
        metadata,
        containsPair('stress_controllability', 'hardly_controllable'),
      );
      expect(metadata, containsPair('main_friction', 'emotional_load'));
      expect(metadata.containsKey('reflection_note'), isFalse);
      expect(metadata.containsKey('specific_blocker'), isFalse);
      expect(metadata.containsKey('gentle_tomorrow'), isFalse);
    });

    test('evening metadata includes only explicitly supplied optionals', () {
      final metadata = _evening()
          .copyWith(
            reflectionNote: '  A real reflection  ',
            specificBlocker: '  Waiting for a reply  ',
            makeTomorrowGentler: true,
          )
          .toMetadataJson();

      expect(metadata['reflection_note'], 'A real reflection');
      expect(metadata['specific_blocker'], 'Waiting for a reply');
      expect(metadata['gentle_tomorrow'], isTrue);
    });

    test('strictly validates ratings, half-hour sleep, dates, and text bounds',
        () {
      expect(
        () => _evening().copyWith(stress: 11).validate(),
        throwsFormatException,
      );
      expect(
        () => _evening()
            .copyWith(
              tomorrowPriority: List.filled(
                EveningShutdownDraft.maxTomorrowPriorityLength + 1,
                'x',
              ).join(),
            )
            .validate(),
        throwsFormatException,
      );
      expect(
        () => _morning().copyWith(sleepHours: 6.25).validate(),
        throwsFormatException,
      );
      expect(
        () => _morning().copyWith(entryDate: '2026-02-31').validate(),
        throwsFormatException,
      );
    });

    test('same-day merge preserves both captures in either order', () {
      final morningThenEvening = DailyCaptureEntry(entryDate: _entryDate)
          .mergeMorning(_morning())
          .mergeEvening(_evening());
      final eveningThenMorning = DailyCaptureEntry(entryDate: _entryDate)
          .mergeEvening(_evening())
          .mergeMorning(_morning());

      for (final entry in [morningThenEvening, eveningThenMorning]) {
        expect(entry.evening?.stressSource, StressSource.privateEmotional);
        expect(entry.morning?.dayShape, DayShape.constrained);
        expect(entry.mood, 2);
        expect(entry.stress, 8);
        expect(entry.sleepHours, 5.5);
        expect(entry.energy, 4, reason: 'Morning energy owns compatibility');
        final captures = entry.toCaptureMetadata()['captures'] as Map;
        expect(captures.keys, containsAll(['evening', 'morning']));
      }
    });

    test('replacing one capture removes its cleared optionals only', () {
      final original = DailyCaptureEntry(entryDate: _entryDate)
          .mergeEvening(
            _evening().copyWith(
              reflectionNote: 'Old reflection',
              specificBlocker: 'Old blocker',
              makeTomorrowGentler: true,
            ),
          )
          .mergeMorning(_morning());
      final edited = original.mergeEvening(
        _evening(captureId: 'evening-edit').copyWith(
          reflectionNote: '',
          specificBlocker: '',
          makeTomorrowGentler: false,
        ),
      );

      expect(edited.morning?.captureId, 'morning-distinctive');
      final captures = edited.toCaptureMetadata()['captures'] as Map;
      final evening = captures['evening'] as Map;
      expect(evening.containsKey('reflection_note'), isFalse);
      expect(evening.containsKey('specific_blocker'), isFalse);
      expect(evening.containsKey('gentle_tomorrow'), isFalse);
    });
  });

  group('QuickCheckInPayloadBuilder', () {
    const builder = QuickCheckInPayloadBuilder();

    test('builds merged daily row and preserves foreign top-level metadata',
        () {
      final entry = DailyCaptureEntry(
        entryDate: _entryDate,
        preservedMetadata: const {
          'foreign_producer': {'kept': true},
        },
      ).mergeEvening(_evening()).mergeMorning(_morning());

      final row = builder.buildDailyLog(userId: 'user-123', entry: entry);

      expect(row['entry_date'], _entryDate);
      expect(row['mood_score'], 2);
      expect(row['energy_level'], 4);
      expect(row['sleep_hours'], 5.5);
      expect(row['stress_level'], 8);
      expect(row['mood_label'], 'very_low');
      expect(row['reflection'], isNull);
      expect(row['source'], 'quick_check_in');
      expect(row['steps'], isNull);
      final metadata = row['metadata'] as Map<String, dynamic>;
      expect(metadata['capture_version'], 'daily-capture-v2');
      expect(metadata['foreign_producer'], {'kept': true});
      final captures = metadata['captures'] as Map;
      expect(captures.keys, containsAll(['evening', 'morning']));
    });

    test('builds only explicit events and mirrors relevant structured context',
        () {
      final eveningOnly =
          DailyCaptureEntry(entryDate: _entryDate).mergeEvening(_evening());
      final morningOnly =
          DailyCaptureEntry(entryDate: _entryDate).mergeMorning(_morning());
      final merged = eveningOnly.mergeMorning(_morning());

      final eveningEvents = _events(builder, eveningOnly);
      final morningEvents = _events(builder, morningOnly);
      final mergedEvents = _events(builder, merged);

      expect(eveningEvents.map((event) => event['event_type']), [
        'mood',
        'energy',
        'stress',
      ]);
      expect(morningEvents.map((event) => event['event_type']), [
        'energy',
        'sleep',
      ]);
      expect(mergedEvents, hasLength(4));
      expect(mergedEvents.map((event) => event['id']).toSet(), hasLength(4));

      final stress = mergedEvents.singleWhere(
        (event) => event['event_type'] == 'stress',
      );
      expect(stress['value'], 8);
      expect(stress['unit'], 'score_0_10');
      expect(stress['source'], 'quick_check_in');
      expect(stress['metadata'], containsPair('capture_kind', 'evening'));
      expect(
        stress['metadata'],
        containsPair('stress_source', 'private_emotional'),
      );
      expect(
        stress['metadata'],
        containsPair('stress_controllability', 'hardly_controllable'),
      );
      final energy = mergedEvents.singleWhere(
        (event) => event['event_type'] == 'energy',
      );
      expect(energy['value'], 4);
      expect(energy['metadata'], containsPair('capture_kind', 'morning'));
      expect(energy['metadata'], containsPair('day_shape', 'constrained'));
    });

    test('event identities and payloads are stable across exact retries', () {
      final entry = DailyCaptureEntry(entryDate: _entryDate)
          .mergeEvening(_evening())
          .mergeMorning(_morning());

      expect(_events(builder, entry), _events(builder, entry));
    });
  });

  group('QuickCheckInDailyRowMapper', () {
    const mapper = QuickCheckInDailyRowMapper();

    test(
        'reads a V1 remote row without deriving its date from UTC capture time',
        () {
      final entry = mapper.map({
        'entry_date': '2026-07-10',
        'mood_score': 3,
        'energy_level': 6,
        'sleep_hours': 7.5,
        'stress_level': 5,
        'reflection': 'Legacy exact note',
        'updated_at': '2026-07-09T22:30:00.000Z',
        'metadata': {
          'capture_version': 'daily-check-in-v1',
          'capture_id': 'remote-legacy-capture',
          'captured_at': '2026-07-09T22:30:00.000Z',
          'context_note': 'Legacy exact note',
          'foreign_producer': {'kept': true},
        },
      });

      expect(entry.entryDate, '2026-07-10');
      expect(entry.legacy?.captureId, 'remote-legacy-capture');
      expect(entry.mood, 3);
      expect(entry.energy, 6);
      expect(entry.sleepHours, 7.5);
      expect(entry.stress, 5);
      expect(entry.preservedMetadata, {
        'foreign_producer': {'kept': true},
      });
    });

    test('round-trips typed capture branches and compatibility values', () {
      const builder = QuickCheckInPayloadBuilder();
      final original = DailyCaptureEntry(entryDate: _entryDate)
          .mergeEvening(_evening())
          .mergeMorning(_morning());
      final row = builder.buildDailyLog(userId: 'user-123', entry: original);

      final decoded = mapper.map(row);

      expect(decoded.evening?.captureId, 'evening-distinctive');
      expect(decoded.morning?.captureId, 'morning-distinctive');
      expect(decoded.energy, 4);
      expect(decoded.sleepHours, 5.5);
      expect(decoded.stress, 8);
    });
  });

  group('GuestQuickCheckInDataSource', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('merges morning then evening, persists exact values, and deduplicates',
        () async {
      final store = GuestQuickCheckInDataSource();

      await store.saveMorning(_morning());
      await store.saveEvening(_evening());
      await store.saveEvening(_evening());

      final values = await store.readAll();
      expect(values, hasLength(1));
      expect(values.single.energy, 4);
      expect(values.single.evening?.tomorrowPriority, 'Protect a calm start');
      expect(values.single.morning?.dayShape, DayShape.constrained);

      final prefs = await SharedPreferences.getInstance();
      final raw = jsonDecode(
        prefs.getString(GuestQuickCheckInDataSource.storageKey)!,
      ) as List<dynamic>;
      expect(raw, hasLength(1));
      final captures = (raw.single as Map)['captures'] as Map;
      final evening = captures['evening'] as Map;
      expect(evening.containsKey('reflection_note'), isFalse);
      expect(evening.containsKey('specific_blocker'), isFalse);
      expect(evening.containsKey('gentle_tomorrow'), isFalse);
    });

    test('reads a V1 guest row with its explicit calendar date unchanged',
        () async {
      SharedPreferences.setMockInitialValues({
        GuestQuickCheckInDataSource.storageKey: jsonEncode([
          {
            'captureId': 'legacy-capture',
            'createdAt': '2026-07-09T22:30:00.000Z',
            'entryDate': '2026-07-10',
            'mood': 3,
            'energy': 6,
            'sleepHours': 7.5,
            'stress': 5,
            'contextNote': 'Legacy exact note',
          },
        ]),
      });
      final store = GuestQuickCheckInDataSource();

      final value = await store.loadToday(DateTime(2026, 7, 10));

      expect(value?.entryDate, '2026-07-10');
      expect(value?.legacy?.captureId, 'legacy-capture');
      expect(value?.mood, 3);
      expect(value?.energy, 6);
      expect(value?.sleepHours, 7.5);
      expect(value?.stress, 5);
    });

    test('a new save can recover corrupted local storage', () async {
      SharedPreferences.setMockInitialValues({
        GuestQuickCheckInDataSource.storageKey: '{not-json',
      });
      final store = GuestQuickCheckInDataSource();

      await store.saveMorning(_morning());

      final values = await store.readAll();
      expect(values, hasLength(1));
      expect(values.single.morning?.captureId, 'morning-distinctive');
    });
  });
}

const _entryDate = '2026-07-10';
const _dailyLogId = '11111111-1111-4111-8111-111111111111';

EveningShutdownDraft _evening({
  String captureId = 'evening-distinctive',
}) {
  return EveningShutdownDraft(
    captureId: captureId,
    entryDate: _entryDate,
    capturedAt: DateTime.parse('2026-07-10T19:45:00+02:00'),
    mood: 2,
    energy: 9,
    stress: 8,
    stressSource: StressSource.privateEmotional,
    stressControllability: StressControllability.hardlyControllable,
    focusBand: FocusBand.thirtyToSixtyMinutes,
    mainFriction: MainFriction.emotionalLoad,
    tomorrowPriority: 'Protect a calm start',
  );
}

MorningCalibrationDraft _morning() {
  return MorningCalibrationDraft(
    captureId: 'morning-distinctive',
    entryDate: _entryDate,
    capturedAt: DateTime.parse('2026-07-10T07:15:00+02:00'),
    sleepHours: 5.5,
    energy: 4,
    dayShape: DayShape.constrained,
  );
}

List<Map<String, dynamic>> _events(
  QuickCheckInPayloadBuilder builder,
  DailyCaptureEntry entry,
) {
  return builder.buildBehavioralEvents(
    userId: 'user-123',
    dailyLogId: _dailyLogId,
    entry: entry,
  );
}
