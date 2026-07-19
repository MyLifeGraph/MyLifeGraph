import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_tables.dart';
import '../../quick_action/data/guest_quick_check_in_data_source.dart';
import '../../quick_action/data/quick_check_in_supabase_data_source.dart';
import 'guest_setup_data_source.dart';
import '../domain/app_session.dart';
import '../domain/intake_response.dart';

const localDeviceTimezoneMarker = 'device-local';

typedef GoogleOAuthLauncher = Future<bool> Function(String redirectTo);

class AuthRepository {
  AuthRepository(
    this._client, {
    required bool useMockData,
    GuestSetupDataSource guestSetupDataSource = const GuestSetupDataSource(),
    GoogleOAuthLauncher? googleOAuthLauncher,
  })  : _useMockData = useMockData,
        _guestSetupDataSource = guestSetupDataSource,
        _googleOAuthLauncher = googleOAuthLauncher;

  final SupabaseClient _client;
  final bool _useMockData;
  final GuestSetupDataSource _guestSetupDataSource;
  final GoogleOAuthLauncher? _googleOAuthLauncher;

  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  AppSession? _cachedSession;

  Future<AppSession?> currentSession() async {
    final user = _client.auth.currentUser;
    if (user != null) {
      final profile = await _resolveAuthenticatedProfile(user);
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
      timezone: localDeviceTimezoneMarker,
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
    final profile = await _resolveAuthenticatedProfile(user);
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
      emailRedirectTo: authRedirectUrl(),
      data: {
        if (name != null && name.trim().isNotEmpty) 'display_name': name.trim(),
      },
    );
    final user = response.user;
    if (user == null || response.session == null) {
      return null;
    }

    final profile = await _resolveAuthenticatedProfile(
      user,
      preferredName: name,
    );
    await _clearGuestActiveFlag();
    final session = AppSession.authenticated(profile);
    _cachedSession = session;
    return session;
  }

  Future<void> signInWithGoogle() async {
    final redirectTo = authRedirectUrl();
    final opened = await (_googleOAuthLauncher?.call(redirectTo) ??
        _client.auth.signInWithOAuth(
          OAuthProvider.google,
          redirectTo: redirectTo,
        ));
    if (!opened) {
      throw const AuthException('Google sign-in could not be opened.');
    }
  }

  Future<void> requestPasswordReset({required String email}) async {
    await _client.auth.resetPasswordForEmail(
      email.trim(),
      redirectTo: authRedirectUrl(),
    );
  }

  Future<void> resendSignupConfirmation({required String email}) async {
    await _client.auth.resend(
      type: OtpType.signup,
      email: email.trim(),
      emailRedirectTo: authRedirectUrl(),
    );
  }

  Future<void> updatePassword({required String password}) async {
    await _client.auth.updateUser(UserAttributes(password: password));
  }

  Future<AppSession> continueAsGuest() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_Prefs.guestActive, true);
    final session = AppSession.guest(
      AppProfile(
        id: 'local_guest',
        email: 'guest@personal-coach.local',
        name: prefs.getString(_Prefs.guestName) ?? 'Guest Coach User',
        timezone: localDeviceTimezoneMarker,
        role: AppRole.guest,
        onboardingDone: prefs.getBool(_Prefs.guestOnboardingDone) ?? false,
        authProvider: 'guest',
      ),
    );
    _cachedSession = session;
    return session;
  }

  Future<void> signOut() async {
    await _client.auth.signOut();
    await _clearGuestActiveFlag();
    _cachedSession = null;
  }

  Future<void> signOutAfterAccountDeletion() async {
    try {
      await _client.auth.signOut();
    } finally {
      await _clearGuestActiveFlag();
      _cachedSession = null;
    }
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
      'timezone': 'UTC',
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
          'id,email,display_name,timezone,daily_preparation_budget_minutes,'
          'auth_provider,'
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
      timezone: '${row['timezone'] ?? 'UTC'}',
      role: AppRole.fromDatabase(row['role']?.toString()),
      onboardingDone: row['onboarding_completed_at'] != null,
      authProvider: '${row['auth_provider'] ?? 'email'}',
      dailyPreparationBudgetMinutes:
          (row['daily_preparation_budget_minutes'] as num?)?.toInt(),
    );
  }

  Future<AppProfile> _resolveAuthenticatedProfile(
    User user, {
    String? preferredName,
  }) async {
    final authProvider = user.appMetadata['provider']?.toString() ?? 'email';
    if (!shouldReadRemoteProfileForAuthIdentity(
      useMockData: _useMockData,
      email: user.email,
      authProvider: authProvider,
    )) {
      final localProfile = localDemoProfileFromAuthUser(
        user,
        preferredName: preferredName,
      );
      try {
        return await overlayLocalDemoSetup(
          profile: localProfile,
          dataSource: _guestSetupDataSource,
        );
      } catch (_) {
        return localProfile;
      }
    }
    final profile = await ensureProfileForAuthUser(
      user,
      preferredName: preferredName,
    );
    if (shouldMigrateGuestCheckIns(
      useMockData: _useMockData,
      profile: profile,
    )) {
      await _migrateGuestCheckIns(profile.id);
      return profile;
    }
    try {
      return await overlayLocalDemoSetup(
        profile: profile,
        dataSource: _guestSetupDataSource,
      );
    } catch (_) {
      return profile;
    }
  }

  Future<void> _migrateGuestCheckIns(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_Prefs.guestQuickCheckIns);
    if (raw == null || raw.isEmpty) {
      return;
    }
    try {
      final entries = await GuestQuickCheckInDataSource().readAll();
      final remote = QuickCheckInSupabaseDataSource(_client);
      for (final entry in entries) {
        await remote.mergeEntryForUser(userId: userId, entry: entry);
      }
      await prefs.remove(_Prefs.guestQuickCheckIns);
    } catch (_) {
      return;
    }
  }

  Future<void> _clearGuestActiveFlag() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_Prefs.guestActive, false);
  }
}

const nativeAuthCallbackUrl = 'com.mylifegraph.app://login-callback/';

String authRedirectUrl() => kIsWeb ? Uri.base.origin : nativeAuthCallbackUrl;

bool usesLocalDemoAuthData({
  required bool useMockData,
  required AppProfile profile,
}) {
  return useMockData ||
      profile.role == AppRole.guest ||
      profile.authProvider == 'guest' ||
      profile.email.toLowerCase() == 'demo@personal-coach.local';
}

bool usesLocalDemoAuthIdentity({
  required bool useMockData,
  required String? email,
  required String? authProvider,
}) {
  return useMockData ||
      authProvider == 'guest' ||
      email?.toLowerCase() == 'demo@personal-coach.local';
}

bool shouldReadRemoteProfileForAuthIdentity({
  required bool useMockData,
  required String? email,
  required String? authProvider,
}) {
  return !usesLocalDemoAuthIdentity(
    useMockData: useMockData,
    email: email,
    authProvider: authProvider,
  );
}

AppProfile localDemoProfileFromAuthUser(
  User user, {
  String? preferredName,
}) {
  final email = user.email ?? '';
  final preferred = preferredName?.trim();
  final metadataName = user.userMetadata?['display_name']?.toString().trim();
  final fullName = user.userMetadata?['full_name']?.toString().trim();
  final fallbackName =
      email.contains('@') ? email.split('@').first : 'Demo User';
  final name = preferred?.isNotEmpty == true
      ? preferred!
      : metadataName?.isNotEmpty == true
          ? metadataName!
          : fullName?.isNotEmpty == true
              ? fullName!
              : fallbackName;
  return AppProfile(
    id: user.id,
    email: email,
    name: name,
    timezone: localDeviceTimezoneMarker,
    role: AppRole.user,
    onboardingDone: false,
    authProvider: user.appMetadata['provider']?.toString() ?? 'email',
  );
}

bool shouldMigrateGuestCheckIns({
  required bool useMockData,
  required AppProfile profile,
}) {
  return !usesLocalDemoAuthData(
    useMockData: useMockData,
    profile: profile,
  );
}

Future<AppProfile> overlayLocalDemoSetup({
  required AppProfile profile,
  required GuestSetupDataSource dataSource,
}) async {
  final preferences = await SharedPreferences.getInstance();
  final storedName =
      preferences.getString(GuestSetupDataSource.guestNameKey)?.trim();
  final storedOnboardingDone =
      preferences.getBool(GuestSetupDataSource.guestOnboardingDoneKey) ?? false;
  IntakeSetupReadState? setup;
  try {
    setup = await dataSource.read();
  } catch (_) {
    return profile.copyWith(
      name: storedName?.isNotEmpty == true ? storedName : null,
      onboardingDone: storedOnboardingDone,
    );
  }
  final responses = setup.responses;
  if (!setup.exists || setup.status != 'applied' || responses == null) {
    return profile.copyWith(
      name: storedName?.isNotEmpty == true ? storedName : null,
      onboardingDone: storedOnboardingDone,
    );
  }
  final displayName = responses.displayName?.trim();
  return profile.copyWith(
    name: displayName?.isNotEmpty == true
        ? displayName
        : storedName?.isNotEmpty == true
            ? storedName
            : null,
    onboardingDone: true,
  );
}

class _Prefs {
  const _Prefs._();

  static const guestActive = 'auth_guest_active';
  static const guestName = 'auth_guest_name';
  static const guestOnboardingDone = 'auth_guest_onboarding_done';
  static const guestQuickCheckIns = 'guest_quick_checkins';
}
