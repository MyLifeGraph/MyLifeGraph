import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/config/app_config.dart';

void main() {
  test('Coach surface defaults fail closed for production and release', () {
    expect(
      resolveCoachSurfaceEnabled(
        environment: 'production',
        releaseMode: false,
      ),
      isFalse,
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

  test('staging, pilot, and production require an exact explicit opt in', () {
    expect(
      resolveCoachSurfaceEnabled(
        environment: 'development',
        releaseMode: false,
        explicitValue: 'true',
      ),
      isTrue,
    );
    for (final environment in [
      'production',
      ' PRODUCTION ',
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
}
