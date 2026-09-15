import 'package:flutter/foundation.dart';

const focusProtectionAppCatalogConsent = 'app_catalog';
const focusProtectionAccessibilityConsent = 'accessibility';
const focusProtectionNotificationPolicyConsent = 'notification_policy';
const focusProtectionConsentVersion = 1;

enum AppBlockingMode { focus, weekly, always }

@immutable
class AppBlockingRule {
  AppBlockingRule({this.focus = true, this.weekly = false, this.always = false,
    Iterable<int> weekdays = const [1, 2, 3, 4, 5], this.startMinute = 1320,
    this.endMinute = 420, this.untilEpochMs = 0}) : weekdays = Set.unmodifiable(weekdays) {
    if (this.weekdays.isEmpty || this.weekdays.any((d) => d < 1 || d > 7) ||
        startMinute < 0 || startMinute > 1439 || endMinute < 0 || endMinute > 1439 ||
        startMinute == endMinute || untilEpochMs < 0) {
      throw const FormatException('Invalid blocking rule.');
    }
  }
  final bool focus, weekly, always;
  final Set<int> weekdays;
  final int startMinute, endMinute, untilEpochMs;
  factory AppBlockingRule.fromMap(Map<Object?, Object?> map) => AppBlockingRule(
    focus: map['focus'] as bool, weekly: map['weekly'] as bool, always: map['always'] as bool,
    weekdays: (map['weekdays'] as List).cast<int>(), startMinute: map['startMinute'] as int,
    endMinute: map['endMinute'] as int, untilEpochMs: map['untilEpochMs'] as int);
  Map<String, Object> toMap() => {'focus': focus, 'weekly': weekly, 'always': always,
    'weekdays': weekdays.toList()..sort(), 'startMinute': startMinute, 'endMinute': endMinute, 'untilEpochMs': untilEpochMs};
}

class InstalledLaunchableApp {
  const InstalledLaunchableApp({
    required this.packageName,
    required this.label,
  });

  factory InstalledLaunchableApp.fromMap(Map<Object?, Object?> map) {
    final packageName = map['packageName'];
    final label = map['label'];
    if (packageName is! String ||
        packageName.trim().isEmpty ||
        label is! String ||
        label.trim().isEmpty) {
      throw const FormatException('Invalid launchable app response.');
    }
    return InstalledLaunchableApp(
      packageName: packageName.trim(),
      label: label.trim(),
    );
  }

  final String packageName;
  final String label;
}

@immutable
class FocusProtectionConfiguration {
  FocusProtectionConfiguration({
    required this.enabled,
    required this.blockSelectedApps,
    required this.silenceNotifications,
    Iterable<String> selectedPackages = const [],
    Map<String, int> consentVersions = const {},
    this.blockingMode = AppBlockingMode.focus,
    Iterable<int> weekdays = const [1, 2, 3, 4, 5],
    this.startMinute = 9 * 60,
    this.endMinute = 17 * 60,
    Map<String, AppBlockingRule> appRules = const {},
  }) : selectedPackages = Set.unmodifiable(
         selectedPackages
             .map((value) => value.trim())
             .where((value) => value.isNotEmpty),
       ),
       appRules = Map.unmodifiable(appRules),
       weekdays = Set.unmodifiable(weekdays),
       consentVersions = Map.unmodifiable(consentVersions) {
    if (this.weekdays.isEmpty ||
        this.weekdays.any((day) => day < 1 || day > 7) ||
        startMinute < 0 ||
        startMinute >= 1440 ||
        endMinute < 0 ||
        endMinute >= 1440 ||
        startMinute == endMinute) {
      throw const FormatException('Invalid app-blocking schedule.');
    }
  }

  factory FocusProtectionConfiguration.fromMap(Map<Object?, Object?> map) {
    final rawPackages = map['selectedPackages'];
    final rawConsents = map['consentVersions'];
    if (map['enabled'] is! bool ||
        map['blockSelectedApps'] is! bool ||
        map['silenceNotifications'] is! bool ||
        rawPackages is! List ||
        rawConsents is! Map) {
      throw const FormatException('Invalid focus protection configuration.');
    }
    final packages = <String>[];
    for (final value in rawPackages) {
      if (value is! String || value.trim().isEmpty) {
        throw const FormatException('Invalid selected package.');
      }
      packages.add(value);
    }
    final consents = <String, int>{};
    for (final entry in rawConsents.entries) {
      if (entry.key is! String ||
          entry.value is! int ||
          (entry.value as int) < 1) {
        throw const FormatException('Invalid consent version.');
      }
      consents[entry.key as String] = entry.value as int;
    }
    return FocusProtectionConfiguration(
      enabled: map['enabled'] as bool,
      blockSelectedApps: map['blockSelectedApps'] as bool,
      silenceNotifications: map['silenceNotifications'] as bool,
      selectedPackages: packages,
      consentVersions: consents,
      blockingMode: AppBlockingMode.values.byName(
        map['blockingMode'] as String? ?? 'focus',
      ),
      weekdays:
          (map['weekdays'] as List?)?.cast<int>() ?? const [1, 2, 3, 4, 5],
      startMinute: map['startMinute'] as int? ?? 9 * 60,
      endMinute: map['endMinute'] as int? ?? 17 * 60,
      appRules: (map['appRules'] as Map? ?? const {}).map((key, value) => MapEntry(key as String, AppBlockingRule.fromMap(value as Map))),
    );
  }

  factory FocusProtectionConfiguration.disabled() =>
      FocusProtectionConfiguration(
        enabled: false,
        blockSelectedApps: true,
        silenceNotifications: true,
      );

  final bool enabled;
  final bool blockSelectedApps;
  final bool silenceNotifications;
  final Set<String> selectedPackages;
  final Map<String, int> consentVersions;
  final AppBlockingMode blockingMode;
  final Set<int> weekdays;
  final int startMinute;
  final int endMinute;
  final Map<String, AppBlockingRule> appRules;

  AppBlockingRule ruleFor(String package) => appRules[package] ?? AppBlockingRule(
    focus: blockingMode == AppBlockingMode.focus, weekly: blockingMode == AppBlockingMode.weekly,
    always: blockingMode == AppBlockingMode.always, weekdays: weekdays, startMinute: startMinute, endMinute: endMinute);

  bool hasConsent(String kind) =>
      (consentVersions[kind] ?? 0) >= focusProtectionConsentVersion;

  FocusProtectionConfiguration copyWith({
    bool? enabled,
    bool? blockSelectedApps,
    bool? silenceNotifications,
    Iterable<String>? selectedPackages,
    Map<String, int>? consentVersions,
    AppBlockingMode? blockingMode,
    Iterable<int>? weekdays,
    int? startMinute,
    int? endMinute,
    Map<String, AppBlockingRule>? appRules,
  }) {
    return FocusProtectionConfiguration(
      enabled: enabled ?? this.enabled,
      blockSelectedApps: blockSelectedApps ?? this.blockSelectedApps,
      silenceNotifications: silenceNotifications ?? this.silenceNotifications,
      selectedPackages: selectedPackages ?? this.selectedPackages,
      consentVersions: consentVersions ?? this.consentVersions,
      blockingMode: blockingMode ?? this.blockingMode,
      weekdays: weekdays ?? this.weekdays,
      startMinute: startMinute ?? this.startMinute,
      endMinute: endMinute ?? this.endMinute,
      appRules: appRules ?? this.appRules,
    );
  }

  Map<String, Object> toMap() => {
    'enabled': enabled,
    'blockSelectedApps': blockSelectedApps,
    'silenceNotifications': silenceNotifications,
    'selectedPackages': selectedPackages.toList()..sort(),
    'consentVersions': consentVersions,
    'blockingMode': blockingMode.name,
    'weekdays': weekdays.toList()..sort(),
    'startMinute': startMinute,
    'endMinute': endMinute,
    'appRules': appRules.map((key, value) => MapEntry(key, value.toMap())),
  };
}

enum FocusProtectionLeaseState {
  active('active'),
  expired('expired'),
  emergencyReleased('emergency_released');

  const FocusProtectionLeaseState(this.code);
  final String code;

  static FocusProtectionLeaseState? fromCode(Object? value) {
    for (final state in values) {
      if (state.code == value) return state;
    }
    return null;
  }
}

@immutable
class FocusProtectionLease {
  const FocusProtectionLease({
    required this.sessionId,
    required this.startedAt,
    required this.endsAt,
    required this.state,
  });

  factory FocusProtectionLease.fromMap(Map<Object?, Object?> map) {
    final sessionId = map['sessionId'];
    final startedAtMs = map['startedAtEpochMs'];
    final endsAtMs = map['endsAtEpochMs'];
    final state = FocusProtectionLeaseState.fromCode(map['state']);
    if (sessionId is! String ||
        sessionId.trim().isEmpty ||
        startedAtMs is! int ||
        endsAtMs is! int ||
        endsAtMs <= startedAtMs ||
        state == null) {
      throw const FormatException('Invalid focus protection lease.');
    }
    return FocusProtectionLease(
      sessionId: sessionId.trim(),
      startedAt: DateTime.fromMillisecondsSinceEpoch(startedAtMs),
      endsAt: DateTime.fromMillisecondsSinceEpoch(endsAtMs),
      state: state,
    );
  }

  final String sessionId;
  final DateTime startedAt;
  final DateTime endsAt;
  final FocusProtectionLeaseState state;

  bool get isActive =>
      state == FocusProtectionLeaseState.active &&
      endsAt.isAfter(DateTime.now());
}

enum FocusProtectionWarning {
  accessibilityDisabled('accessibility_disabled'),
  notificationPolicyMissing('notification_policy_missing'),
  dndUnsupported('dnd_unsupported'),
  noAppsSelected('no_apps_selected'),
  zenRuleMissingOrOverridden('zen_rule_missing_or_overridden'),
  nativeFailure('native_failure');

  const FocusProtectionWarning(this.code);
  final String code;

  static FocusProtectionWarning? fromCode(Object? value) {
    for (final warning in values) {
      if (warning.code == value) return warning;
    }
    return null;
  }
}

@immutable
class FocusProtectionStatus {
  FocusProtectionStatus({
    required this.platformSupported,
    required this.accessibilityEnabled,
    required this.notificationPolicyGranted,
    required this.configuration,
    required this.lease,
    this.configurationKnown = true,
    Iterable<String> activeMechanisms = const [],
    Iterable<FocusProtectionWarning> warnings = const [],
  }) : activeMechanisms = Set.unmodifiable(activeMechanisms),
       warnings = Set.unmodifiable(warnings);

  factory FocusProtectionStatus.fromMap(Map<Object?, Object?> map) {
    final rawConfiguration = map['configuration'];
    final rawLease = map['lease'];
    final rawMechanisms = map['activeMechanisms'];
    final rawWarnings = map['warnings'];
    if (map['platformSupported'] is! bool ||
        map['accessibilityEnabled'] is! bool ||
        map['notificationPolicyGranted'] is! bool ||
        rawConfiguration is! Map ||
        rawMechanisms is! List ||
        rawWarnings is! List) {
      throw const FormatException('Invalid focus protection status.');
    }
    final warnings = <FocusProtectionWarning>[];
    for (final value in rawWarnings) {
      final warning = FocusProtectionWarning.fromCode(value);
      if (warning != null) warnings.add(warning);
    }
    return FocusProtectionStatus(
      platformSupported: map['platformSupported'] as bool,
      accessibilityEnabled: map['accessibilityEnabled'] as bool,
      notificationPolicyGranted: map['notificationPolicyGranted'] as bool,
      configuration: FocusProtectionConfiguration.fromMap(rawConfiguration),
      lease: rawLease is Map ? FocusProtectionLease.fromMap(rawLease) : null,
      activeMechanisms: rawMechanisms.whereType<String>(),
      warnings: warnings,
    );
  }

  factory FocusProtectionStatus.nativeFailure({
    FocusProtectionConfiguration? configuration,
  }) {
    return FocusProtectionStatus(
      platformSupported: true,
      accessibilityEnabled: false,
      notificationPolicyGranted: false,
      configuration: configuration ?? FocusProtectionConfiguration.disabled(),
      lease: null,
      configurationKnown: configuration != null,
      warnings: const [FocusProtectionWarning.nativeFailure],
    );
  }

  final bool platformSupported;
  final bool accessibilityEnabled;
  final bool notificationPolicyGranted;
  final FocusProtectionConfiguration configuration;
  final FocusProtectionLease? lease;
  final bool configurationKnown;
  final Set<String> activeMechanisms;
  final Set<FocusProtectionWarning> warnings;
}
