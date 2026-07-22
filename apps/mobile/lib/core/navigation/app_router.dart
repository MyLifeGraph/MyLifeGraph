import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../capabilities/app_surface_capabilities.dart';
import '../../features/auth/presentation/pages/auth_page.dart';
import '../../features/auth/presentation/pages/onboarding_page.dart';
import '../../features/auth/presentation/pages/password_recovery_page.dart';
import '../../features/auth/presentation/providers/auth_providers.dart';
import '../../features/calendar_integration/presentation/pages/calendar_integration_page.dart';
import '../../features/coach/presentation/pages/coach_page.dart';
import '../../features/deadline_plans/domain/deadline_plan.dart';
import '../../features/deadline_plans/presentation/pages/deadline_plans_page.dart';
import '../../features/dashboard/presentation/pages/dashboard_page.dart';
import '../../features/focus/domain/focus_session.dart';
import '../../features/focus/presentation/pages/focus_session_page.dart';
import '../../features/insights/presentation/pages/insights_page.dart';
import '../../features/notifications/presentation/pages/notifications_page.dart';
import '../../features/notifications/presentation/pages/notification_settings_page.dart';
import '../../features/planner/presentation/pages/planner_page.dart';
import '../../features/quick_action/presentation/pages/habit_completion_page.dart';
import '../../features/quick_action/presentation/pages/habit_management_page.dart';
import '../../features/quick_action/presentation/pages/morning_calibration_page.dart';
import '../../features/quick_action/presentation/pages/quick_mood_check_in_page.dart';
import '../../features/quick_action/presentation/pages/quick_action_page.dart';
import '../../features/settings/presentation/pages/settings_page.dart';
import '../../features/shell/presentation/main_shell.dart';
import '../../features/weekly_review/presentation/pages/weekly_review_page.dart';
import 'app_routes.dart';

const _postAuthContinuationParameter = 'continue';
const _postAuthContinuationPaths = <String>{
  '/',
  AppRoutes.dashboard,
  AppRoutes.onboarding,
  AppRoutes.settings,
  AppRoutes.notificationSettings,
  AppRoutes.calendarIntegration,
  AppRoutes.preparationPlans,
  AppRoutes.planner,
  AppRoutes.insights,
  AppRoutes.quickAction,
  AppRoutes.quickMoodCheckIn,
  AppRoutes.morningCalibration,
  AppRoutes.habitCompletion,
  AppRoutes.habitManagement,
  AppRoutes.weeklyReview,
  AppRoutes.alerts,
  AppRoutes.notifications,
  AppRoutes.dailyCheckIn,
  AppRoutes.deepWork,
  AppRoutes.coach,
  AppRoutes.more,
};

final appRouterProvider = Provider<GoRouter>((ref) {
  Uri? pendingPostAuthLocation;
  final router = GoRouter(
    initialLocation: AppRoutes.dashboard,
    redirect: (context, state) {
      final authState = ref.read(authControllerProvider);
      final passwordRecoveryActive = ref.read(passwordRecoveryActiveProvider);
      final path = state.uri.path;
      final isAuthRoute = path == AppRoutes.auth;
      final isPasswordRecoveryRoute = path == AppRoutes.passwordRecovery;

      if (passwordRecoveryActive) {
        return isPasswordRecoveryRoute ? null : AppRoutes.passwordRecovery;
      }

      if (isPasswordRecoveryRoute) {
        return AppRoutes.auth;
      }

      if (authState.isLoading) {
        if (isAuthRoute) return null;
        pendingPostAuthLocation = _validPostAuthLocation(state.uri);
        return _authLocationFor(state.uri);
      }

      final session = authState.valueOrNull;
      final isOnboardingRoute = path == AppRoutes.onboarding;
      final isEditingOnboarding =
          isOnboardingRoute && state.uri.queryParameters['edit'] == '1';

      if (session == null) {
        if (isAuthRoute) return null;
        pendingPostAuthLocation = _validPostAuthLocation(state.uri);
        return _authLocationFor(state.uri);
      }

      if (session.requiresOnboarding && !isOnboardingRoute) {
        pendingPostAuthLocation = null;
        return AppRoutes.onboarding;
      }

      if (isAuthRoute) {
        final continuation = _postAuthContinuation(state.uri) ??
            pendingPostAuthLocation?.toString();
        pendingPostAuthLocation = null;
        return continuation ?? AppRoutes.dashboard;
      }

      if (!session.requiresOnboarding &&
          isOnboardingRoute &&
          !isEditingOnboarding) {
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
        path: AppRoutes.passwordRecovery,
        builder: (context, state) => const PasswordRecoveryPage(),
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
            path: AppRoutes.notificationSettings,
            redirect: (context, state) =>
                ref.read(appSurfaceCapabilitiesProvider).canUseSyncedExecution
                    ? null
                    : AppRoutes.settings,
            builder: (context, state) => const NotificationSettingsPage(),
          ),
          GoRoute(
            path: AppRoutes.calendarIntegration,
            builder: (context, state) => const CalendarIntegrationPage(),
          ),
          GoRoute(
            path: AppRoutes.preparationPlans,
            builder: (context, state) => DeadlinePlansPage(
              initialKind: DeadlinePlanKind.fromCode(
                state.uri.queryParameters['kind'],
              ),
              initialPlanId: state.uri.queryParameters['plan_id'],
              openInitialReplan:
                  state.uri.queryParameters['action'] == 'replan',
              sourceCalendarEventId:
                  state.uri.queryParameters['calendar_event_id'],
            ),
          ),
          GoRoute(
            path: AppRoutes.planner,
            builder: (context, state) => const PlannerPage(),
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
                ref.read(appSurfaceCapabilitiesProvider).canUseSyncedHabits
                    ? null
                    : AppRoutes.quickAction,
            builder: (context, state) => const HabitCompletionPage(),
          ),
          GoRoute(
            path: AppRoutes.habitManagement,
            redirect: (context, state) =>
                ref.read(appSurfaceCapabilitiesProvider).canUseSyncedHabits
                    ? null
                    : AppRoutes.planner,
            builder: (context, state) => const HabitManagementPage(),
          ),
          GoRoute(
            path: AppRoutes.weeklyReview,
            redirect: (context, state) =>
                ref.read(appSurfaceCapabilitiesProvider).canUseWeeklyReview
                    ? null
                    : AppRoutes.dashboard,
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
            redirect: (context, state) =>
                ref.read(appSurfaceCapabilitiesProvider).canUseSyncedExecution
                    ? null
                    : AppRoutes.quickAction,
            builder: (context, state) => FocusSessionPage(
              initialTargetKind: FocusTargetKind.fromCode(
                state.uri.queryParameters['target_kind'],
              ),
              initialTargetId: state.uri.queryParameters['target_id'],
              initialPlannedMinutes: _focusMinutes(
                state.uri.queryParameters['planned_minutes'],
              ),
            ),
          ),
          GoRoute(
            path: AppRoutes.coach,
            redirect: (context, state) =>
                ref.read(appSurfaceCapabilitiesProvider).canShowCoachSurface
                    ? null
                    : AppRoutes.settings,
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
  ref.listen(authControllerProvider, (_, __) => router.refresh());
  ref.listen(passwordRecoveryActiveProvider, (_, __) => router.refresh());
  ref.listen(appSurfaceCapabilitiesProvider, (_, __) => router.refresh());
  ref.onDispose(router.dispose);
  return router;
});

int? _focusMinutes(String? value) {
  if (value == null || !RegExp(r'^\d{1,3}$').hasMatch(value)) return null;
  final minutes = int.tryParse(value);
  return minutes != null && minutes >= 5 && minutes <= 240 ? minutes : null;
}

String _authLocationFor(Uri intendedLocation) {
  return Uri(
    path: AppRoutes.auth,
    queryParameters: {
      _postAuthContinuationParameter: intendedLocation.toString(),
    },
  ).toString();
}

String? _postAuthContinuation(Uri authLocation) {
  final raw = authLocation.queryParameters[_postAuthContinuationParameter];
  if (raw == null || raw.isEmpty) return null;

  final target = Uri.tryParse(raw);
  return target == null ? null : _validPostAuthLocation(target)?.toString();
}

Uri? _validPostAuthLocation(Uri target) {
  if (target.hasScheme ||
      target.hasAuthority ||
      target.fragment.isNotEmpty ||
      !_postAuthContinuationPaths.contains(target.path)) {
    return null;
  }
  return target;
}
