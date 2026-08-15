import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final appConfigProvider = Provider<AppConfig>(
  (_) => throw StateError('AppConfig was not initialized'),
);

class AppConfig {
  const AppConfig({
    required this.environment,
    required this.supabaseUrl,
    required this.supabaseAnonKey,
    required this.aiServiceBaseUrl,
    required this.useMockData,
    this.coachSurfaceEnabled = false,
    this.learnedFocusPlanningPilotEnabled = false,
  });

  factory AppConfig.fromEnvironment() {
    const supabaseUrl = String.fromEnvironment(
      'SUPABASE_URL',
      defaultValue: '',
    );
    const supabaseAnonKey = String.fromEnvironment(
      'SUPABASE_ANON_KEY',
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
      supabaseAnonKey: supabaseAnonKey,
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
      learnedFocusPlanningPilotEnabled:
          learnedFocusPlanningPilotEnabled && environment != 'production',
    );
  }

  final String environment;
  final String supabaseUrl;
  final String supabaseAnonKey;
  final String aiServiceBaseUrl;
  final bool useMockData;
  final bool coachSurfaceEnabled;
  final bool learnedFocusPlanningPilotEnabled;

  bool get isSupabaseConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}

bool resolveCoachSurfaceEnabled({
  required String environment,
  required bool releaseMode,
  String explicitValue = '',
}) {
  final normalized = environment.trim().toLowerCase();
  if (normalized == 'staging' || normalized == 'production') {
    return explicitValue == 'true';
  }
  if (normalized != 'development') return false;
  if (explicitValue.isNotEmpty) return explicitValue == 'true';
  return !releaseMode;
}
