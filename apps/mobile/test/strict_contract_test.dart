import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/contracts/strict_contract.dart';

Never _fail() => throw const FormatException('invalid');

void main() {
  group('strict contract keys', () {
    test('accepts exact required and optional keys', () {
      requireStrictKeys(
        {'required': 1, 'optional': true},
        requiredKeys: const {'required'},
        optionalKeys: const {'optional'},
        rejectExplicitNullOptionalKeys: true,
        onFailure: _fail,
      );
    });

    test('rejects unknown, missing, and explicit-null optional keys', () {
      for (final value in [
        {'required': 1, 'unknown': true},
        <String, dynamic>{},
        {'required': 1, 'optional': null},
      ]) {
        expect(
          () => requireStrictKeys(
            value,
            requiredKeys: const {'required'},
            optionalKeys: const {'optional'},
            rejectExplicitNullOptionalKeys: true,
            onFailure: _fail,
          ),
          throwsFormatException,
        );
      }
    });
  });

  test('maps and lists reject invalid nested shapes and item bounds', () {
    expect(
      requireStrictMap({'value': 1}, onFailure: _fail),
      {'value': 1},
    );
    expect(
      () => requireStrictMap({1: 'value'}, onFailure: _fail),
      throwsFormatException,
    );
    expect(
      requireStrictMapList(
        [
          {'value': 1},
        ],
        minItems: 1,
        maxItems: 1,
        onFailure: _fail,
      ),
      [
        {'value': 1},
      ],
    );
    for (final value in [
      <dynamic>[],
      [
        {'value': 1},
        {'value': 2},
      ],
      [true],
    ]) {
      expect(
        () => requireStrictMapList(
          value,
          minItems: 1,
          maxItems: 1,
          onFailure: _fail,
        ),
        throwsFormatException,
      );
    }
  });

  test('scalars preserve whitespace, Unicode, and numeric strictness', () {
    expect(
      requireStrictString(
        '😀',
        maxLength: 1,
        length: StrictStringLength.runes,
        onFailure: _fail,
      ),
      '😀',
    );
    expect(
      requireStrictString(
        ' value ',
        maxLength: 5,
        whitespace: StrictStringWhitespace.trim,
        onFailure: _fail,
      ),
      'value',
    );
    expect(
      () => requireStrictString(
        ' value ',
        maxLength: 5,
        whitespace: StrictStringWhitespace.trim,
        measureBeforeWhitespace: true,
        onFailure: _fail,
      ),
      throwsFormatException,
    );
    expect(
      () => requireStrictString(' value ', maxLength: 7, onFailure: _fail),
      throwsFormatException,
    );
    expect(
      () => requireStrictString('😀', maxLength: 1, onFailure: _fail),
      throwsFormatException,
    );
    expect(requireStrictInt(2, min: 1, max: 2, onFailure: _fail), 2);
    for (final value in <Object?>[true, 2.0, 0, 3]) {
      expect(
        () => requireStrictInt(value, min: 1, max: 2, onFailure: _fail),
        throwsFormatException,
      );
    }
    expect(requireStrictBool(false, onFailure: _fail), isFalse);
    expect(
      () => requireStrictBool(0, onFailure: _fail),
      throwsFormatException,
    );
  });

  test('UUID validation keeps case, version, and variant configurable', () {
    const v4 = '123e4567-e89b-42d3-a456-426614174000';
    expect(
      requireStrictUuid(
        v4,
        minVersion: 1,
        maxVersion: 5,
        onFailure: _fail,
      ),
      v4,
    );
    for (final value in [
      '123e4567-e89b-92d3-a456-426614174000',
      '123E4567-E89B-42D3-A456-426614174000',
      '123e4567-e89b-42d3-7456-426614174000',
    ]) {
      expect(
        () => requireStrictUuid(
          value,
          minVersion: 1,
          maxVersion: 5,
          onFailure: _fail,
        ),
        throwsFormatException,
      );
    }
    expect(
      isStrictUuid(
        '123E4567-E89B-42D3-A456-426614174000',
        lowercaseOnly: false,
      ),
      isTrue,
    );
  });

  test('date and time validators reject invalid calendar values', () {
    expect(
      requireStrictLocalDate('2026-02-28', onFailure: _fail),
      '2026-02-28',
    );
    for (final value in ['2026-02-30', '2026-2-03', 'not-a-date']) {
      expect(
        () => requireStrictLocalDate(value, onFailure: _fail),
        throwsFormatException,
      );
    }
    expect(
      requireStrictLocalTime(
        '23:59:59.123456',
        maxFractionDigits: 6,
        onFailure: _fail,
      ),
      '23:59:59.123456',
    );
    for (final value in ['24:00:00', '23:60:00', '23:59', '23:59:59.1234567']) {
      expect(
        () => requireStrictLocalTime(
          value,
          maxFractionDigits: 6,
          onFailure: _fail,
        ),
        throwsFormatException,
      );
    }
  });

  test('aware timestamps require valid dates, offsets, and configured shape',
      () {
    expect(
      requireStrictAwareDateTime(
        '2026-02-28T23:59:59.123456+02:00',
        maxFractionDigits: 6,
        onFailure: _fail,
      ).isUtc,
      isTrue,
    );
    for (final value in [
      '2026-02-30T12:00:00Z',
      '2026-02-28T12:00:00',
      '2026-02-28T24:00:00Z',
      '2026-02-28T12:00:00+24:00',
      '2026-02-28T12:00:00.1234567Z',
    ]) {
      expect(
        () => requireStrictAwareDateTime(
          value,
          maxFractionDigits: 6,
          onFailure: _fail,
        ),
        throwsFormatException,
      );
    }
    expect(
      requireStrictAwareDateTime(
        '2026-02-30T12:00:00Z',
        validateDateAndTimeComponents: false,
        onFailure: _fail,
      ),
      DateTime.utc(2026, 3, 2, 12),
    );
  });
}
