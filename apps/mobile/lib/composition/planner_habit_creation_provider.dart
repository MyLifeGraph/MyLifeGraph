import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/capabilities/app_surface_capabilities.dart';
import '../core/supabase/supabase_providers.dart';
import '../features/planner/domain/planner.dart';
import '../features/quick_action/domain/habit_v1.dart';
import 'auth_providers.dart';
import 'habit_action_providers.dart';

typedef PlannerManualHabitWrite =
    Future<void> Function(PlannerHabitDraft draft, String requestId);

/// Composition seam: Planner creates an untimed manual Habit using the existing
/// owner-scoped, idempotent command, never a fabricated planning proposal.
final plannerManualHabitWriteProvider = Provider<PlannerManualHabitWrite?>((
  ref,
) {
  final session = ref.watch(authControllerProvider).valueOrNull;
  final capabilities = ref.watch(appSurfaceCapabilitiesProvider);
  final client = ref.watch(supabaseClientProvider);
  final owner = client?.auth.currentUser?.id;
  if (session?.isAuthenticated != true ||
      !capabilities.canUseSyncedExecution ||
      owner == null) {
    return null;
  }
  final source = ref.watch(habitManagementPageDataSourceProvider);
  if (source == null) return null;
  return (draft, requestId) async {
    if (client?.auth.currentUser?.id != owner ||
        draft.targetId != null ||
        draft.durationMinutes != null) {
      throw StateError('Habit owner or draft changed.');
    }
    final cadence = switch (draft.cadenceKind) {
      'daily' => HabitCadence.daily(),
      'weekdays' => HabitCadence.weekdays(draft.scheduledWeekdays),
      'weekly_target' => HabitCadence.weeklyTarget(draft.weeklyTarget),
      _ => throw StateError('Unsupported habit cadence.'),
    };
    await source.createHabit(
      habitId: requestId,
      title: draft.title,
      description: draft.description,
      cadence: cadence,
    );
  };
});
