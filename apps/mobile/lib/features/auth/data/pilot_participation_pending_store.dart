import 'package:shared_preferences/shared_preferences.dart';

enum PilotParticipationFlow { email, google }

class PilotParticipationPendingStore {
  const PilotParticipationPendingStore();

  static const maxAge = Duration(minutes: 30);
  static const _versionKey = 'pilot_participation_pending_version';
  static const _flowKey = 'pilot_participation_pending_flow';
  static const _identityKey = 'pilot_participation_pending_identity';
  static const _expiresAtKey = 'pilot_participation_pending_expires_at_ms';

  Future<void> record({
    required String noticeVersion,
    required PilotParticipationFlow flow,
    required String identity,
    required DateTime now,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    await clear();
    await preferences.setString(_flowKey, flow.name);
    await preferences.setString(_identityKey, identity.trim().toLowerCase());
    await preferences.setInt(
      _expiresAtKey,
      now.toUtc().add(maxAge).millisecondsSinceEpoch,
    );
    // Write the version last so a partial write never becomes eligible.
    await preferences.setString(_versionKey, noticeVersion);
  }

  Future<bool> matches({
    required String noticeVersion,
    required PilotParticipationFlow flow,
    required String identity,
    required DateTime now,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    final expiresAt = preferences.getInt(_expiresAtKey);
    final matches = preferences.getString(_versionKey) == noticeVersion &&
        preferences.getString(_flowKey) == flow.name &&
        preferences.getString(_identityKey) == identity.trim().toLowerCase() &&
        expiresAt != null &&
        now.toUtc().millisecondsSinceEpoch <= expiresAt;
    if (!matches) await clear();
    return matches;
  }

  Future<void> clear() async {
    final preferences = await SharedPreferences.getInstance();
    await Future.wait([
      preferences.remove(_versionKey),
      preferences.remove(_flowKey),
      preferences.remove(_identityKey),
      preferences.remove(_expiresAtKey),
    ]);
  }
}
