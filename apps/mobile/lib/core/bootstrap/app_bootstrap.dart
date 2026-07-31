import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';
import '../time/profile_timezone.dart';

class AppBootstrap {
  const AppBootstrap._();

  static Future<void> initialize(AppConfig config) async {
    initializeProfileTimeZones();
    if (!config.isSupabaseConfigured) {
      return;
    }

    await Supabase.initialize(
      url: config.supabaseUrl,
      anonKey: config.supabaseAnonKey,
    );
  }
}
