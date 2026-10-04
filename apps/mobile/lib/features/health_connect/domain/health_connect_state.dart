const healthConnectContractVersion = 'health-connect-v1';
const healthConnectConsentVersion = 'health-connect-cloud-consent-v1';
const healthVitalsConsentVersion = 'health-vitals-cloud-consent-v1';

class HealthConnectState {
  const HealthConnectState({
    required this.enabled,
    required this.revision,
    required this.timezone,
    required this.windowEnd,
    this.deviceId,
    this.lastSyncedAt,
    this.vitalsEnabled = false,
    this.latest = const {},
  });

  final bool enabled;
  final int revision;
  final String timezone;
  final String windowEnd;
  final String? deviceId;
  final DateTime? lastSyncedAt;
  final bool vitalsEnabled;
  final Map<String, dynamic> latest;

  factory HealthConnectState.fromJson(Map<String, dynamic> json) {
    final latest = json['latest'];
    if (latest != null) {
      if (latest is! Map || latest['date'] != json['window_end']) {
        throw const FormatException('Invalid Health Connect observations.');
      }
      for (final metric in ['steps', 'sleep_minutes', 'heart_rate', 'resting_heart_rate']) {
        final value = latest[metric];
        if (value == null) continue;
        final maximum = metric == 'steps' ? 200000 : metric == 'sleep_minutes' ? 1500 : 300;
        final minimum = metric == 'steps' || metric == 'sleep_minutes' ? 0 : 1;
        if (value is! num || !value.isFinite || value < minimum || value > maximum ||
            (metric != 'sleep_minutes' && value is! int)) {
          throw const FormatException('Invalid Health Connect observation value.');
        }
      }
    }
    if (json['contract_version'] != healthConnectContractVersion ||
        json['enabled'] is! bool ||
        json['revision'] is! int ||
        (json['revision'] as int) < 0 ||
        json['timezone'] is! String ||
        json['window_end'] is! String ||
        DateTime.tryParse(json['window_end'] as String) == null ||
        (json.containsKey('vitals_enabled') && json['vitals_enabled'] is! bool) ||
        (json['vitals_enabled'] == true &&
            (json['enabled'] != true ||
                json['vitals_consent_version'] != healthVitalsConsentVersion)) ||
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
      vitalsEnabled: json['vitals_enabled'] == true,
      latest: Map<String, dynamic>.from(latest as Map? ?? const {}),
      lastSyncedAt: json['last_synced_at'] == null
          ? null
          : DateTime.parse(json['last_synced_at'] as String),
    );
  }
}
