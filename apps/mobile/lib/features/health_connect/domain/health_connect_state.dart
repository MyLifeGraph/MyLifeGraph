const healthConnectContractVersion = 'health-connect-v1';
const healthConnectConsentVersion = 'health-connect-cloud-consent-v1';

class HealthConnectState {
  const HealthConnectState({
    required this.enabled,
    required this.revision,
    required this.timezone,
    required this.windowEnd,
    this.deviceId,
    this.lastSyncedAt,
  });

  final bool enabled;
  final int revision;
  final String timezone;
  final String windowEnd;
  final String? deviceId;
  final DateTime? lastSyncedAt;

  factory HealthConnectState.fromJson(Map<String, dynamic> json) {
    if (json['contract_version'] != healthConnectContractVersion ||
        json['enabled'] is! bool ||
        json['revision'] is! int ||
        (json['revision'] as int) < 0 ||
        json['timezone'] is! String ||
        json['window_end'] is! String ||
        DateTime.tryParse(json['window_end'] as String) == null ||
        (json['enabled'] == true &&
            (json['consent_version'] != healthConnectConsentVersion ||
                json['device_id'] is! String))) {
      throw const FormatException('Invalid Health Connect response.');
    }
    return HealthConnectState(
      enabled: json['enabled'] as bool,
      revision: json['revision'] as int,
      timezone: json['timezone'] as String,
      windowEnd: json['window_end'] as String,
      deviceId: json['device_id'] as String?,
      lastSyncedAt: json['last_synced_at'] == null
          ? null
          : DateTime.parse(json['last_synced_at'] as String),
    );
  }
}
