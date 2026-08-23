typedef StrictContractFailure = Never Function();

enum StrictStringWhitespace { preserve, requireTrimmed, trim }

enum StrictStringLength { codeUnits, runes }

void requireStrictKeys(
  Map<String, dynamic> value, {
  required Set<String> requiredKeys,
  Set<String> optionalKeys = const {},
  bool rejectExplicitNullOptionalKeys = false,
  required StrictContractFailure onFailure,
}) {
  final keys = value.keys.toSet();
  if (requiredKeys.difference(keys).isNotEmpty ||
      keys.difference({...requiredKeys, ...optionalKeys}).isNotEmpty ||
      rejectExplicitNullOptionalKeys &&
          optionalKeys.any(
            (key) => value.containsKey(key) && value[key] == null,
          )) {
    onFailure();
  }
}

Map<String, dynamic> requireStrictMap(
  Object? value, {
  required StrictContractFailure onFailure,
}) {
  if (value is! Map || value.keys.any((key) => key is! String)) {
    onFailure();
  }
  return Map<String, dynamic>.from(value);
}

List<dynamic> requireStrictList(
  Object? value, {
  int minItems = 0,
  int? maxItems,
  required StrictContractFailure onFailure,
}) {
  if (value is! List ||
      value.length < minItems ||
      maxItems != null && value.length > maxItems) {
    onFailure();
  }
  return value;
}

List<Map<String, dynamic>> requireStrictMapList(
  Object? value, {
  int minItems = 0,
  int? maxItems,
  required StrictContractFailure onFailure,
}) {
  final values = requireStrictList(
    value,
    minItems: minItems,
    maxItems: maxItems,
    onFailure: onFailure,
  );
  return values
      .map((item) => requireStrictMap(item, onFailure: onFailure))
      .toList(growable: false);
}

String requireStrictString(
  Object? value, {
  int minLength = 1,
  int? maxLength,
  StrictStringWhitespace whitespace = StrictStringWhitespace.requireTrimmed,
  StrictStringLength length = StrictStringLength.codeUnits,
  bool measureBeforeWhitespace = false,
  required StrictContractFailure onFailure,
}) {
  if (value is! String) onFailure();
  final result = switch (whitespace) {
    StrictStringWhitespace.preserve => value,
    StrictStringWhitespace.requireTrimmed =>
      value.trim() == value ? value : onFailure(),
    StrictStringWhitespace.trim => value.trim(),
  };
  final measuredValue = measureBeforeWhitespace ? value : result;
  final measuredLength = switch (length) {
    StrictStringLength.codeUnits => measuredValue.length,
    StrictStringLength.runes => measuredValue.runes.length,
  };
  if (measuredLength < minLength ||
      maxLength != null && measuredLength > maxLength) {
    onFailure();
  }
  return result;
}

bool requireStrictBool(
  Object? value, {
  required StrictContractFailure onFailure,
}) {
  if (value is! bool) onFailure();
  return value;
}

int requireStrictInt(
  Object? value, {
  int? min,
  int? max,
  required StrictContractFailure onFailure,
}) {
  if (value is! int ||
      min != null && value < min ||
      max != null && value > max) {
    onFailure();
  }
  return value;
}

bool isStrictUuid(
  String value, {
  int? minVersion,
  int? maxVersion,
  bool lowercaseOnly = true,
  bool requireRfcVariant = true,
}) {
  final pattern = lowercaseOnly
      ? RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
        )
      : RegExp(
          r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
        );
  if (!pattern.hasMatch(value)) return false;
  final version = int.parse(value[14], radix: 16);
  if (minVersion != null && version < minVersion ||
      maxVersion != null && version > maxVersion) {
    return false;
  }
  if (requireRfcVariant && !'89ab'.contains(value[19].toLowerCase())) {
    return false;
  }
  return true;
}

String requireStrictUuid(
  Object? value, {
  int? minVersion,
  int? maxVersion,
  bool lowercaseOnly = true,
  bool requireRfcVariant = true,
  required StrictContractFailure onFailure,
}) {
  if (value is! String ||
      !isStrictUuid(
        value,
        minVersion: minVersion,
        maxVersion: maxVersion,
        lowercaseOnly: lowercaseOnly,
        requireRfcVariant: requireRfcVariant,
      )) {
    onFailure();
  }
  return value;
}

bool isStrictLocalDate(String value, {int minimumYear = 0}) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) return false;
  final year = int.parse(value.substring(0, 4));
  if (year < minimumYear) return false;
  final parsed = DateTime.tryParse('${value}T00:00:00Z');
  if (parsed == null) return false;
  return '${parsed.year.toString().padLeft(4, '0')}-'
          '${parsed.month.toString().padLeft(2, '0')}-'
          '${parsed.day.toString().padLeft(2, '0')}' ==
      value;
}

String requireStrictLocalDate(
  Object? value, {
  int minimumYear = 0,
  required StrictContractFailure onFailure,
}) {
  if (value is! String || !isStrictLocalDate(value, minimumYear: minimumYear)) {
    onFailure();
  }
  return value;
}

bool isStrictLocalTime(
  String value, {
  bool secondsRequired = true,
  bool secondsAllowed = true,
  int? maxFractionDigits,
}) {
  final seconds = secondsRequired
      ? r':(\d{2})'
      : secondsAllowed
          ? r'(?::(\d{2}))?'
          : '';
  final fraction = secondsAllowed
      ? maxFractionDigits == null
          ? r'(?:\.\d+)?'
          : '(?:\\.\\d{1,$maxFractionDigits})?'
      : '';
  final match =
      RegExp('^(\\d{2}):(\\d{2})$seconds$fraction\$').firstMatch(value);
  if (match == null) return false;
  final hour = int.parse(match.group(1)!);
  final minute = int.parse(match.group(2)!);
  final second = match.groupCount >= 3 && match.group(3) != null
      ? int.parse(match.group(3)!)
      : 0;
  return hour <= 23 && minute <= 59 && second <= 59;
}

String requireStrictLocalTime(
  Object? value, {
  bool secondsRequired = true,
  bool secondsAllowed = true,
  int? maxFractionDigits,
  required StrictContractFailure onFailure,
}) {
  if (value is! String ||
      !isStrictLocalTime(
        value,
        secondsRequired: secondsRequired,
        secondsAllowed: secondsAllowed,
        maxFractionDigits: maxFractionDigits,
      )) {
    onFailure();
  }
  return value;
}

bool hasStrictTimezoneSuffix(String value) =>
    RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(value);

bool isStrictAwareDateTime(
  String value, {
  int? maxFractionDigits,
  bool exactSecondsFormat = true,
  bool validateDateAndTimeComponents = true,
}) {
  if (!hasStrictTimezoneSuffix(value)) return false;
  if (!exactSecondsFormat) return DateTime.tryParse(value) != null;
  final fraction = maxFractionDigits == null
      ? r'(?:\.\d+)?'
      : '(?:\\.\\d{1,$maxFractionDigits})?';
  final match = RegExp(
    '^(\\d{4})-(\\d{2})-(\\d{2})T(\\d{2}):(\\d{2}):(\\d{2})'
    '$fraction(Z|[+-]\\d{2}:\\d{2})\$',
  ).firstMatch(value);
  if (match == null) return false;
  if (!validateDateAndTimeComponents) {
    return DateTime.tryParse(value) != null;
  }
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final hour = int.parse(match.group(4)!);
  final minute = int.parse(match.group(5)!);
  final second = int.parse(match.group(6)!);
  final date = DateTime.utc(year, month, day);
  final offset = match.group(7)!;
  final validOffset = offset == 'Z' ||
      int.parse(offset.substring(1, 3)) <= 23 &&
          int.parse(offset.substring(4, 6)) <= 59;
  return date.year == year &&
      date.month == month &&
      date.day == day &&
      hour <= 23 &&
      minute <= 59 &&
      second <= 59 &&
      validOffset &&
      DateTime.tryParse(value) != null;
}

DateTime requireStrictAwareDateTime(
  Object? value, {
  int? maxFractionDigits,
  bool exactSecondsFormat = true,
  bool validateDateAndTimeComponents = true,
  bool requireUtcResult = false,
  required StrictContractFailure onFailure,
}) {
  if (value is! String ||
      !isStrictAwareDateTime(
        value,
        maxFractionDigits: maxFractionDigits,
        exactSecondsFormat: exactSecondsFormat,
        validateDateAndTimeComponents: validateDateAndTimeComponents,
      )) {
    onFailure();
  }
  final parsed = DateTime.parse(value);
  if (requireUtcResult && !parsed.isUtc) onFailure();
  return parsed;
}
