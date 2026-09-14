const pushContractVersion = 'android-push-v1';
const pushConsentVersion = 'android-push-consent-v1';

class PushSettingsState {
  const PushSettingsState(this.json);
  final Map<String, dynamic> json;
  factory PushSettingsState.parse(Map<String, dynamic> json) {
    if (json['contract_version'] != pushContractVersion ||
        json['settings'] is! Map<String, dynamic> ||
        json['available'] is! bool) {
      throw const FormatException('Invalid push settings');
    }
    final s = json['settings'] as Map<String, dynamic>;
    if (s['revision'] is! int ||
        (s['revision'] as int) < 0 ||
        [
          'enabled',
          'sleep',
          'deadlines',
          'patterns',
        ].any((k) => s[k] is! bool) ||
        ['quiet_start', 'quiet_end'].any(
          (k) =>
              s[k] is! String ||
              !RegExp(
                r'^([01][0-9]|2[0-3]):[0-5][0-9]$',
              ).hasMatch(s[k] as String),
        ) ||
        (s['enabled'] == true && s['consent_version'] != pushConsentVersion)) {
      throw const FormatException('Invalid push settings');
    }
    return PushSettingsState(json);
  }
  Map<String, dynamic> get settings => json['settings'] as Map<String, dynamic>;
  int get revision => settings['revision'] as int;
  bool get enabled => settings['enabled'] == true;
  bool get available => json['available'] == true;
}
