import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/config/app_config.dart';

void main() {
  test('Coach surface defaults fail closed for invalid and release builds', () {
    expect(
      () => resolveCoachSurfaceEnabled(
        environment: 'production',
        releaseMode: false,
      ),
      throwsStateError,
    );
    expect(
      resolveCoachSurfaceEnabled(
        environment: 'development',
        releaseMode: true,
      ),
      isFalse,
    );
    expect(
      resolveCoachSurfaceEnabled(
        environment: 'development',
        releaseMode: false,
      ),
      isTrue,
    );
  });

  test('staging and pilot require an exact explicit opt in', () {
    expect(
      resolveCoachSurfaceEnabled(
        environment: 'development',
        releaseMode: false,
        explicitValue: 'true',
      ),
      isTrue,
    );
    for (final environment in [
      'staging',
      'pilot',
    ]) {
      expect(
        resolveCoachSurfaceEnabled(
          environment: environment,
          releaseMode: false,
          explicitValue: 'true',
        ),
        isTrue,
      );
    }
    expect(
      resolveCoachSurfaceEnabled(
        environment: 'development',
        releaseMode: true,
        explicitValue: 'true',
      ),
      isTrue,
    );
    for (final value in ['false', 'TRUE', '1', 'invalid']) {
      expect(
        resolveCoachSurfaceEnabled(
          environment: 'development',
          releaseMode: false,
          explicitValue: value,
        ),
        isFalse,
        reason: 'explicitValue=$value',
      );
    }
  });

  test('application environment is a closed exact value', () {
    for (final environment in ['development', 'test', 'staging', 'pilot']) {
      expect(() => validateAppEnvironment(environment), returnsNormally);
    }
    for (final environment in [
      '',
      'pilto',
      'Pilot',
      ' pilot',
      'pilot ',
      'production',
    ]) {
      expect(
        () => validateAppEnvironment(environment),
        throwsStateError,
        reason: 'environment=$environment',
      );
    }
  });

  test('current publishable key wins during legacy-key rotation', () {
    expect(
      resolveSupabaseClientKey(
        environment: 'staging',
        publishableKey: 'sb_publishable_current',
      ),
      'sb_publishable_current',
    );
    expect(
      resolveSupabaseClientKey(
        environment: 'development',
        legacyAnonKey: 'legacy-anon-key',
      ),
      'legacy-anon-key',
    );
    expect(
      resolveSupabaseClientKey(
        environment: 'staging',
        publishableKey: 'sb_publishable_current',
        legacyAnonKey: 'different-legacy-key',
      ),
      'sb_publishable_current',
    );
    expect(
      () => resolveSupabaseClientKey(
        environment: 'pilot',
        legacyAnonKey: 'legacy-anon-key',
      ),
      throwsStateError,
    );
  });

  test('hosted Supabase target is bound to its exact environment project', () {
    const stagingRef = 'abcdefghijklmnopqrst';
    const pilotRef = 'bcdefghijklmnopqrstu';
    expect(
      () => validateHostedSupabaseTarget(
        environment: 'staging',
        supabaseUrl: 'https://$stagingRef.supabase.co',
        stagingProjectRef: stagingRef,
        pilotProjectRef: pilotRef,
      ),
      returnsNormally,
    );
    expect(
      () => validateHostedSupabaseTarget(
        environment: 'pilot',
        supabaseUrl: 'https://$pilotRef.supabase.co',
        stagingProjectRef: stagingRef,
        pilotProjectRef: pilotRef,
      ),
      returnsNormally,
    );
    expect(
      () => validateHostedSupabaseTarget(
        environment: 'pilot',
        supabaseUrl: 'https://$stagingRef.supabase.co',
        stagingProjectRef: stagingRef,
        pilotProjectRef: pilotRef,
      ),
      throwsStateError,
    );
    expect(
      () => validateHostedSupabaseTarget(
        environment: 'pilot',
        supabaseUrl: 'https://$stagingRef.supabase.co',
        stagingProjectRef: stagingRef,
        pilotProjectRef: stagingRef,
      ),
      throwsStateError,
    );
  });

  test('staging app configuration cannot fall back to guest mode', () {
    const config = AppConfig(
      environment: 'staging',
      supabaseUrl: '',
      aiServiceBaseUrl: 'https://coach-staging.example.test',
      useMockData: false,
      stagingSupabaseProjectRef: 'abcdefghijklmnopqrst',
    );

    expect(config.validateSupabaseConfiguration, throwsStateError);
  });

  test('hosted participation requires an explicit contact address', () {
    const missing = AppConfig(
      environment: 'staging',
      supabaseUrl: 'https://abcdefghijklmnopqrst.supabase.co',
      supabasePublishableKey: 'sb_publishable_test',
      stagingSupabaseProjectRef: 'abcdefghijklmnopqrst',
      aiServiceBaseUrl: 'https://coach-staging.example.test',
      useMockData: false,
    );
    const configured = AppConfig(
      environment: 'pilot',
      supabaseUrl: 'https://bcdefghijklmnopqrstu.supabase.co',
      supabasePublishableKey: 'sb_publishable_test',
      stagingSupabaseProjectRef: 'abcdefghijklmnopqrst',
      pilotSupabaseProjectRef: 'bcdefghijklmnopqrstu',
      pilotContactEmail: 'pilot-contact@example.org',
      aiServiceBaseUrl: 'https://coach.example.org',
      useMockData: false,
    );

    expect(missing.validatePilotParticipationConfiguration, throwsStateError);
    expect(
      configured.validatePilotParticipationConfiguration,
      returnsNormally,
    );
  });

  test('hosted builds require exact immutable release identity', () {
    const configured = AppConfig(
      environment: 'pilot',
      supabaseUrl: '',
      aiServiceBaseUrl: 'https://coach.example.org',
      useMockData: false,
      appBuildSha: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      appReleaseTag: 'v0.1.0-pilot.1-rc.1',
    );
    const missing = AppConfig(
      environment: 'staging',
      supabaseUrl: '',
      aiServiceBaseUrl: 'https://coach-staging.example.org',
      useMockData: false,
    );

    expect(configured.validateReleaseIdentityConfiguration, returnsNormally);
    expect(missing.validateReleaseIdentityConfiguration, throwsStateError);
    expect(
      () => const AppConfig(
        environment: 'pilot',
        supabaseUrl: '',
        aiServiceBaseUrl: 'https://coach.example.org',
        useMockData: false,
        appBuildSha: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
        appReleaseTag: 'latest',
      ).validateReleaseIdentityConfiguration(),
      throwsStateError,
    );
  });

  test('hosted email auth requires an exact public origin and Turnstile key',
      () {
    const configured = AppConfig(
      environment: 'pilot',
      supabaseUrl: '',
      aiServiceBaseUrl: 'https://coach.example.org',
      useMockData: false,
      appPublicOrigin: 'https://app.example.org',
      turnstileSiteKey: '1x00000000000000000000AA',
    );
    expect(configured.validateAuthProtectionConfiguration, returnsNormally);
    expect(
      configured.turnstileChallengeUrl.toString(),
      'https://app.example.org/turnstile.html',
    );

    for (final pair in [
      ('', '1x00000000000000000000AA'),
      ('http://app.example.org', '1x00000000000000000000AA'),
      ('https://app.example.org/', '1x00000000000000000000AA'),
      ('https://user@app.example.org', '1x00000000000000000000AA'),
      ('https://app.example.org', ''),
      ('https://app.example.org', 'short'),
    ]) {
      expect(
        () => AppConfig(
          environment: 'pilot',
          supabaseUrl: '',
          aiServiceBaseUrl: 'https://coach.example.org',
          useMockData: false,
          appPublicOrigin: pair.$1,
          turnstileSiteKey: pair.$2,
        ).validateAuthProtectionConfiguration(),
        throwsStateError,
        reason: 'origin=${pair.$1}, siteKey=${pair.$2}',
      );
    }
  });

  test('hosted AI service URL is one canonical credential-free HTTPS origin',
      () {
    const configured = AppConfig(
      environment: 'pilot',
      supabaseUrl: '',
      aiServiceBaseUrl: 'https://api.example.org',
      useMockData: false,
    );
    expect(configured.validateAiServiceConfiguration, returnsNormally);

    for (final value in [
      '',
      'http://api.example.org',
      'https://user@api.example.org',
      'https://api.example.org:443',
      'https://api.example.org/',
      'https://api.example.org/path',
      'https://api.example.org?query=1',
      'https://api.example.org#fragment',
      'https://localhost',
      'https://127.0.0.1',
      'https://API.example.org',
    ]) {
      expect(
        () => AppConfig(
          environment: 'pilot',
          supabaseUrl: '',
          aiServiceBaseUrl: value,
          useMockData: false,
        ).validateAiServiceConfiguration(),
        throwsStateError,
        reason: 'AI_SERVICE_BASE_URL=$value',
      );
    }
  });

  test('development HTTP API URL is restricted to known local hosts', () {
    for (final value in [
      'http://localhost:8000',
      'http://127.0.0.1:8000',
      'http://10.0.2.2:8000',
    ]) {
      expect(
        () => AppConfig(
          environment: 'development',
          supabaseUrl: '',
          aiServiceBaseUrl: value,
          useMockData: true,
        ).validateAiServiceConfiguration(),
        returnsNormally,
      );
    }
    expect(
      () => const AppConfig(
        environment: 'development',
        supabaseUrl: '',
        aiServiceBaseUrl: 'http://example.org:8000',
        useMockData: false,
      ).validateAiServiceConfiguration(),
      throwsStateError,
    );
  });
}
