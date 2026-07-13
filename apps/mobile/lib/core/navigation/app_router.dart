import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../capabilities/app_surface_capabilities.dart';
import '../../features/auth/presentation/pages/auth_page.dart';
import '../../features/auth/presentation/pages/onboarding_page.dart';
import '../../features/auth/presentation/providers/auth_providers.dart';
import '../../features/calendar_integration/presentation/pages/calendar_integration_page.dart';
import '../../features/coach/presentation/pages/coach_page.dart';
import '../../features/dashboard/presentation/pages/dashboard_page.dart';
import '../../features/focus/domain/focus_session.dart';
import '../../features/focus/presentation/pages/focus_session_page.dart';
import '../../features/insights/presentation/pages/insights_page.dart';
import '../../features/notifications/presentation/pages/notifications_page.dart';
import '../../features/quick_action/presentation/pages/habit_completion_page.dart';
import '../../features/quick_action/presentation/pages/habit_management_page.dart';
import '../../features/quick_action/presentation/pages/morning_calibration_page.dart';
import '../../features/quick_action/presentation/pages/quick_mood_check_in_page.dart';
import '../../features/quick_action/presentation/pages/quick_action_page.dart';
import '../../features/settings/presentation/pages/settings_page.dart';
import '../../features/shell/presentation/main_shell.dart';
import '../../features/weekly_review/presentation/pages/weekly_review_page.dart';
import 'app_routes.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authControllerProvider);
  final capabilities = ref.watch(appSurfaceCapabilitiesProvider);

  return GoRouter(
    initialLocation: AppRoutes.dashboard,
    redirect: (context, state) {
      final path = state.uri.path;
      final isAuthRoute = path == AppRoutes.auth;

      if (authState.isLoading) {
        return isAuthRoute ? null : AppRoutes.auth;
      }

      final session = authState.valueOrNull;
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
        builder: (context, state) => OnboardingPage(
          editing: state.uri.queryParameters['edit'] == '1',
        ),
      ),
      GoRoute(
        path: AppRoutes.quickMoodCheckIn,
        builder: (context, state) => const QuickMoodCheckInPage(),
      ),
      GoRoute(
        path: AppRoutes.morningCalibration,
        builder: (context, state) => const MorningCalibrationPage(),
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
            path: AppRoutes.calendarIntegration,
            builder: (context, state) => const CalendarIntegrationPage(),
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
            path: AppRoutes.habitCompletion,
            redirect: (context, state) =>
                capabilities.canUseSyncedHabits ? null : AppRoutes.quickAction,
            builder: (context, state) => const HabitCompletionPage(),
          ),
          GoRoute(
            path: AppRoutes.habitManagement,
            redirect: (context, state) =>
                capabilities.canUseSyncedHabits ? null : AppRoutes.quickAction,
            builder: (context, state) => const HabitManagementPage(),
          ),
          GoRoute(
            path: AppRoutes.weeklyReview,
            redirect: (context, state) =>
                capabilities.canUseWeeklyReview ? null : AppRoutes.dashboard,
            builder: (context, state) => const WeeklyReviewPage(),
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
            redirect: (context, state) => AppRoutes.quickMoodCheckIn,
          ),
          GoRoute(
            path: AppRoutes.deepWork,
            redirect: (context, state) => capabilities.canUseSyncedExecution
                ? null
                : AppRoutes.quickAction,
            builder: (context, state) => FocusSessionPage(
              initialTargetKind: FocusTargetKind.fromCode(
                state.uri.queryParameters['target_kind'],
              ),
              initialTargetId: state.uri.queryParameters['target_id'],
            ),
          ),
          GoRoute(
            path: AppRoutes.coach,
            builder: (context, state) => const CoachPage(),
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
