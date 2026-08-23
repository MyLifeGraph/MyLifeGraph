import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/contracts/account_deletion.dart';
import '../../../core/supabase/supabase_tables.dart';
import 'guest_setup_data_source.dart';
import 'pilot_participation_api_data_source.dart';
import '../domain/app_session.dart';
import '../domain/auth_captcha.dart';
import '../domain/auth_failure.dart';
import '../domain/intake_response.dart';

const localDeviceTimezoneMarker = 'device-local';

typedef GoogleOAuthLauncher = Future<bool> Function(String redirectTo);
typedef GuestCheckInMigrator = Future<void> Function(String userId);
typedef PendingAccountDeletionResolver =
    Future<AccountDeletionRecovery?> Function({
      required String userId,
      required String accessToken,
    });

class AuthRepository {
  AuthRepository(
    this._client, {
    required bool useMockData,
    GuestSetupDataSource guestSetupDataSource = const GuestSetupDataSource(),
    GoogleOAuthLauncher? googleOAuthLauncher,
    GuestCheckInMigrator? guestCheckInMigrator,
    PilotParticipationGateway? pilotParticipationGateway,
    PendingAccountDeletionResolver? pendingAccountDeletionResolver,
    bool requiresPilotParticipation = false,
    bool requiresAuthCaptcha = false,
  }) : _useMockData = useMockData,
       _guestSetupDataSource = guestSetupDataSource,
       _googleOAuthLauncher = googleOAuthLauncher,
       _guestCheckInMigrator = guestCheckInMigrator,
       _pilotParticipationGateway = pilotParticipationGateway,
       _pendingAccountDeletionResolver = pendingAccountDeletionResolver,
       _requiresPilotParticipation = requiresPilotParticipation,
       _requiresAuthCaptcha = requiresAuthCaptcha;

  final SupabaseClient _client;
  final bool _useMockData;
  final GuestSetupDataSource _guestSetupDataSource;
  final GoogleOAuthLauncher? _googleOAuthLauncher;
  final GuestCheckInMigrator? _guestCheckInMigrator;
  final PilotParticipationGateway? _pilotParticipationGateway;
  final PendingAccountDeletionResolver? _pendingAccountDeletionResolver;
  final bool _requiresPilotParticipation;
  final bool _requiresAuthCaptcha;

  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  AppSession? _cachedSession;

  Future<AppSession?> currentSession() async {
    final user = _client.auth.currentUser;
    if (user != null) {
      final deletionRecovery = await _pendingDeletionRecovery(user);
      if (deletionRecovery != null) {
        if (_client.auth.currentUser?.id != user.id) {
          _cachedSession = null;
          return null;
        }
        final session = AppSession.deletionRecovery(
          _deletionRecoveryProfile(user),
          deletionRecovery,
        );
        _cachedSession = session;
        return session;
      }
      final profile = await _resolveAuthenticatedProfile(user);
      if (_client.auth.currentUser?.id != user.id) {
        _cachedSession = null;
        return null;
      }
      _cachedSession = AppSession.authenticated(profile);
      return _cachedSession;
    }

    if (_requiresPilotParticipation) {
      await _clearGuestActiveFlag();
      _cachedSession = null;
      return null;
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
    String? captchaToken,
  }) async {
    final verifiedCaptchaToken = validateAuthCaptchaToken(
      requiredForEnvironment: _requiresAuthCaptcha,
      token: captchaToken,
    );
    final response = await _client.auth.signInWithPassword(
      email: email,
      password: password,
      captchaToken: verifiedCaptchaToken,
    );
    final user = response.user ?? _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Login did not return a user session.');
    }
    final deletionRecovery = await _pendingDeletionRecovery(user);
    if (deletionRecovery != null) {
      if (_client.auth.currentUser?.id != user.id) {
        throw const AuthException('Account session changed during sign-in.');
      }
      final session = AppSession.deletionRecovery(
        _deletionRecoveryProfile(user),
        deletionRecovery,
      );
      _cachedSession = session;
      return session;
    }
    final profile = await _resolveAuthenticatedProfile(user);
    if (_client.auth.currentUser?.id != user.id) {
      throw const AuthException('Account session changed during sign-in.');
    }
    await _clearGuestActiveFlag();
    final session = AppSession.authenticated(profile);
    _cachedSession = session;
    return session;
  }

  Future<AppSession?> registerWithEmail({
    required String email,
    required String password,
    String? name,
    bool confirmed18OrOlder = false,
    String? captchaToken,
  }) async {
    _requirePilotParticipationConfirmation(confirmed18OrOlder);
    final response = await _client.auth.signUp(
      email: email,
      password: password,
      emailRedirectTo: authRedirectUrl(),
      data: {
        if (name != null && name.trim().isNotEmpty) 'display_name': name.trim(),
      },
      captchaToken: validateAuthCaptchaToken(
        requiredForEnvironment: _requiresAuthCaptcha,
        token: captchaToken,
      ),
    );
    final user = response.user;
    if (user == null || response.session == null) {
      return null;
    }

    var profile = await _resolveAuthenticatedProfile(user, preferredName: name);
    if (_requiresPilotParticipation) {
      profile = await _recordCurrentPilotParticipation(profile);
      profile = await _finishAuthenticatedProfile(profile);
    }
    await _clearGuestActiveFlag();
    final session = AppSession.authenticated(profile);
    _cachedSession = session;
    return session;
  }

  Future<void> signInWithGoogle({bool confirmed18OrOlder = false}) async {
    _requirePilotParticipationConfirmation(confirmed18OrOlder);
    final redirectTo = authRedirectUrl();
    final opened =
        await (_googleOAuthLauncher?.call(redirectTo) ??
            _client.auth.signInWithOAuth(
              OAuthProvider.google,
              redirectTo: redirectTo,
            ));
    if (!opened) {
      throw const AuthException('Google sign-in could not be opened.');
    }
  }

  Future<void> requestPasswordReset({
    required String email,
    String? captchaToken,
  }) async {
    await _client.auth.resetPasswordForEmail(
      email.trim(),
      redirectTo: authRedirectUrl(),
      captchaToken: validateAuthCaptchaToken(
        requiredForEnvironment: _requiresAuthCaptcha,
        token: captchaToken,
      ),
    );
  }

  Future<void> resendSignupConfirmation({
    required String email,
    String? captchaToken,
  }) async {
    await _client.auth.resend(
      type: OtpType.signup,
      email: email.trim(),
      emailRedirectTo: authRedirectUrl(),
      captchaToken: validateAuthCaptchaToken(
        requiredForEnvironment: _requiresAuthCaptcha,
        token: captchaToken,
      ),
    );
  }

  Future<void> updatePassword({required String password}) async {
    await _client.auth.updateUser(UserAttributes(password: password));
  }

  Future<AppSession> continueAsGuest() async {
    if (_requiresPilotParticipation) {
      throw const PilotParticipationUnavailableException();
    }
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

  Future<AppProfile> requireProfileForAuthUser(User user) async {
    final existing = await _selectProfile(user.id);
    if (existing == null) {
      throw const MissingProfileInvariantException();
    }
    return _profileFromRow(existing, fallbackUser: user);
  }

  Future<Map<String, dynamic>?> _selectProfile(String id) async {
    final rows = await _client
        .from(SupabaseTables.profiles)
        .select(
          'id,email,display_name,timezone,daily_preparation_budget_minutes,'
          'timezone_revision,preparation_budget_revision,auth_provider,'
          'onboarding_completed_at,role,pilot_participation_notice_version,'
          'pilot_participation_accepted_at',
        )
        .eq('id', id)
        .limit(1);
    final list = List<Map<String, dynamic>>.from(rows as List);
    return list.isEmpty ? null : list.first;
  }

  AppProfile _profileFromRow(Map<String, dynamic> row, {User? fallbackUser}) {
    final acceptedAtValue = row['pilot_participation_accepted_at'];
    final parsedAcceptedAt = acceptedAtValue is String
        ? DateTime.tryParse(acceptedAtValue)
        : null;
    final acceptedAt = parsedAcceptedAt?.isUtc == true
        ? parsedAcceptedAt
        : null;
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
      timezoneRevision: (row['timezone_revision'] as num?)?.toInt() ?? 1,
      preparationBudgetRevision:
          (row['preparation_budget_revision'] as num?)?.toInt() ?? 1,
      pilotParticipationNoticeVersion:
          row['pilot_participation_notice_version'] as String?,
      pilotParticipationAcceptedAt: acceptedAt,
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
    final profile = await requireProfileForAuthUser(user);
    if (_requiresPilotParticipation && !profile.hasCurrentPilotParticipation) {
      return profile;
    }
    return _finishAuthenticatedProfile(profile);
  }

  Future<AppProfile> _finishAuthenticatedProfile(AppProfile profile) async {
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

  void _requirePilotParticipationConfirmation(bool confirmed18OrOlder) {
    if (!_requiresPilotParticipation) return;
    if (!confirmed18OrOlder) {
      throw const PilotParticipationConfirmationRequiredException();
    }
  }

  Future<AppProfile> acceptCurrentPilotParticipation() async {
    final session = _cachedSession;
    if (!_requiresPilotParticipation ||
        session == null ||
        session.isGuestSession) {
      throw const PilotParticipationUnavailableException();
    }
    final accepted = await _recordCurrentPilotParticipation(session.profile);
    final complete = await _finishAuthenticatedProfile(accepted);
    _cachedSession = AppSession.authenticated(complete);
    return complete;
  }

  Future<AppProfile> _recordCurrentPilotParticipation(
    AppProfile profile,
  ) async {
    final gateway = _pilotParticipationGateway;
    final currentSession = _client.auth.currentSession;
    if (gateway == null ||
        currentSession == null ||
        currentSession.user.id != profile.id ||
        currentSession.accessToken.isEmpty) {
      throw const PilotParticipationUnavailableException();
    }
    final accepted = await gateway.accept(
      accessToken: currentSession.accessToken,
    );
    return profile.copyWith(
      pilotParticipationNoticeVersion: accepted.noticeVersion,
      pilotParticipationAcceptedAt: accepted.acceptedAt,
    );
  }

  Future<void> _migrateGuestCheckIns(String userId) async {
    try {
      await _guestCheckInMigrator?.call(userId);
    } catch (_) {
      return;
    }
  }

  Future<void> _clearGuestActiveFlag() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_Prefs.guestActive, false);
  }

  Future<AccountDeletionRecovery?> _pendingDeletionRecovery(User user) async {
    final resolver = _pendingAccountDeletionResolver;
    final session = _client.auth.currentSession;
    if (resolver == null ||
        session == null ||
        session.user.id != user.id ||
        session.accessToken.isEmpty) {
      return null;
    }
    return resolver(userId: user.id, accessToken: session.accessToken);
  }
}

AppProfile _deletionRecoveryProfile(User user) => AppProfile(
  id: user.id,
  email: user.email ?? '',
  name: 'Account deletion',
  timezone: 'UTC',
  role: AppRole.user,
  onboardingDone: true,
  authProvider: user.appMetadata['provider']?.toString() ?? 'email',
);

const nativeAuthCallbackUrl = 'com.mylifegraph.app://login-callback/';

String authRedirectUrl() =>
    kIsWeb ? webOAuthRedirectTo(Uri.base) : nativeAuthCallbackUrl;

@visibleForTesting
String webOAuthRedirectTo(Uri baseUri) => '${baseUri.origin}/';

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

AppProfile localDemoProfileFromAuthUser(User user, {String? preferredName}) {
  final email = user.email ?? '';
  final preferred = preferredName?.trim();
  final metadataName = user.userMetadata?['display_name']?.toString().trim();
  final fullName = user.userMetadata?['full_name']?.toString().trim();
  final fallbackName = email.contains('@')
      ? email.split('@').first
      : 'Demo User';
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
  return !usesLocalDemoAuthData(useMockData: useMockData, profile: profile);
}

Future<AppProfile> overlayLocalDemoSetup({
  required AppProfile profile,
  required GuestSetupDataSource dataSource,
}) async {
  final preferences = await SharedPreferences.getInstance();
  final storedName = preferences
      .getString(GuestSetupDataSource.guestNameKey)
      ?.trim();
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
}

class PilotParticipationConfirmationRequiredException implements Exception {
  const PilotParticipationConfirmationRequiredException();
}

class PilotParticipationUnavailableException implements Exception {
  const PilotParticipationUnavailableException();
}
