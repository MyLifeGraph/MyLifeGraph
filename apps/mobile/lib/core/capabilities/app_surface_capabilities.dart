import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/domain/app_session.dart';
import '../../features/auth/presentation/providers/auth_providers.dart';
import '../config/app_config.dart';
import '../supabase/supabase_providers.dart';

class AppSurfaceCapabilities {
  const AppSurfaceCapabilities({
    required this.isLocalDemo,
    required this.canUseSyncedHabits,
    this.canUseSyncedExecution = false,
    this.canUseWeeklyReview = false,
    this.canUseCalendarIntegration = false,
    this.canUseDeadlinePlanner = false,
    this.canAccessCoachBackend = false,
    this.canShowCoachSurface = false,
  });

  final bool isLocalDemo;
  final bool canUseSyncedHabits;
  final bool canUseSyncedExecution;
  final bool canUseWeeklyReview;
  final bool canUseCalendarIntegration;
  final bool canUseDeadlinePlanner;
  final bool canAccessCoachBackend;
  final bool canShowCoachSurface;

  factory AppSurfaceCapabilities.forSession({
    required AppSession? session,
    required bool useMockData,
    required bool hasSupabaseClient,
    bool coachSurfaceEnabled = false,
  }) {
    final profile = session?.profile;
    final authProvider = profile?.authProvider.trim().toLowerCase();
    final isLocalDemo = useMockData ||
        session?.isGuestSession == true ||
        profile?.role == AppRole.guest ||
        authProvider == 'guest' ||
        authProvider == 'anonymous' ||
        profile?.email.toLowerCase() == 'demo@personal-coach.local';

    final canUseSyncedExecution =
        !isLocalDemo && session?.isAuthenticated == true && hasSupabaseClient;
    return AppSurfaceCapabilities(
      isLocalDemo: isLocalDemo,
      canUseSyncedHabits: canUseSyncedExecution,
      canUseSyncedExecution: canUseSyncedExecution,
      canUseWeeklyReview: canUseSyncedExecution,
      canUseCalendarIntegration: canUseSyncedExecution,
      canUseDeadlinePlanner: canUseSyncedExecution,
      canAccessCoachBackend: coachSurfaceEnabled && canUseSyncedExecution,
      canShowCoachSurface: coachSurfaceEnabled,
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
    coachSurfaceEnabled: config.coachSurfaceEnabled,
  );
});
