import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final appConfigProvider = Provider<AppConfig>(
  (_) => throw StateError('AppConfig was not initialized'),
);

class AppConfig {
  const AppConfig({
    required this.environment,
    required this.supabaseUrl,
    required this.aiServiceBaseUrl,
    required this.useMockData,
    this.supabasePublishableKey = '',
    this.supabaseAnonKey = '',
    this.stagingSupabaseProjectRef = '',
    this.pilotSupabaseProjectRef = '',
    this.pilotContactEmail = '',
    this.appPublicOrigin = '',
    this.turnstileSiteKey = '',
    this.appBuildSha = '',
    this.appReleaseTag = '',
    this.coachSurfaceEnabled = false,
    this.learnedFocusPlanningPilotEnabled = false,
  });

  factory AppConfig.fromEnvironment() {
    const supabaseUrl = String.fromEnvironment(
      'SUPABASE_URL',
      defaultValue: '',
    );
    const supabasePublishableKey = String.fromEnvironment(
      'SUPABASE_PUBLISHABLE_KEY',
      defaultValue: '',
    );
    const supabaseAnonKey = String.fromEnvironment(
      'SUPABASE_ANON_KEY',
      defaultValue: '',
    );
    const stagingSupabaseProjectRef = String.fromEnvironment(
      'STAGING_SUPABASE_PROJECT_REF',
      defaultValue: '',
    );
    const pilotSupabaseProjectRef = String.fromEnvironment(
      'PILOT_SUPABASE_PROJECT_REF',
      defaultValue: '',
    );
    const pilotContactEmail = String.fromEnvironment(
      'PILOT_CONTACT_EMAIL',
      defaultValue: '',
    );
    const appPublicOrigin = String.fromEnvironment(
      'APP_PUBLIC_ORIGIN',
      defaultValue: '',
    );
    const turnstileSiteKey = String.fromEnvironment(
      'TURNSTILE_SITE_KEY',
      defaultValue: '',
    );
    const appBuildSha = String.fromEnvironment(
      'APP_BUILD_SHA',
      defaultValue: '',
    );
    const appReleaseTag = String.fromEnvironment(
      'APP_RELEASE_TAG',
      defaultValue: '',
    );
    const aiServiceBaseUrl = String.fromEnvironment(
      'AI_SERVICE_BASE_URL',
      defaultValue: 'http://localhost:8000',
    );

    const environment = String.fromEnvironment(
      'APP_ENV',
      defaultValue: 'development',
    );
    const coachSurfaceOverride = String.fromEnvironment(
      'COACH_SURFACE_ENABLED',
      defaultValue: '',
    );
    const learnedFocusPlanningPilotEnabled = bool.fromEnvironment(
      'LEARNED_FOCUS_PLANNING_PILOT_ENABLED',
      defaultValue: false,
    );
    return AppConfig(
      environment: environment,
      supabaseUrl: supabaseUrl,
      supabasePublishableKey: supabasePublishableKey,
      supabaseAnonKey: supabaseAnonKey,
      stagingSupabaseProjectRef: stagingSupabaseProjectRef,
      pilotSupabaseProjectRef: pilotSupabaseProjectRef,
      pilotContactEmail: pilotContactEmail,
      appPublicOrigin: appPublicOrigin,
      turnstileSiteKey: turnstileSiteKey,
      appBuildSha: appBuildSha,
      appReleaseTag: appReleaseTag,
      aiServiceBaseUrl: aiServiceBaseUrl,
      useMockData: const bool.fromEnvironment(
        'USE_MOCK_DATA',
        defaultValue: false,
      ),
      coachSurfaceEnabled: resolveCoachSurfaceEnabled(
        environment: environment,
        releaseMode: kReleaseMode,
        explicitValue: coachSurfaceOverride,
      ),
      learnedFocusPlanningPilotEnabled: learnedFocusPlanningPilotEnabled &&
          !{'pilot', 'production'}.contains(
            environment.trim().toLowerCase(),
          ),
    );
  }

  final String environment;
  final String supabaseUrl;
  final String supabasePublishableKey;

  /// Legacy transition input for local Supabase and older hosted settings.
  /// New hosted pilot builds must use [supabasePublishableKey].
  final String supabaseAnonKey;
  final String stagingSupabaseProjectRef;
  final String pilotSupabaseProjectRef;
  final String pilotContactEmail;
  final String appPublicOrigin;
  final String turnstileSiteKey;
  final String appBuildSha;
  final String appReleaseTag;
  final String aiServiceBaseUrl;
  final bool useMockData;
  final bool coachSurfaceEnabled;
  final bool learnedFocusPlanningPilotEnabled;

  void validateEnvironmentConfiguration() {
    validateAppEnvironment(environment);
  }

  bool get requiresPilotParticipation =>
      {'staging', 'pilot'}.contains(environment);

  bool get requiresAuthCaptcha => requiresPilotParticipation;

  Uri get turnstileChallengeUrl {
    validateAuthProtectionConfiguration();
    return Uri.parse('$appPublicOrigin/turnstile.html');
  }

  String get supabaseClientKey => resolveSupabaseClientKey(
        environment: environment,
        publishableKey: supabasePublishableKey,
        legacyAnonKey: supabaseAnonKey,
      );

  String get supabaseProjectRef {
    if (environment == 'staging') return stagingSupabaseProjectRef;
    if (environment == 'pilot') return pilotSupabaseProjectRef;
    return '';
  }

  bool get isSupabaseConfigured {
    validateSupabaseConfiguration();
    return supabaseUrl.isNotEmpty && supabaseClientKey.isNotEmpty;
  }

  void validateSupabaseConfiguration() {
    validateEnvironmentConfiguration();
    final key = supabaseClientKey;
    final hasUrl = supabaseUrl.isNotEmpty;
    if ((environment == 'staging' || environment == 'pilot') &&
        (!hasUrl || key.isEmpty)) {
      throw StateError(
        'Hosted builds require SUPABASE_URL and a Supabase client key.',
      );
    }
    if (hasUrl != key.isNotEmpty) {
      throw StateError(
        'SUPABASE_URL and a Supabase client key must be configured together.',
      );
    }
    if (!hasUrl) return;

    validateHostedSupabaseTarget(
      environment: environment,
      supabaseUrl: supabaseUrl,
      stagingProjectRef: stagingSupabaseProjectRef,
      pilotProjectRef: pilotSupabaseProjectRef,
    );
  }

  void validatePilotParticipationConfiguration() {
    validateEnvironmentConfiguration();
    if (!requiresPilotParticipation) return;
    _rejectSurroundingWhitespace('PILOT_CONTACT_EMAIL', pilotContactEmail);
    if (pilotContactEmail.length > 254 ||
        !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(pilotContactEmail)) {
      throw StateError(
        'PILOT_CONTACT_EMAIL must be a valid hosted-pilot contact address.',
      );
    }
  }

  void validateAuthProtectionConfiguration() {
    validateEnvironmentConfiguration();
    if (!requiresAuthCaptcha) return;
    _rejectSurroundingWhitespace('APP_PUBLIC_ORIGIN', appPublicOrigin);
    _rejectSurroundingWhitespace('TURNSTILE_SITE_KEY', turnstileSiteKey);
    final uri = Uri.tryParse(appPublicOrigin);
    if (uri == null ||
        uri.scheme != 'https' ||
        !uri.hasAuthority ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort ||
        uri.path.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        !_isCanonicalDnsHostname(uri.host) ||
        appPublicOrigin != 'https://${uri.host}') {
      throw StateError(
        'APP_PUBLIC_ORIGIN must be one canonical credential-free HTTPS origin.',
      );
    }
    if (!RegExp(r'^[A-Za-z0-9_-]{20,128}$').hasMatch(turnstileSiteKey)) {
      throw StateError(
        'TURNSTILE_SITE_KEY must be a valid public Cloudflare Turnstile site key.',
      );
    }
  }

  void validateReleaseIdentityConfiguration() {
    validateEnvironmentConfiguration();
    if (!requiresPilotParticipation) return;
    _rejectSurroundingWhitespace('APP_BUILD_SHA', appBuildSha);
    _rejectSurroundingWhitespace('APP_RELEASE_TAG', appReleaseTag);
    if (!RegExp(r'^[0-9a-f]{40}$').hasMatch(appBuildSha)) {
      throw StateError(
        'APP_BUILD_SHA must be an exact lowercase 40-character SHA.',
      );
    }
    if (!RegExp(
      r'^v[0-9]+\.[0-9]+\.[0-9]+-pilot\.[0-9]+(?:-rc\.[0-9]+)?$',
    ).hasMatch(appReleaseTag)) {
      throw StateError('APP_RELEASE_TAG must be an exact pilot release tag.');
    }
  }

  void validateAiServiceConfiguration() {
    validateEnvironmentConfiguration();
    _rejectSurroundingWhitespace(
      'AI_SERVICE_BASE_URL',
      aiServiceBaseUrl,
    );
    final uri = Uri.tryParse(aiServiceBaseUrl);
    if (uri == null ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.path.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw StateError(
        'AI_SERVICE_BASE_URL must be one credential-free HTTP(S) origin.',
      );
    }
    final hosted = requiresPilotParticipation;
    if (hosted) {
      final hostname = uri.host;
      final canonical = 'https://$hostname';
      if (uri.scheme != 'https' ||
          uri.hasPort ||
          aiServiceBaseUrl != canonical ||
          !_isCanonicalDnsHostname(hostname)) {
        throw StateError(
          'Hosted AI_SERVICE_BASE_URL must be one canonical HTTPS hostname origin.',
        );
      }
      return;
    }
    if (uri.scheme == 'https') return;
    const localHttpHosts = {'localhost', '127.0.0.1', '::1', '10.0.2.2'};
    if (uri.scheme != 'http' || !localHttpHosts.contains(uri.host)) {
      throw StateError(
        'Development HTTP AI_SERVICE_BASE_URL must use a known loopback host.',
      );
    }
  }
}

void validateAppEnvironment(String environment) {
  if (!const {'development', 'test', 'staging', 'pilot'}
      .contains(environment)) {
    throw StateError(
      'APP_ENV must be exactly development, test, staging, or pilot.',
    );
  }
}

String resolveSupabaseClientKey({
  required String environment,
  String publishableKey = '',
  String legacyAnonKey = '',
}) {
  validateAppEnvironment(environment);
  _rejectSurroundingWhitespace(
    'SUPABASE_PUBLISHABLE_KEY',
    publishableKey,
  );
  _rejectSurroundingWhitespace('SUPABASE_ANON_KEY', legacyAnonKey);
  if (publishableKey.isNotEmpty &&
      !publishableKey.startsWith('sb_publishable_')) {
    throw StateError(
      'SUPABASE_PUBLISHABLE_KEY must use the current sb_publishable_ format.',
    );
  }
  if (environment == 'pilot' && publishableKey.isEmpty) {
    throw StateError('SUPABASE_PUBLISHABLE_KEY is required for pilot builds.');
  }
  return publishableKey.isNotEmpty ? publishableKey : legacyAnonKey;
}

void validateHostedSupabaseTarget({
  required String environment,
  required String supabaseUrl,
  String stagingProjectRef = '',
  String pilotProjectRef = '',
}) {
  validateAppEnvironment(environment);
  final normalized = environment;
  if (normalized != 'staging' && normalized != 'pilot') return;

  final stagingRef = _validatedProjectRef(
    'STAGING_SUPABASE_PROJECT_REF',
    stagingProjectRef,
  );
  final pilotRef = _validatedProjectRef(
    'PILOT_SUPABASE_PROJECT_REF',
    pilotProjectRef,
    optional: normalized == 'staging',
  );
  if (pilotRef.isNotEmpty && stagingRef == pilotRef) {
    throw StateError(
      'Staging and pilot Supabase project refs must be distinct.',
    );
  }
  final expectedRef = normalized == 'staging' ? stagingRef : pilotRef;
  final uri = Uri.tryParse(supabaseUrl);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.userInfo.isNotEmpty ||
      uri.hasPort ||
      (uri.path.isNotEmpty && uri.path != '/') ||
      uri.hasQuery ||
      uri.hasFragment ||
      uri.host != '$expectedRef.supabase.co') {
    throw StateError(
      'SUPABASE_URL must exactly match the configured hosted project ref.',
    );
  }
}

String _validatedProjectRef(
  String name,
  String value, {
  bool optional = false,
}) {
  _rejectSurroundingWhitespace(name, value);
  if (optional && value.isEmpty) return '';
  if (!RegExp(r'^[a-z]{20}$').hasMatch(value)) {
    throw StateError('$name must be an exact 20-letter project ref.');
  }
  return value;
}

void _rejectSurroundingWhitespace(String name, String value) {
  if (value.trim() != value) {
    throw StateError('$name must not contain surrounding whitespace.');
  }
}

bool _isCanonicalDnsHostname(String value) {
  if (value != value.toLowerCase() ||
      value == 'localhost' ||
      value.length > 253 ||
      !value.contains('.')) {
    return false;
  }
  final labels = value.split('.');
  final label = RegExp(r'^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$');
  return labels.every(label.hasMatch) &&
      RegExp(r'^(?:[a-z]{2,63}|xn--[a-z0-9-]{2,59})$').hasMatch(labels.last);
}

bool resolveCoachSurfaceEnabled({
  required String environment,
  required bool releaseMode,
  String explicitValue = '',
}) {
  validateAppEnvironment(environment);
  final normalized = environment;
  if (normalized == 'staging' || normalized == 'pilot') {
    return explicitValue == 'true';
  }
  if (normalized != 'development') return false;
  if (explicitValue.isNotEmpty) return explicitValue == 'true';
  return !releaseMode;
}
