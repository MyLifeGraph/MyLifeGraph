import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';
import '../time/profile_timezone.dart';

class AppBootstrap {
  const AppBootstrap._();

  static Future<void> initialize(AppConfig config) async {
    config.validateEnvironmentConfiguration();
    config.validateAiServiceConfiguration();
    config.validateSupabaseConfiguration();
    config.validatePilotParticipationConfiguration();
    config.validateAuthProtectionConfiguration();
    config.validateReleaseIdentityConfiguration();
    initializeProfileTimeZones();
    if (!config.isSupabaseConfigured) {
      return;
    }

    await Supabase.initialize(
      url: config.supabaseUrl,
      // Current SDKs keep opaque API keys in `apikey`; user session JWTs alone
      // belong in Authorization. The value may still be a legacy anon JWT
      // during the bounded staging transition.
      publishableKey: config.supabaseClientKey,
    );
  }
}
