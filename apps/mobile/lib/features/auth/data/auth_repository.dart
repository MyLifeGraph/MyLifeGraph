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
      redirectTo: kIsWeb ? webOAuthRedirectTo(Uri.base) : null,
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
    await _safeUserUpdate(profile.id, {
      if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
      'onboardingDone': true,
      'updatedAt': now,
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
    final existing = await _selectUser(user.id);
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
      'name': name,
      'timezone': 'Europe/Berlin',
      'authProvider': provider,
      'onboardingDone': false,
      'updatedAt': now,
      'role': AppRole.user.databaseValue,
    };

    try {
      await _client.from(SupabaseTables.users).insert(row);
    } on PostgrestException catch (error) {
      if (!error.message.toLowerCase().contains('role')) {
        rethrow;
      }
      final fallback = Map<String, dynamic>.from(row)..remove('role');
      await _client.from(SupabaseTables.users).insert(fallback);
    }

    final inserted = await _selectUser(user.id);
    return _profileFromRow(inserted ?? row, fallbackUser: user);
  }

  Future<Map<String, dynamic>?> _selectUser(String id) async {
    try {
      final rows = await _client
          .from(SupabaseTables.users)
          .select('id,email,name,timezone,authProvider,onboardingDone,role')
          .eq('id', id)
          .limit(1);
      final list = List<Map<String, dynamic>>.from(rows as List);
      return list.isEmpty ? null : list.first;
    } on PostgrestException catch (error) {
      if (!error.message.toLowerCase().contains('role')) {
        rethrow;
      }
      final rows = await _client
          .from(SupabaseTables.users)
          .select('id,email,name,timezone,authProvider,onboardingDone')
          .eq('id', id)
          .limit(1);
      final list = List<Map<String, dynamic>>.from(rows as List);
      return list.isEmpty ? null : list.first;
    }
  }

  AppProfile _profileFromRow(
    Map<String, dynamic> row, {
    User? fallbackUser,
  }) {
    return AppProfile(
      id: '${row['id'] ?? fallbackUser?.id ?? ''}',
      email: '${row['email'] ?? fallbackUser?.email ?? ''}',
      name: '${row['name'] ?? 'New User'}',
      timezone: '${row['timezone'] ?? 'Europe/Berlin'}',
      role: AppRole.fromDatabase(row['role']?.toString()),
      onboardingDone: row['onboardingDone'] == true,
      authProvider: '${row['authProvider'] ?? 'email'}',
    );
  }

  Future<void> _safeUserUpdate(String id, Map<String, dynamic> values) async {
    try {
      await _client.from(SupabaseTables.users).update(values).eq('id', id);
    } on PostgrestException catch (error) {
      if (!error.message.toLowerCase().contains('role')) {
        rethrow;
      }
      final fallback = Map<String, dynamic>.from(values)..remove('role');
      await _client.from(SupabaseTables.users).update(fallback).eq('id', id);
    }
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
        'id': 'schedule_${now.microsecondsSinceEpoch}_${draft.weekday}',
        'userId': userId,
        'title':
            draft.title.trim().isEmpty ? 'Study block' : draft.title.trim(),
        'location':
            draft.location.trim().isEmpty ? null : draft.location.trim(),
        'weekday': draft.weekday,
        'startsAt': draft.startsAt,
        'endsAt': draft.endsAt,
        'source': 'onboarding',
        'updatedAt': now.toIso8601String(),
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
        final id = 'guest_migrated_daily_${now.microsecondsSinceEpoch}';
        final date = DateTime(now.year, now.month, now.day).toIso8601String();
        final mood = (value['mood'] as num?)?.toInt() ?? 7;
        final energy = (value['energy'] as num?)?.toInt() ?? 6;
        final stress = (value['stress'] as num?)?.toInt() ?? 4;
        final notes = '${value['coachNotes'] ?? ''}'.trim();

        await _client.from(SupabaseTables.dailyLogs).insert({
          'id': id,
          'userId': userId,
          'date': date,
          'sleepHours': (value['sleepHours'] as num?)?.toDouble() ?? 7,
          'energyLevel': energy,
          'mood': _moodEnumValue(mood),
          'reflection': [
            'Migrated from guest quick check-in.',
            'Stress rating: $stress/10.',
            if (notes.isNotEmpty) notes,
          ].join(' '),
          'updatedAt': now.toIso8601String(),
        });
      }
      await prefs.remove(_Prefs.guestQuickCheckIns);
    } catch (_) {
      return;
    }
  }

  String _moodEnumValue(int rating) {
    if (rating >= 9) {
      return 'GREAT';
    }
    if (rating >= 7) {
      return 'GOOD';
    }
    if (rating >= 5) {
      return 'NEUTRAL';
    }
    if (rating >= 3) {
      return 'BAD';
    }
    return 'VERY_BAD';
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

@visibleForTesting
String webOAuthRedirectTo(Uri baseUri) => '${baseUri.origin}/';
