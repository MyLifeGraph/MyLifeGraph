import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';
import '../time/profile_timezone.dart';

class AppBootstrap {
  const AppBootstrap._();

  static Future<void> initialize(AppConfig config) async {
    initializeProfileTimeZones();
    config.validateSupabaseConfiguration();
    if (!config.isSupabaseConfigured) {
      return;
    }

    await Supabase.initialize(
      url: config.supabaseUrl,
      // supabase_flutter 2.x keeps the historical parameter name while
      // accepting both current publishable keys and legacy anon JWTs.
      anonKey: config.supabaseClientKey,
    );
  }
}
