import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_tables.dart';
import '../domain/app_session.dart';

class AuthRepository {
  AuthRepository(this._client);

  final SupabaseClient _client;

  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  AppSession? _cachedSession;

  Future<AppSession?> currentSession() async {
    final user = _client.auth.currentUser;
    if (user != null) {
      final profile = await ensureProfileForAuthUser(user);
      await _migrateGuestTimetable(profile.id);
      await _migrateGuestCheckIns(profile.id);
      _cachedSession = AppSession.authenticated(profile);
      return _cachedSession;
    }

    final prefs = await SharedPreferences.getInstance();
    final guestActive = prefs.getBool(_Prefs.guestActive) ?? false;
    if (!guestActive) {
      _cachedSession = null;
      return null;
    }

    final guestProfile = AppProfile(
      id: 'local_guest',
      email: 'guest@personal-coach.local',
      name: prefs.getString(_Prefs.guestName) ?? 'Guest Coach User',
      timezone: 'Europe/Berlin',
      role: AppRole.guest,
      onboardingDone: prefs.getBool(_Prefs.guestOnboardingDone) ?? false,
      authProvider: 'guest',
    );
    _cachedSession = AppSession.guest(guestProfile);
    return _cachedSession;
  }

  Future<AppSession> signInWithEmail({
    required String email,
    required String password,
  }) async {
    final response = await _client.auth.signInWithPassword(
      email: email,
      password: password,
    );
    final user = response.user ?? _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Login did not return a user session.');
    }
    final profile = await ensureProfileForAuthUser(user);
    await _migrateGuestTimetable(profile.id);
    await _migrateGuestCheckIns(profile.id);
    await _clearGuestActiveFlag();
    final session = AppSession.authenticated(profile);
    _cachedSession = session;
    return session;
  }

  Future<AppSession?> registerWithEmail({
    required String email,
    required String password,
    String? name,
  }) async {
    final response = await _client.auth.signUp(
      email: email,
      password: password,
      data: {
        if (name != null && name.trim().isNotEmpty) 'display_name': name.trim(),
      },
    );
    final user = response.user;
    if (user == null || response.session == null) {
      return null;
    }

    final profile = await ensureProfileForAuthUser(user, preferredName: name);
    await _migrateGuestTimetable(profile.id);
    await _migrateGuestCheckIns(profile.id);
    await _clearGuestActiveFlag();
    final session = AppSession.authenticated(profile);
    _cachedSession = session;
    return session;
  }

  Future<void> signInWithGoogle() async {
    await _client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: kIsWeb ? Uri.base.origin : null,
    );
  }

  Future<AppSession> continueAsGuest() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_Prefs.guestActive, true);
    final session = AppSession.guest(
      AppProfile(
        id: 'local_guest',
        email: 'guest@personal-coach.local',
        name: prefs.getString(_Prefs.guestName) ?? 'Guest Coach User',
        timezone: 'Europe/Berlin',
        role: AppRole.guest,
        onboardingDone: prefs.getBool(_Prefs.guestOnboardingDone) ?? false,
        authProvider: 'guest',
      ),
    );
    _cachedSession = session;
    return session;
  }

  Future<AppSession> completeOnboarding({
    required String? name,
    required List<TimetableDraft> timetable,
  }) async {
    final session = _cachedSession ?? await currentSession();
    if (session == null) {
      throw StateError('No active session.');
    }

    if (session.isGuestSession) {
      final prefs = await SharedPreferences.getInstance();
      final cleanName = name?.trim();
      if (cleanName != null && cleanName.isNotEmpty) {
        await prefs.setString(_Prefs.guestName, cleanName);
      }
      await prefs.setBool(_Prefs.guestOnboardingDone, true);
      await prefs.setString(
        _Prefs.guestTimetable,
        jsonEncode(timetable.map((draft) => draft.toJson()).toList()),
      );
      final updated = AppSession.guest(
        session.profile.copyWith(
          name: cleanName?.isNotEmpty == true ? cleanName : null,
          onboardingDone: true,
        ),
      );
      _cachedSession = updated;
      return updated;
    }

    final now = DateTime.now().toIso8601String();
    final profile = session.profile;
    await _safeProfileUpdate(profile.id, {
      if (name != null && name.trim().isNotEmpty) 'display_name': name.trim(),
      'onboarding_completed_at': now,
      'updated_at': now,
    });
    await _saveTimetable(profile.id, timetable);

    final updated = AppSession.authenticated(
      profile.copyWith(
        name: name?.trim().isNotEmpty == true ? name!.trim() : null,
        onboardingDone: true,
      ),
    );
    _cachedSession = updated;
    return updated;
  }

  Future<void> signOut() async {
    await _client.auth.signOut();
    await _clearGuestActiveFlag();
    _cachedSession = null;
  }

  Future<AppProfile> ensureProfileForAuthUser(
    User user, {
    String? preferredName,
  }) async {
    final existing = await _selectProfile(user.id);
    if (existing != null) {
      return _profileFromRow(existing, fallbackUser: user);
    }

    final now = DateTime.now().toIso8601String();
    final email = user.email ?? '';
    final name = preferredName?.trim().isNotEmpty == true
        ? preferredName!.trim()
        : user.userMetadata?['display_name']?.toString() ??
            user.userMetadata?['full_name']?.toString() ??
            (email.contains('@') ? email.split('@').first : 'New User');
    final provider = user.appMetadata['provider']?.toString() ?? 'email';
    final row = {
      'id': user.id,
      'email': email,
      'display_name': name,
      'timezone': 'Europe/Berlin',
      'auth_provider': provider,
      'updated_at': now,
      'role': AppRole.user.databaseValue,
    };

    await _client.from(SupabaseTables.profiles).upsert(row);

    final inserted = await _selectProfile(user.id);
    return _profileFromRow(inserted ?? row, fallbackUser: user);
  }

  Future<Map<String, dynamic>?> _selectProfile(String id) async {
    final rows = await _client
        .from(SupabaseTables.profiles)
        .select(
          'id,email,display_name,timezone,auth_provider,'
          'onboarding_completed_at,role',
        )
        .eq('id', id)
        .limit(1);
    final list = List<Map<String, dynamic>>.from(rows as List);
    return list.isEmpty ? null : list.first;
  }

  AppProfile _profileFromRow(
    Map<String, dynamic> row, {
    User? fallbackUser,
  }) {
    return AppProfile(
      id: '${row['id'] ?? fallbackUser?.id ?? ''}',
      email: '${row['email'] ?? fallbackUser?.email ?? ''}',
      name: '${row['display_name'] ?? 'New User'}',
      timezone: '${row['timezone'] ?? 'Europe/Berlin'}',
      role: AppRole.fromDatabase(row['role']?.toString()),
      onboardingDone: row['onboarding_completed_at'] != null,
      authProvider: '${row['auth_provider'] ?? 'email'}',
    );
  }

  Future<void> _safeProfileUpdate(
    String id,
    Map<String, dynamic> values,
  ) async {
    await _client.from(SupabaseTables.profiles).update(values).eq('id', id);
  }

  Future<void> _saveTimetable(
    String userId,
    List<TimetableDraft> timetable,
  ) async {
    if (timetable.isEmpty) {
      return;
    }
    final now = DateTime.now();
    final rows = timetable.map((draft) {
      return {
        'user_id': userId,
        'title':
            draft.title.trim().isEmpty ? 'Study block' : draft.title.trim(),
        'location':
            draft.location.trim().isEmpty ? null : draft.location.trim(),
        'weekday': draft.weekday,
        'starts_at': draft.startsAt,
        'ends_at': draft.endsAt,
        'source': 'onboarding',
        'updated_at': now.toIso8601String(),
      };
    }).toList();
    await _client.from(SupabaseTables.scheduleItems).insert(rows);
  }

  Future<void> _migrateGuestTimetable(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_Prefs.guestTimetable);
    if (raw == null || raw.isEmpty) {
      return;
    }
    try {
      final values = jsonDecode(raw) as List<dynamic>;
      final drafts = values
          .whereType<Map<String, dynamic>>()
          .map(TimetableDraft.fromJson)
          .toList();
      await _saveTimetable(userId, drafts);
      await prefs.remove(_Prefs.guestTimetable);
    } catch (_) {
      return;
    }
  }

  Future<void> _migrateGuestCheckIns(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_Prefs.guestQuickCheckIns);
    if (raw == null || raw.isEmpty) {
      return;
    }
    try {
      final values = jsonDecode(raw) as List<dynamic>;
      for (final value in values.whereType<Map<String, dynamic>>()) {
        final now =
            DateTime.tryParse('${value['createdAt']}') ?? DateTime.now();
        final date = DateTime(now.year, now.month, now.day);
        final mood = (value['mood'] as num?)?.toInt() ?? 7;
        final energy = (value['energy'] as num?)?.toInt() ?? 6;
        final stress = (value['stress'] as num?)?.toInt() ?? 4;
        final notes = '${value['coachNotes'] ?? ''}'.trim();

        await _client.from(SupabaseTables.dailyLogs).upsert(
          {
            'user_id': userId,
            'entry_date': _dateOnly(date),
            'sleep_hours': (value['sleepHours'] as num?)?.toDouble() ?? 7,
            'energy_level': energy,
            'stress_level': stress,
            'mood_score': mood,
            'mood_label': _moodLabel(mood),
            'reflection': [
              'Migrated from guest quick check-in.',
              'Stress rating: $stress/10.',
              if (notes.isNotEmpty) notes,
            ].join(' '),
            'source': 'guest_migration',
            'updated_at': now.toIso8601String(),
          },
          onConflict: 'user_id,entry_date',
        );
      }
      await prefs.remove(_Prefs.guestQuickCheckIns);
    } catch (_) {
      return;
    }
  }

  String _moodLabel(int rating) {
    if (rating >= 9) {
      return 'great';
    }
    if (rating >= 7) {
      return 'good';
    }
    if (rating >= 5) {
      return 'neutral';
    }
    if (rating >= 3) {
      return 'low';
    }
    return 'very_low';
  }

  String _dateOnly(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  Future<void> _clearGuestActiveFlag() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_Prefs.guestActive, false);
  }
}

class _Prefs {
  const _Prefs._();

  static const guestActive = 'auth_guest_active';
  static const guestName = 'auth_guest_name';
  static const guestOnboardingDone = 'auth_guest_onboarding_done';
  static const guestTimetable = 'auth_guest_timetable';
  static const guestQuickCheckIns = 'guest_quick_checkins';
}
