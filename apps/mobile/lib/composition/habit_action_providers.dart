import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/supabase/supabase_providers.dart';
import '../features/quick_action/data/habit_completion_supabase_data_source.dart';
import 'profile_local_date_providers.dart';

final habitCompletionPageDataSourceProvider =
    Provider<HabitCompletionSupabaseDataSource?>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return client == null
      ? null
      : HabitCompletionSupabaseDataSource(
          client,
          todayProvider: ref.watch(profileLocalDateSourceProvider).today,
        );
});

final habitManagementPageDataSourceProvider =
    Provider<HabitCompletionSupabaseDataSource?>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return client == null
      ? null
      : HabitCompletionSupabaseDataSource(
          client,
          todayProvider: ref.watch(profileLocalDateSourceProvider).today,
        );
});
