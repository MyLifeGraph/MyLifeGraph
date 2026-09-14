import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:my_life_graph/core/supabase/supabase_providers.dart';
import 'package:my_life_graph/features/coach/presentation/providers/coach_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test(
    'Coach token stays bound to the active profile during account handoff',
    () async {
      final client = SupabaseClient(
        'http://localhost:54321',
        'test-anon-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient(
          (_) async => throw StateError('No network allowed'),
        ),
      );
      addTearDown(client.dispose);
      final profile = StateProvider<String?>((_) => 'profile-a');
      final container = ProviderContainer(
        overrides: [
          supabaseClientProvider.overrideWithValue(client),
          coachActiveProfileIdProvider.overrideWith(
            (ref) => ref.watch(profile),
          ),
        ],
      );
      addTearDown(container.dispose);
      final token = container.read(coachAccessTokenProvider);
      expect(await token(), isNull);
      await _session(client, 'profile-a');
      expect(await token(), 'synthetic-profile-a');
      // Auth has switched, but app profile loading has not completed yet.
      await _session(client, 'profile-b');
      expect(await token(), isNull);
      container.read(profile.notifier).state = 'profile-b';
      expect(await token(), 'synthetic-profile-b');
      // Guest, logout or a disabled Coach surface denies any retained token.
      container.read(profile.notifier).state = null;
      expect(await token(), isNull);
    },
  );
}

Future<void> _session(SupabaseClient client, String owner) async {
  await client.auth.recoverSession(
    jsonEncode({
      'access_token': 'synthetic-$owner',
      'refresh_token': 'synthetic-refresh',
      'token_type': 'bearer',
      'expires_in': 3600,
      'expires_at':
          DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
          1000,
      'user': {
        'id': owner,
        'aud': 'authenticated',
        'app_metadata': {},
        'user_metadata': {},
        'created_at': '2026-09-14T00:00:00Z',
      },
    }),
  );
}
