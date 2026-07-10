import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/domain/app_session.dart';
import '../../features/auth/presentation/providers/auth_providers.dart';
import '../config/app_config.dart';
import '../supabase/supabase_providers.dart';

class AppSurfaceCapabilities {
  const AppSurfaceCapabilities({
    required this.isLocalDemo,
    required this.canUseSyncedHabits,
  });

  final bool isLocalDemo;
  final bool canUseSyncedHabits;

  factory AppSurfaceCapabilities.forSession({
    required AppSession? session,
    required bool useMockData,
    required bool hasSupabaseClient,
  }) {
    final isLocalDemo = useMockData ||
        session?.isGuestSession == true ||
        session?.profile.authProvider == 'guest' ||
        session?.profile.email.toLowerCase() == 'demo@personal-coach.local';

    return AppSurfaceCapabilities(
      isLocalDemo: isLocalDemo,
      canUseSyncedHabits:
          !isLocalDemo && session?.isAuthenticated == true && hasSupabaseClient,
    );
  }
}

final appSurfaceCapabilitiesProvider = Provider<AppSurfaceCapabilities>((ref) {
  final config = ref.watch(appConfigProvider);
  final client = ref.watch(supabaseClientProvider);
  final session = ref.watch(authControllerProvider).valueOrNull;

  return AppSurfaceCapabilities.forSession(
    session: session,
    useMockData: config.useMockData,
    hasSupabaseClient: client != null,
  );
});
