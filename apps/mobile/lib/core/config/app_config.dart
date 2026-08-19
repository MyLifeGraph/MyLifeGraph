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
  final String aiServiceBaseUrl;
  final bool useMockData;
  final bool coachSurfaceEnabled;
  final bool learnedFocusPlanningPilotEnabled;

  bool get requiresPilotParticipation =>
      {'staging', 'pilot'}.contains(environment.trim().toLowerCase());

  String get supabaseClientKey => resolveSupabaseClientKey(
        environment: environment,
        publishableKey: supabasePublishableKey,
        legacyAnonKey: supabaseAnonKey,
      );

  String get supabaseProjectRef {
    final normalized = environment.trim().toLowerCase();
    if (normalized == 'staging') return stagingSupabaseProjectRef;
    if (normalized == 'pilot') return pilotSupabaseProjectRef;
    return '';
  }

  bool get isSupabaseConfigured {
    validateSupabaseConfiguration();
    return supabaseUrl.isNotEmpty && supabaseClientKey.isNotEmpty;
  }

  void validateSupabaseConfiguration() {
    final key = supabaseClientKey;
    final hasUrl = supabaseUrl.isNotEmpty;
    final normalizedEnvironment = environment.trim().toLowerCase();
    if ((normalizedEnvironment == 'staging' ||
            normalizedEnvironment == 'pilot') &&
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
    if (!requiresPilotParticipation) return;
    _rejectSurroundingWhitespace('PILOT_CONTACT_EMAIL', pilotContactEmail);
    if (pilotContactEmail.length > 254 ||
        !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(pilotContactEmail)) {
      throw StateError(
        'PILOT_CONTACT_EMAIL must be a valid hosted-pilot contact address.',
      );
    }
  }
}

String resolveSupabaseClientKey({
  required String environment,
  String publishableKey = '',
  String legacyAnonKey = '',
}) {
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
  if (environment.trim().toLowerCase() == 'pilot' && publishableKey.isEmpty) {
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
  final normalized = environment.trim().toLowerCase();
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

bool resolveCoachSurfaceEnabled({
  required String environment,
  required bool releaseMode,
  String explicitValue = '',
}) {
  final normalized = environment.trim().toLowerCase();
  if (normalized == 'staging' ||
      normalized == 'pilot' ||
      normalized == 'production') {
    return explicitValue == 'true';
  }
  if (normalized != 'development') return false;
  if (explicitValue.isNotEmpty) return explicitValue == 'true';
  return !releaseMode;
}
