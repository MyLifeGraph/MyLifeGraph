import 'package:flutter/foundation.dart';

const focusProtectionAppCatalogConsent = 'app_catalog';
const focusProtectionAccessibilityConsent = 'accessibility';
const focusProtectionNotificationPolicyConsent = 'notification_policy';
const focusProtectionConsentVersion = 1;

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
  })  : selectedPackages = Set.unmodifiable(
          selectedPackages.map((value) => value.trim()).where(
                (value) => value.isNotEmpty,
              ),
        ),
        consentVersions = Map.unmodifiable(consentVersions);

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

  bool hasConsent(String kind) =>
      (consentVersions[kind] ?? 0) >= focusProtectionConsentVersion;

  FocusProtectionConfiguration copyWith({
    bool? enabled,
    bool? blockSelectedApps,
    bool? silenceNotifications,
    Iterable<String>? selectedPackages,
    Map<String, int>? consentVersions,
  }) {
    return FocusProtectionConfiguration(
      enabled: enabled ?? this.enabled,
      blockSelectedApps: blockSelectedApps ?? this.blockSelectedApps,
      silenceNotifications: silenceNotifications ?? this.silenceNotifications,
      selectedPackages: selectedPackages ?? this.selectedPackages,
      consentVersions: consentVersions ?? this.consentVersions,
    );
  }

  Map<String, Object> toMap() => {
        'enabled': enabled,
        'blockSelectedApps': blockSelectedApps,
        'silenceNotifications': silenceNotifications,
        'selectedPackages': selectedPackages.toList()..sort(),
        'consentVersions': consentVersions,
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
  })  : activeMechanisms = Set.unmodifiable(activeMechanisms),
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
