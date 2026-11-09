class PhoneLockOptions {
  PhoneLockOptions({
    this.mode = 'timer',
    this.minutes = 45,
    Set<String> allowedApps = const {},
  }) : allowedApps = Set.unmodifiable(allowedApps);
  final String mode;
  final int minutes;
  final Set<String> allowedApps;
  PhoneLockOptions copyWith({
    String? mode,
    int? minutes,
    Set<String>? allowedApps,
  }) => PhoneLockOptions(
    mode: mode ?? this.mode,
    minutes: minutes ?? this.minutes,
    allowedApps: allowedApps ?? this.allowedApps,
  );
  Map<String, Object> arguments(String requestId, {DateTime? focusEndsAt}) => {
    'requestId': requestId,
    'mode': mode,
    'minutes': minutes,
    'allowedApps': allowedApps.toList(),
    'recoveryAccepted': true,
    if (mode == 'timer' && focusEndsAt != null)
      'endsAtEpochMs': focusEndsAt.millisecondsSinceEpoch,
  };
}

class PhoneLockLaunch {
  const PhoneLockLaunch({required this.focusMinutes, this.options});
  final int focusMinutes;
  final PhoneLockOptions? options;
}

class PhoneLockStatus {
  const PhoneLockStatus({
    required this.active,
    required this.id,
    required this.mode,
    required this.ready,
    required this.nfcAvailable,
    required this.nfcEnrolled,
    this.protectionEnabled,
    this.accessibilityEnabled,
    this.phoneAvailable,
    this.remainingMs = 0,
    this.durationMs = 0,
    this.recoveryStarted = false,
    this.recoveryRemainingMs = 0,
    this.allowedApps = const {},
  });
  factory PhoneLockStatus.fromMap(Map map) {
    if (map['active'] is! bool ||
        map['ready'] is! bool ||
        map['id'] is! String ||
        !{'timer', 'nfc'}.contains(map['mode']) ||
        map['remainingMs'] is! int) {
      throw const FormatException('Phone lock status unavailable.');
    }
    return PhoneLockStatus(
      active: map['active'] as bool,
      id: map['id'] as String,
      mode: map['mode'] as String,
      ready: map['ready'] as bool,
      nfcAvailable: map['nfcAvailable'] == true,
      nfcEnrolled: map['nfcEnrolled'] == true,
      protectionEnabled: map['protectionEnabled'] as bool?,
      accessibilityEnabled: map['accessibilityEnabled'] as bool?,
      phoneAvailable: map['phoneAvailable'] as bool?,
      remainingMs: map['remainingMs'] as int,
      durationMs: map['durationMs'] as int? ?? 0,
      recoveryStarted: map['recoveryStarted'] == true,
      recoveryRemainingMs: map['recoveryRemainingMs'] as int? ?? 0,
      allowedApps: (map['allowedApps'] as List? ?? const [])
          .cast<String>()
          .toSet(),
    );
  }
  final bool active, ready, nfcAvailable, nfcEnrolled, recoveryStarted;
  // Optional diagnostics for older native hosts; only `ready` authorizes review.
  final bool? protectionEnabled, accessibilityEnabled, phoneAvailable;
  final String id, mode;
  final int remainingMs, durationMs, recoveryRemainingMs;
  final Set<String> allowedApps;
}

String phoneLockTime(int milliseconds) {
  final seconds = (milliseconds.clamp(0, 24 * 60 * 60 * 1000) + 999) ~/ 1000;
  return '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
}
