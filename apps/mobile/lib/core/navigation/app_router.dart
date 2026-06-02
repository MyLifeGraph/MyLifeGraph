import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/pages/auth_page.dart';
import '../../features/auth/presentation/pages/onboarding_page.dart';
import '../../features/auth/presentation/providers/auth_providers.dart';
import '../../features/dashboard/presentation/pages/dashboard_page.dart';
import '../../features/insights/presentation/pages/insights_page.dart';
import '../../features/more/presentation/pages/more_page.dart';
import '../../features/notifications/presentation/pages/daily_check_in_page.dart';
import '../../features/notifications/presentation/pages/deep_work_page.dart';
import '../../features/notifications/presentation/pages/notifications_page.dart';
import '../../features/quick_action/presentation/pages/quick_mood_check_in_page.dart';
import '../../features/quick_action/presentation/pages/quick_action_page.dart';
import '../../features/settings/presentation/pages/settings_page.dart';
import '../../features/shell/presentation/main_shell.dart';
import 'app_routes.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authControllerProvider);

  return GoRouter(
    initialLocation: AppRoutes.dashboard,
    redirect: (context, state) {
      if (authState.isLoading) {
        return null;
      }

      final session = authState.valueOrNull;
      final path = state.uri.path;
      final isAuthRoute = path == AppRoutes.auth;
      final isOnboardingRoute = path == AppRoutes.onboarding;
      final isEditingOnboarding =
          isOnboardingRoute && state.uri.queryParameters['edit'] == '1';

      if (session == null) {
        return isAuthRoute ? null : AppRoutes.auth;
      }

      if (session.requiresOnboarding && !isOnboardingRoute) {
        return AppRoutes.onboarding;
      }

      if (!session.requiresOnboarding &&
          (isAuthRoute || (isOnboardingRoute && !isEditingOnboarding))) {
        return AppRoutes.dashboard;
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/',
        redirect: (context, state) => AppRoutes.dashboard,
      ),
      GoRoute(
        path: AppRoutes.auth,
        builder: (context, state) => const AuthPage(),
      ),
      GoRoute(
        path: AppRoutes.onboarding,
        builder: (context, state) => const OnboardingPage(),
      ),
      GoRoute(
        path: AppRoutes.quickMoodCheckIn,
        builder: (context, state) => const QuickMoodCheckInPage(),
      ),
      ShellRoute(
        builder: (context, state, child) => MainShell(
          currentPath: state.uri.path,
          child: child,
        ),
        routes: [
          GoRoute(
            path: AppRoutes.dashboard,
            builder: (context, state) => const DashboardPage(),
          ),
          GoRoute(
            path: AppRoutes.settings,
            builder: (context, state) => const SettingsPage(),
          ),
          GoRoute(
            path: AppRoutes.insights,
            builder: (context, state) => const InsightsPage(),
          ),
          GoRoute(
            path: AppRoutes.quickAction,
            builder: (context, state) => const QuickActionPage(),
          ),
          GoRoute(
            path: AppRoutes.alerts,
            builder: (context, state) => const NotificationsPage(),
          ),
          GoRoute(
            path: AppRoutes.notifications,
            redirect: (context, state) => AppRoutes.alerts,
          ),
          GoRoute(
            path: AppRoutes.dailyCheckIn,
            builder: (context, state) => const DailyCheckInPage(),
          ),
          GoRoute(
            path: AppRoutes.deepWork,
            builder: (context, state) => const DeepWorkPage(),
          ),
          GoRoute(
            path: AppRoutes.coach,
            builder: (context, state) => const MorePage(),
          ),
          GoRoute(
            path: AppRoutes.more,
            redirect: (context, state) => AppRoutes.coach,
          ),
        ],
      ),
    ],
  );
});
