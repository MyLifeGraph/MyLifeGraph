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

    return const AppConfig(
      environment: String.fromEnvironment(
        'APP_ENV',
        defaultValue: 'development',
      ),
      supabaseUrl: supabaseUrl,
      supabaseAnonKey: supabaseAnonKey,
      aiServiceBaseUrl: aiServiceBaseUrl,
      useMockData: bool.fromEnvironment('USE_MOCK_DATA', defaultValue: false),
    );
  }

  final String environment;
  final String supabaseUrl;
  final String supabaseAnonKey;
  final String aiServiceBaseUrl;
  final bool useMockData;

  bool get isSupabaseConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
