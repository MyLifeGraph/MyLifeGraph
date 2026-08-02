import 'package:shared_preferences/shared_preferences.dart';

import '../application/focus_recovery_store.dart';

class SharedPreferencesFocusRecoveryStore implements FocusRecoveryStore {
  const SharedPreferencesFocusRecoveryStore();

  static const preferenceKey = 'focus-recovery-countdown-v1';

  @override
  Future<String?> read() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getString(preferenceKey);
  }

  @override
  Future<void> write(String value) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(preferenceKey, value);
  }

  @override
  Future<void> clear() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(preferenceKey);
  }
}
